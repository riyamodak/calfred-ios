import SwiftUI
import EventKit
import CalendarDomain

struct MessagesHarnessView: View {
    @ObservedObject var model: MessagesModel

    var body: some View {
        NavigationStack {
            Form {
                if let draft = model.draft {
                    Section("Received event") {
                        Text(draft.snapshot.event.displayTitle).font(.headline)
                        Text(draft.time.probeDescription)
                        Text("Saves an independent copy.")
                        if draft.snapshot.event.isSingleOccurrence { Text("This occurrence only") }
                        if let location = draft.snapshot.event.location { Text(location) }
                        if let note = draft.snapshot.event.note { Text(note) }
                    }
                    if let result = draft.writeResult {
                        Section("Save result") { Text(result).textSelection(.enabled) }
                    }
                    if !draft.writeAttempted {
                        Section("Choose a calendar") {
                            if model.calendars.isEmpty { Text("Use the connection probes below to load writable calendars. Nothing is selected automatically.") }
                            ForEach(model.calendars) { calendar in
                                Button { model.selectDestination(calendar) } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(calendar.displayName)
                                            Text("\(calendar.provider == .apple ? "Apple · On this iPhone" : "Google · Direct") · \(calendar.accountLabel)").font(.caption)
                                        }
                                        Spacer()
                                        if draft.selectedDestination?.id == calendar.id { Image(systemName: "checkmark.circle.fill") }
                                    }
                                }
                                .accessibilityAddTraits(draft.selectedDestination?.id == calendar.id ? .isSelected : [])
                            }
                            if let selected = draft.selectedDestination { Text("Selected: \(selected.displayName)") }
                        }
                        Section {
                            DisclosureGroup("Edit this copy") {
                                TextField("Title", text: binding(\.title)).accessibilityLabel("Copy title")
                                TextField("Location", text: binding(\.location)).accessibilityLabel("Copy location")
                                TextField("Note (optional)", text: binding(\.note), axis: .vertical).accessibilityLabel("Copy note")
                                Text("M0 preserves the sample dates and creates no reminders. Free is requested where supported.").font(.caption)
                            }
                        }
                    }
                    Button(draft.writeAttempted ? "Finish probe and clear pending state" : "Cancel receive", role: .destructive) { model.closeReceive() }
                } else {
                    Section("Message transport probes") {
                        Button("Insert sample event card") { model.selectSample(nearLimit: false) }
                        Button("Insert timed / DST sample card") { model.selectSample(nearLimit: false, timed: true) }
                        Button("Insert near-limit Unicode card") { model.selectSample(nearLimit: true) }
                        if model.canRetryInsertion { Button("Retry insertion") { model.retryInsertion() } }
                        Text("Default fixture shares title, dates, zone and location. The Unicode stress fixture also includes an intentional test note. Selecting again creates a fresh share ID.").font(.caption)
                        Button("Open local receive fixture") { model.openLocalReceiveFixture() }
                        Button("Clear pending receive data", role: .destructive) { model.closeReceive() }
                        Text("If pending data cannot be restored, check your calendar for any earlier save before clearing it and reopening the original card.").font(.caption)
                    }
                }
                Section("Apple · Calendars on this iPhone") {
                    Text(model.appleStatus)
                    Button("Request access / list Apple calendars") { model.requestApple() }
                }
                Section("Google · Direct connection") {
                    Text(model.googleStatus)
                    Button("Open setup for browsing") { model.setup(.browse) }
                    Button("Open setup for saving / upgrade") { model.setup(.save) }
                    Button("List Google calendars") { model.listGoogle(forceRefresh: false) }
                    Button("Force refresh + list in extension") { model.listGoogle(forceRefresh: true) }
                    Text("If setup cannot open, launch Calendar Share from the Home Screen. Return manually to this conversation after consent.").font(.caption)
                    if !model.grantedScopes.isEmpty {
                        DisclosureGroup("Actually granted scopes") {
                            ForEach(model.grantedScopes, id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
                        }
                    }
                }
                Section("Probe status") { Text(model.status).textSelection(.enabled) }
                if !model.diagnostics.isEmpty {
                    Section("Compare on both devices") { Text(model.diagnostics).font(.caption.monospaced()).textSelection(.enabled) }
                }
                Section {
                    Text("M0 · iOS \(UIDevice.current.systemVersion). This harness has one pending receive slot. Production browsing, recents, and retry reconciliation are deferred.").font(.caption)
                }
            }
            .disabled(model.busy)
            .safeAreaInset(edge: .bottom) {
                if let draft = model.draft, !draft.writeAttempted {
                    VStack {
                        if model.busy { ProgressView("Working…") }
                        Button { model.add() } label: {
                            Text(draft.selectedDestination.map { "Add to \($0.displayName)" } ?? "Choose a calendar")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canAdd)
                    }.padding().background(.regularMaterial)
                } else if model.busy {
                    ProgressView("Working…").padding().frame(maxWidth: .infinity).background(.regularMaterial)
                }
            }
            .navigationTitle("Calendar Share M0")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            guard !model.busy else { return }
            Task { await model.refreshConnections() }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<ReceiveDraft, String>) -> Binding<String> {
        Binding(get: { model.draft?[keyPath: keyPath] ?? "" }, set: { model.edit(keyPath, value: $0) })
    }
}
