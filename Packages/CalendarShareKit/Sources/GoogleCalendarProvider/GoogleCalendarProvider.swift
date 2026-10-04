import AuthorizationStore
import CalendarDomain
import Foundation

public enum GoogleCalendarError: Error, LocalizedError, Sendable {
    case network, response, permissionChanged, accountChanged, rateLimited
    case authorizationRejected
    case uncertainWrite, rejectedWrite(Int), server(Int)

    public var errorDescription: String? {
        switch self {
        case .network: return "Google is unavailable. Check the connection, then retry the calendar list."
        case .response: return "Google returned an incomplete calendar response."
        case .permissionChanged: return "This calendar is no longer writable. Choose a calendar again."
        case .accountChanged: return "The Google account changed. Choose a destination again."
        case .rateLimited: return "Google temporarily limited requests. Wait before trying again."
        case .authorizationRejected: return "Google rejected this connection. Reconnect in Calendar Share."
        case .uncertainWrite: return "The save outcome is uncertain. Check the destination calendar. M0 blocks another attempt; reconciliation is a later milestone."
        case .rejectedWrite(let code): return "Google rejected the save (HTTP \(code)). Check calendar access and the test configuration."
        case .server(let code): return "Google is unavailable (HTTP \(code)). Try the calendar list later."
        }
    }
}

/// Only the M0 calendar-list and explicit sample-copy probes. Event browsing is M2.
public final class GoogleCalendarProvider: @unchecked Sendable {
    private let authorizationStore: GoogleAuthorizationStore
    private let session: URLSession

    public init(authorizationStore: GoogleAuthorizationStore) {
        self.authorizationStore = authorizationStore
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        session = URLSession(configuration: configuration)
    }

    public func listCalendars(purpose: GoogleAuthorizationPurpose) async throws -> [CalendarRef] {
        let result = try await authorizedCalendars(purpose: purpose)
        return result.0
    }

    private func authorizedCalendars(purpose: GoogleAuthorizationPurpose) async throws -> ([CalendarRef], GoogleAccessToken) {
        let token = try await authorizationStore.accessToken(purpose: purpose)
        do {
            return (try await listCalendars(purpose: purpose, token: token), token)
        } catch GoogleCalendarError.authorizationRejected {
            // A server can reject a token before its local expiry. Retry this GET-only
            // probe once with a real refresh; never apply this retry to Events.insert.
            let refreshed = try await authorizationStore.accessToken(purpose: purpose, forceRefresh: true)
            do {
                return (try await listCalendars(purpose: purpose, token: refreshed), refreshed)
            } catch GoogleCalendarError.authorizationRejected {
                try await authorizationStore.requireReconnect(accountKey: refreshed.connection.accountKey,
                                                               rejectedAccessToken: refreshed.value)
                throw GoogleAuthorizationError.reconnect
            }
        }
    }

    private func listCalendars(purpose: GoogleAuthorizationPurpose, token: GoogleAccessToken) async throws -> [CalendarRef] {
        struct Page: Decodable {
            struct Entry: Decodable {
                let id: String
                let summary: String?
                let summaryOverride: String?
                let backgroundColor: String?
                let accessRole: String?
                let deleted: Bool?
            }
            let items: [Entry]?
            let nextPageToken: String?
        }
        var nextPage: String?
        var seenPages = Set<String>()
        var seenCalendars = Set<String>()
        var calendars: [CalendarRef] = []
        repeat {
            try Task.checkCancellation()
            var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!
            components.queryItems = [URLQueryItem(name: "maxResults", value: "250"),
                                     URLQueryItem(name: "showDeleted", value: "false"),
                                     URLQueryItem(name: "showHidden", value: "true")]
            if let nextPage { components.queryItems?.append(URLQueryItem(name: "pageToken", value: nextPage)) }
            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await read(request)
            if response.statusCode == 401 {
                throw GoogleCalendarError.authorizationRejected
            }
            guard response.statusCode == 200 else {
                if response.statusCode == 429 { throw GoogleCalendarError.rateLimited }
                if response.statusCode == 403 { throw GoogleCalendarError.permissionChanged }
                throw GoogleCalendarError.server(response.statusCode)
            }
            guard let page = try? JSONDecoder().decode(Page.self, from: data) else { throw GoogleCalendarError.response }
            for entry in page.items ?? [] {
                guard entry.deleted != true, let role = entry.accessRole,
                      ["reader", "writer", "owner"].contains(role), seenCalendars.insert(entry.id).inserted else { continue }
                let writable = role == "writer" || role == "owner"
                if purpose == .save && !writable { continue }
                calendars.append(CalendarRef(provider: .google, accountKey: token.connection.accountKey,
                                             calendarID: entry.id,
                                             displayName: entry.summaryOverride ?? entry.summary ?? "Google calendar",
                                             accountLabel: "Direct Google account", colorHex: entry.backgroundColor,
                                             isWritable: writable))
            }
            nextPage = page.nextPageToken
            if let nextPage, !seenPages.insert(nextPage).inserted { throw GoogleCalendarError.response }
        } while nextPage != nil
        return calendars
    }

    /// Call only after an explicit Add tap and after persisting the M0 attempted-write
    /// guard. This never retries a POST. Parent UI must keep an uncertain attempt locked.
    public func createSampleCopy(snapshot: ShareSnapshot, destination: CalendarRef, operationID: UUID) async throws -> String {
        guard destination.provider == .google, destination.isWritable else { throw GoogleCalendarError.permissionChanged }
        let body = try Self.makeEventBody(snapshot: snapshot, operationID: operationID)
        let (current, token) = try await authorizedCalendars(purpose: .save)
        guard token.connection.accountKey == destination.accountKey else { throw GoogleCalendarError.accountChanged }
        guard current.contains(where: { $0.calendarID == destination.calendarID && $0.isWritable }) else {
            throw GoogleCalendarError.permissionChanged
        }
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3")!
        // A calendar ID must remain one path segment, including IDs containing slashes.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let calendarID = destination.calendarID.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw GoogleCalendarError.response
        }
        components.percentEncodedPath = "/calendar/v3/calendars/\(calendarID)/events"
        components.queryItems = [URLQueryItem(name: "sendUpdates", value: "none")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw GoogleCalendarError.uncertainWrite }
        guard let response = response as? HTTPURLResponse else { throw GoogleCalendarError.uncertainWrite }
        if response.statusCode == 401 {
            try await authorizationStore.requireReconnect(accountKey: token.connection.accountKey,
                                                           rejectedAccessToken: token.value)
        }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 409 || response.statusCode == 408 || response.statusCode >= 500 {
                throw GoogleCalendarError.uncertainWrite
            }
            throw GoogleCalendarError.rejectedWrite(response.statusCode)
        }
        struct Saved: Decodable { let id: String }
        guard let saved = try? JSONDecoder().decode(Saved.self, from: data),
              saved.id == Self.eventID(operationID) else { throw GoogleCalendarError.uncertainWrite }
        return saved.id
    }

    /// An allowlist mapper; no source IDs, attendees, recurrence or conferencing fields.
    public static func makeEventBody(snapshot: ShareSnapshot, operationID: UUID) throws -> Data {
        guard snapshot.schemaVersion == 1 else { throw DomainError.invalidField("schema version") }
        try snapshot.event.validate()
        var body: [String: Any] = [
            "id": eventID(operationID), "summary": snapshot.event.displayTitle,
            "eventType": "default", "transparency": "transparent",
            "reminders": ["useDefault": false, "overrides": []] as [String: Any],
            "extendedProperties": ["private": ["calendarShareM0Operation": operationID.uuidString.lowercased()]]
        ]
        if let location = snapshot.event.location { body["location"] = location }
        if let note = snapshot.event.note { body["description"] = note }
        switch snapshot.event.time {
        case let .allDay(startDate, endDateExclusive):
            body["start"] = ["date": startDate.description]
            body["end"] = ["date": endDateExclusive.description]
        case let .timed(startInstant, endInstant, startTimeZone, endTimeZone):
            var start = ["dateTime": EventTimestamp.string(startInstant)]
            var end = ["dateTime": EventTimestamp.string(endInstant)]
            if let startTimeZone { start["timeZone"] = startTimeZone }
            if let endTimeZone { end["timeZone"] = endTimeZone }
            body["start"] = start
            body["end"] = end
        }
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    private static func eventID(_ operationID: UUID) -> String {
        // Lowercase UUID hex is a subset of Google's base32hex event-ID alphabet.
        "m0" + operationID.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    private func read(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw GoogleCalendarError.response }
            return (data, response)
        } catch is CancellationError { throw CancellationError() }
        catch let error as GoogleCalendarError { throw error }
        catch { throw GoogleCalendarError.network }
    }
}
