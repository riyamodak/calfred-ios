import CalendarDomain
import EventKitProvider
import SwiftUI

/// The same permission and calendar inventory UI in the companion and Messages.
struct AppleCalendarsSection: View {
    let permission: AppleCalendarPermission
    let calendars: [CalendarRef]?
    let isLoading: Bool
    let error: String?
    var showCalendars = true
    let onAction: () -> Void

    var body: some View {
        Section {
            if permission.canListCalendars {
                if let calendars {
                    Text("\(calendars.count) calendars · \(calendars.filter(\.isWritable).count) writable")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if showCalendars {
                        ForEach(calendars) { calendar in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(calendar.displayName).font(.body.weight(.medium))
                                Text(calendar.accountLabel).font(.caption).foregroundStyle(.secondary)
                                Label(calendar.isWritable ? "Can save events" : "Read only",
                                      systemImage: calendar.isWritable ? "pencil" : "lock")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    if calendars.isEmpty {
                        Text("No calendars are available. Add a calendar in the Calendar app, then refresh here.")
                    }
                }
                if isLoading { ProgressView("Loading calendars…") }
                if let error { Text(error).foregroundStyle(.red) }
                Button("Refresh calendars", action: onAction).disabled(isLoading)
            } else {
                Text(permission.explanation)
                if let error { Text(error).foregroundStyle(.red) }
                if isLoading {
                    ProgressView("Checking calendar access…")
                } else if permission == .notDetermined || permission == .writeOnly {
                    Button("Allow calendar access", action: onAction)
                } else {
                    Button("Check access again", action: onAction)
                }
            }
        } header: {
            Text("Apple · Calendars on this iPhone")
        } footer: {
            if permission.canListCalendars && showCalendars {
                Text("When saving a received event, choose one of the writable calendars. Read-only calendars cannot accept new events.")
            }
        }
    }
}
