import CalendarDomain
import CoreGraphics
import EventKit
import Foundation

/// Read this again when either process activates. Permission sharing between the
/// containing app and extension must be measured on a signed physical device.
public enum AppleCalendarPermission: String, Sendable, CaseIterable {
    case notDetermined, fullAccess, writeOnly, denied, restricted, unknown

    public var canListCalendars: Bool { self == .fullAccess }

    public var explanation: String {
        switch self {
        case .notDetermined:
            return "Choose Apple to request access to calendars on this iPhone."
        case .fullAccess:
            return "Full access: calendars on this iPhone can be listed and writable calendars selected."
        case .writeOnly:
            return "Write-only access cannot show real destination calendars. Request full access to choose a calendar."
        case .denied:
            return "Calendar access was denied. You can change Calendar access in Settings."
        case .restricted:
            return "Calendar access is restricted on this device."
        case .unknown:
            return "This calendar authorization state is not supported."
        }
    }
}

public enum AppleProbeError: Error, LocalizedError, Sendable {
    case fullAccessRequired(AppleCalendarPermission)
    case destinationUnavailable
    case invalidDates

    public var errorDescription: String? {
        switch self {
        case .fullAccessRequired(let status): return status.explanation
        case .destinationUnavailable:
            return "This calendar is no longer a writable destination. Choose a calendar again."
        case .invalidDates:
            return "The event's end must be later than its start, with valid dates and time zones."
        }
    }
}

public struct AppleSaveResult: Sendable {
    public let eventID: String?
    public let destinationName: String
    public let hadUnexpectedAlarmsAfterSave: Bool
    public let availabilityDescription: String

    /// Saving confirms the device store accepted the copy; account sync may still be pending.
    public var confirmation: String {
        "Added to \(destinationName) in the device calendar store. Remote account sync may still be pending."
    }
}

/// A deliberately small M0 probe, not the M1 event browser or M3 import journal.
/// The actor keeps EventKit objects off the main actor and never exports them.
/// Call `createCopy` only from an explicit Add action; access requests never save.
@available(macOS 14.0, *)
public actor EventKitProbe {
    private let store = EKEventStore()

    public init() {}

    public nonisolated static func permissionStatus() -> AppleCalendarPermission {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: return .notDetermined
        case .fullAccess: return .fullAccess
        case .writeOnly: return .writeOnly
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .unknown
        }
    }

    /// Must be invoked by a visible Apple permission button, never during activation.
    @discardableResult
    public func requestFullAccess() async throws -> AppleCalendarPermission {
        let status = Self.permissionStatus()
        guard status == .notDetermined || status == .writeOnly else { return status }
        _ = try await store.requestFullAccessToEvents()
        // A store created before the prompt can otherwise retain stale state.
        store.reset()
        return Self.permissionStatus()
    }

    public func listCalendars(writableOnly: Bool = false) throws -> [CalendarRef] {
        try requireFullAccess()
        try Task.checkCancellation()
        return store.calendars(for: .event)
            .filter { !writableOnly || $0.allowsContentModifications }
            .map(calendarReference)
            .sorted {
                let accountOrder = $0.accountLabel.localizedStandardCompare($1.accountLabel)
                if accountOrder != .orderedSame { return accountOrder == .orderedAscending }
                let nameOrder = $0.displayName.localizedStandardCompare($1.displayName)
                if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
                return $0.calendarID < $1.calendarID
            }
    }

    /// Re-fetches the chosen destination on every save. It does not fall back to
    /// a default calendar when a selection is stale, removed, or read-only.
    /// M0 callers must not automatically retry an uncertain EventKit save.
    public func createCopy(event: SharedEvent, destination: CalendarRef) throws -> AppleSaveResult {
        try requireFullAccess()
        try event.validate()
        try Task.checkCancellation()
        guard destination.provider == .apple,
              let calendar = store.calendar(withIdentifier: destination.calendarID),
              calendar.source.sourceIdentifier == destination.accountKey,
              calendar.allowedEntityTypes.contains(.event),
              calendar.allowsContentModifications else {
            throw AppleProbeError.destinationUnavailable
        }

        // This is always a new ordinary event; no source EKEvent is ever mutated.
        let copy = EKEvent(eventStore: store)
        copy.calendar = calendar
        copy.title = event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled event" : event.title
        copy.location = event.location
        copy.notes = event.note
        copy.url = nil
        copy.recurrenceRules = nil
        copy.alarms = []

        switch event.time {
        case .allDay(let startDate, let endDateExclusive):
            // All-day values are civil dates. Materialize them in the current
            // device zone rather than interpreting them as UTC instants.
            let zone = TimeZone.current
            copy.startDate = try startDate.date(in: zone)
            copy.endDate = try endDateExclusive.date(in: zone)
            copy.isAllDay = true
            copy.timeZone = nil
        case .timed(let startInstant, let endInstant, let startZone, let endZone):
            guard startInstant.timeIntervalSinceReferenceDate.isFinite,
                  endInstant.timeIntervalSinceReferenceDate.isFinite,
                  startZone.map({ TimeZone(identifier: $0) != nil }) ?? true,
                  endZone.map({ TimeZone(identifier: $0) != nil }) ?? true else {
                throw AppleProbeError.invalidDates
            }
            copy.startDate = startInstant
            copy.endDate = endInstant
            copy.isAllDay = false
            // EventKit exposes one time zone; preserve both actual instants even
            // if a message carries distinct start/end display zone labels.
            copy.timeZone = startZone.flatMap(TimeZone.init(identifier:))
        }
        guard copy.endDate > copy.startDate else { throw AppleProbeError.invalidDates }

        if calendar.supportedEventAvailabilities.contains(.free) {
            copy.availability = .free
        } else {
            copy.availability = .notSupported
        }

        // Check cancellation immediately before the mutation, never after it:
        // reporting cancellation after a successful commit invites duplicate saves.
        try Task.checkCancellation()
        try store.save(copy, span: .thisEvent, commit: true)

        let persisted = copy.eventIdentifier.flatMap { store.event(withIdentifier: $0) } ?? copy
        let availability: String
        switch persisted.availability {
        case .free: availability = "Free"
        case .busy: availability = "Busy"
        case .tentative: availability = "Tentative"
        case .unavailable: availability = "Unavailable"
        case .notSupported: availability = "Not supported by this calendar"
        @unknown default: availability = "Unknown"
        }
        return AppleSaveResult(
            eventID: persisted.eventIdentifier,
            destinationName: calendar.title,
            hadUnexpectedAlarmsAfterSave: !(persisted.alarms ?? []).isEmpty,
            availabilityDescription: availability
        )
    }

    private func requireFullAccess() throws {
        let status = Self.permissionStatus()
        guard status.canListCalendars else { throw AppleProbeError.fullAccessRequired(status) }
    }

    private func calendarReference(_ calendar: EKCalendar) -> CalendarRef {
        CalendarRef(
            provider: .apple,
            accountKey: calendar.source.sourceIdentifier,
            calendarID: calendar.calendarIdentifier,
            displayName: calendar.title,
            accountLabel: calendar.source.title,
            colorHex: colorHex(calendar),
            isWritable: calendar.allowsContentModifications
        )
    }

    private func colorHex(_ calendar: EKCalendar) -> String? {
        guard let color = calendar.cgColor,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let rgb = color.converted(to: space, intent: .defaultIntent, options: nil),
              let parts = rgb.components, parts.count >= 3 else { return nil }
        let bytes = parts.prefix(3).map { Int((min(max($0, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2])
    }
}
