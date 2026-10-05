import CalendarDomain
import SwiftUI

/// Inventory only. Choosing a destination remains an explicit action in the receive screen.
struct GoogleCalendarInventory: View {
    let calendars: [CalendarRef]?
    let isLoading: Bool
    let error: String?
    let canWrite: Bool
    var showCalendars = true

    var body: some View {
        if isLoading { ProgressView("Loading Google calendars…") }
        if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
        if let calendars {
            Text("\(calendars.count) calendars · \(calendars.filter(\.isWritable).count) writable")
                .font(.subheadline).foregroundStyle(.secondary)
            if calendars.isEmpty { Text("Google returned no readable calendars for this account.") }
            if showCalendars {
                ForEach(calendars) { calendar in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(calendar.displayName).font(.body.weight(.medium))
                        Text(calendar.accountLabel).font(.caption).foregroundStyle(.secondary)
                        Label(calendar.isWritable ? (canWrite ? "Can save events" : "Authorize saving to add events") : "Read only",
                              systemImage: calendar.isWritable ? "pencil" : "lock")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
