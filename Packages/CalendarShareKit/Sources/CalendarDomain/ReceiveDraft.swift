import Foundation

public enum CalendarProvider: String, Codable, Sendable { case apple, google }

/// This reference is local state; it is never encoded into a shared message.
public struct CalendarRef: Codable, Hashable, Sendable, Identifiable {
    public let provider: CalendarProvider
    public let accountKey: String
    public let calendarID: String
    public let displayName: String
    public let accountLabel: String
    public let colorHex: String?
    public let isWritable: Bool
    public var id: String { "\(provider.rawValue):\(accountKey.utf8.count):\(accountKey):\(calendarID)" }

    public init(provider: CalendarProvider, accountKey: String, calendarID: String, displayName: String, accountLabel: String, colorHex: String? = nil, isWritable: Bool) {
        self.provider = provider; self.accountKey = accountKey; self.calendarID = calendarID
        self.displayName = displayName; self.accountLabel = accountLabel; self.colorHex = colorHex; self.isWritable = isWritable
    }
}

/// Minimal M0 handoff state. Restoring it never initiates a save.
public struct ReceiveDraft: Codable, Hashable, Sendable, Identifiable {
    public let snapshot: ShareSnapshot
    public var title: String
    public var location: String
    public var note: String
    public var time: EventTime
    public var selectedDestination: CalendarRef?
    public var writeAttempted: Bool
    public var writeResult: String?
    public var id: UUID { snapshot.shareId }

    public init(snapshot: ShareSnapshot, selectedDestination: CalendarRef? = nil) {
        self.snapshot = snapshot
        title = snapshot.event.title
        location = snapshot.event.location ?? ""
        note = snapshot.event.note ?? ""
        time = snapshot.event.time
        self.selectedDestination = selectedDestination
        writeAttempted = false
        writeResult = nil
    }

    public var effectiveEvent: SharedEvent {
        SharedEvent(title: title, time: time, location: location.isEmpty ? nil : location,
                    note: note.isEmpty ? nil : note, isSingleOccurrence: snapshot.event.isSingleOccurrence)
    }

    public mutating func invalidateGoogleDestination(unlessAccountKey accountKey: String?) {
        guard let destination = selectedDestination, destination.provider == .google else { return }
        if destination.accountKey != accountKey { selectedDestination = nil }
    }

    /// Call only after a successful calendar listing. A failed/offline listing is
    /// inconclusive and must not discard edits or a potentially valid selection.
    public mutating func revalidateDestination(in calendars: [CalendarRef], provider: CalendarProvider) {
        guard let destination = selectedDestination, destination.provider == provider else { return }
        selectedDestination = calendars.first { $0.id == destination.id && $0.isWritable }
    }
}
