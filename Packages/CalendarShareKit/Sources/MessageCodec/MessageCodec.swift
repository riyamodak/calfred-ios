import CalendarDomain
import CryptoKit
import Foundation

public enum MessageCodecError: Error, LocalizedError, Equatable {
    case invalidBaseURL
    case unexpectedURL
    case oversizedPayload
    case malformedPayload
    case unsupportedSchema(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL: return "Configure the owned HTTPS message help URL before using this probe."
        case .unexpectedURL: return "This is not a Calendar Share message URL."
        case .oversizedPayload: return "This event is too large for a message. Shorten or omit the optional note; required fields are never truncated."
        case .malformedPayload: return "This message contains an invalid event."
        case .unsupportedSchema: return "Update the app to open this message format."
        }
    }
}

/// Self-contained transport used by the M0 Messages probe. The fragment is not authentication or encryption.
public struct MessageCodec: Sendable {
    public static let maximumURLLength = 4_500
    public static let maximumDecodedBytes = 3_375
    public let baseURL: URL

    public init(baseURL: URL) throws {
        guard let components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              components.scheme == "https", let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil, !components.path.isEmpty else {
            throw MessageCodecError.invalidBaseURL
        }
        self.baseURL = baseURL
    }

    public func encode(_ snapshot: ShareSnapshot) throws -> URL {
        let data = try canonicalData(snapshot)
        guard data.count <= Self.maximumDecodedBytes else { throw MessageCodecError.oversizedPayload }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw MessageCodecError.invalidBaseURL
        }
        components.fragment = Self.base64URL(data)
        guard let url = components.url, url.absoluteString.utf8.count <= Self.maximumURLLength else {
            throw MessageCodecError.oversizedPayload
        }
        return url
    }

    public func decode(_ url: URL) throws -> ShareSnapshot {
        guard url.absoluteString.utf8.count <= Self.maximumURLLength else { throw MessageCodecError.oversizedPayload }
        guard let actual = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let expected = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              actual.scheme == "https", actual.host == expected.host,
              actual.percentEncodedPath == expected.percentEncodedPath,
              actual.port == nil, actual.user == nil, actual.password == nil, actual.query == nil,
              let fragment = actual.percentEncodedFragment, !fragment.isEmpty else {
            throw MessageCodecError.unexpectedURL
        }
        guard fragment.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else {
            throw MessageCodecError.malformedPayload
        }
        let remainder = fragment.utf8.count % 4
        guard remainder != 1 else { throw MessageCodecError.malformedPayload }
        let padded = fragment.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            + String(repeating: "=", count: (4 - remainder) % 4)
        guard let data = Data(base64Encoded: padded), data.count <= Self.maximumDecodedBytes,
              Self.base64URL(data) == fragment else { throw MessageCodecError.malformedPayload }
        do {
            let version = try JSONDecoder().decode(VersionHeader.self, from: data).schemaVersion
            guard version == 1 else { throw MessageCodecError.unsupportedSchema(version) }
            let snapshot = try JSONDecoder().decode(ShareSnapshot.self, from: data)
            try snapshot.event.validate()
            return snapshot
        } catch let error as MessageCodecError {
            throw error
        } catch {
            throw MessageCodecError.malformedPayload
        }
    }

    /// Compare this fingerprint on sender and recipient devices; never log the full URL or event content.
    public func digest(_ snapshot: ShareSnapshot) throws -> String {
        SHA256.hash(data: try canonicalData(snapshot)).map { String(format: "%02x", $0) }.joined()
    }

    public func sampleSnapshot() -> ShareSnapshot { M0Samples.allDaySnapshot() }

    public func nearLimitSnapshot() throws -> ShareSnapshot { try M0Samples.nearLimitSnapshot(codec: self) }

    public func canonicalData(_ snapshot: ShareSnapshot) throws -> Data {
        guard snapshot.schemaVersion == 1 else { throw MessageCodecError.unsupportedSchema(snapshot.schemaVersion) }
        try snapshot.event.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(snapshot)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private struct VersionHeader: Decodable { let schemaVersion: Int }
}

public enum M0Samples {
    public static func allDaySnapshot() -> ShareSnapshot {
        // These compile-time sample dates are intentionally independent of recipient time zones.
        let start = try! LocalDate("2026-10-10")
        let end = try! LocalDate("2026-10-13")
        return ShareSnapshot(createdAt: Date(timeIntervalSince1970: 1_791_086_400), event: SharedEvent(
            title: "Trip to Chicago", time: .allDay(startDate: start, endDateExclusive: end), location: "Chicago"
        ))
    }

    public static func timedSnapshot() -> ShareSnapshot {
        let start = try! EventTimestamp.parse("2026-11-01T01:30:00-04:00")
        let end = try! EventTimestamp.parse("2026-11-01T02:30:00-05:00")
        return ShareSnapshot(createdAt: Date(timeIntervalSince1970: 1_791_086_400), event: SharedEvent(
            title: "Overnight / DST sample", time: .timed(startInstant: start, endInstant: end,
            startTimeZone: "America/New_York", endTimeZone: "America/New_York"), isSingleOccurrence: true
        ))
    }

    /// Explicitly opted-in synthetic Unicode note, built to exercise transport close to its 4,500-character cap.
    public static func nearLimitSnapshot(codec: MessageCodec) throws -> ShareSnapshot {
        let base = allDaySnapshot()
        let fragment = "🗓️ 東京 café · مرحبا · "
        var note = ""
        func snapshot(_ note: String) -> ShareSnapshot {
            ShareSnapshot(shareId: base.shareId, createdAt: base.createdAt, event: SharedEvent(
                title: "Unicode trip 🧳 — 東京 / Montréal", time: base.event.time, location: "京都 • Québec",
                note: note
            ))
        }
        // Only synthetic sample data is fitted; real sender content is never truncated.
        while (note + fragment).utf8.count <= 3_000, (try? codec.encode(snapshot(note + fragment))) != nil { note += fragment }
        while (note + "é").utf8.count <= 3_000, (try? codec.encode(snapshot(note + "é"))) != nil { note += "é" }
        while (note + ".").utf8.count <= 3_000, (try? codec.encode(snapshot(note + "."))) != nil { note += "." }
        let result = snapshot(note)
        _ = try codec.encode(result)
        return result
    }
}
