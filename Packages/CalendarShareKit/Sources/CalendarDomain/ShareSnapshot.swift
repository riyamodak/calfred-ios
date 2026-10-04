import Foundation

public enum EventTime: Hashable, Sendable, Codable {
    case timed(startInstant: Date, endInstant: Date, startTimeZone: String?, endTimeZone: String?)
    case allDay(startDate: LocalDate, endDateExclusive: LocalDate)

    public func validate() throws {
        switch self {
        case let .timed(start, end, startZone, endZone):
            guard start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite, end > start else {
                throw DomainError.invalidTimeRange
            }
            for zone in [startZone, endZone].compactMap({ $0 }) {
                guard zone.utf8.count <= 128, TimeZone.knownTimeZoneIdentifiers.contains(zone) || zone == "UTC" else {
                    throw DomainError.invalidTimeZone
                }
            }
        case let .allDay(start, end):
            guard end > start else { throw DomainError.invalidTimeRange }
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, startInstant, endInstant, startTimeZone, endTimeZone, startDate, endDateExclusive
    }
    public init(from decoder: Decoder) throws {
        try rejectUnknownFields(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "timed":
            guard !c.contains(.startDate), !c.contains(.endDateExclusive) else { throw DomainError.invalidField("timed date") }
            self = .timed(
                startInstant: try EventTimestamp.parse(c.decode(String.self, forKey: .startInstant)),
                endInstant: try EventTimestamp.parse(c.decode(String.self, forKey: .endInstant)),
                startTimeZone: try c.decodeIfPresent(String.self, forKey: .startTimeZone),
                endTimeZone: try c.decodeIfPresent(String.self, forKey: .endTimeZone)
            )
        case "allDay":
            guard ![CodingKeys.startInstant, .endInstant, .startTimeZone, .endTimeZone].contains(where: c.contains) else {
                throw DomainError.invalidField("all-day date")
            }
            self = .allDay(startDate: try c.decode(LocalDate.self, forKey: .startDate), endDateExclusive: try c.decode(LocalDate.self, forKey: .endDateExclusive))
        default: throw DomainError.invalidField("event time kind")
        }
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .timed(start, end, startZone, endZone):
            try c.encode("timed", forKey: .kind)
            try c.encode(EventTimestamp.string(start), forKey: .startInstant)
            try c.encode(EventTimestamp.string(end), forKey: .endInstant)
            try c.encodeIfPresent(startZone, forKey: .startTimeZone)
            try c.encodeIfPresent(endZone, forKey: .endTimeZone)
        case let .allDay(start, end):
            try c.encode("allDay", forKey: .kind)
            try c.encode(start, forKey: .startDate)
            try c.encode(end, forKey: .endDateExclusive)
        }
    }
}

public struct SharedEvent: Codable, Hashable, Sendable {
    public var title: String
    public var time: EventTime
    public var location: String?
    public var note: String?
    public var isSingleOccurrence: Bool

    public init(title: String, time: EventTime, location: String? = nil, note: String? = nil, isSingleOccurrence: Bool = false) {
        self.title = title; self.time = time; self.location = location; self.note = note
        self.isSingleOccurrence = isSingleOccurrence
    }

    public var displayTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled event" : title }

    public func validate() throws {
        guard title.utf8.count <= 3_000 else { throw DomainError.invalidField("title length") }
        guard (location?.utf8.count ?? 0) <= 3_000 else { throw DomainError.invalidField("location length") }
        guard (note?.utf8.count ?? 0) <= 3_000 else { throw DomainError.invalidField("note length") }
        try time.validate()
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case title, time, location, note, isSingleOccurrence }
    public init(from decoder: Decoder) throws {
        try rejectUnknownFields(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        time = try c.decode(EventTime.self, forKey: .time)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        isSingleOccurrence = try c.decode(Bool.self, forKey: .isSingleOccurrence)
        try validate()
    }
}

public struct ShareSnapshot: Codable, Hashable, Sendable, Identifiable {
    public let schemaVersion: Int
    public let shareId: UUID
    public let createdAt: Date
    public let event: SharedEvent
    public var id: UUID { shareId }

    public init(schemaVersion: Int = 1, shareId: UUID = UUID(), createdAt: Date = Date(), event: SharedEvent) {
        self.schemaVersion = schemaVersion; self.shareId = shareId; self.createdAt = createdAt; self.event = event
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, shareId, createdAt, event }
    public init(from decoder: Decoder) throws {
        try rejectUnknownFields(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        shareId = try c.decode(UUID.self, forKey: .shareId)
        createdAt = try EventTimestamp.parse(c.decode(String.self, forKey: .createdAt))
        event = try c.decode(SharedEvent.self, forKey: .event)
    }

    public func encode(to encoder: Encoder) throws {
        try event.validate()
        guard createdAt.timeIntervalSince1970.isFinite else { throw DomainError.invalidDate }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(shareId, forKey: .shareId)
        try c.encode(EventTimestamp.string(createdAt), forKey: .createdAt)
        try c.encode(event, forKey: .event)
    }
}

private struct AnyField: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private func rejectUnknownFields(_ decoder: Decoder, allowed: [String]) throws {
    let container = try decoder.container(keyedBy: AnyField.self)
    guard container.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
        throw DomainError.invalidField("payload field")
    }
}
