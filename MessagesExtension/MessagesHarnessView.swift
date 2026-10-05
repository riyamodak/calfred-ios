import SwiftUI
import EventKit
import CalendarDomain

struct MessagesHarnessView: View {
    @ObservedObject var model: MessagesModel

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
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
                        .id("received-event")
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
                    }
                    AppleCalendarsSection(permission: model.applePermission, calendars: model.appleCalendars,
                                          isLoading: model.appleLoading, error: model.appleError,
                                          showCalendars: model.draft == nil, onAction: model.requestApple)
                    if model.draft == nil {
                        Section("Try saving an event") {
                            Text("Open a sample received event, choose a writable calendar, then tap Add. This creates a real test event only after you tap Add.")
                            Button("Open sample to test saving") { model.openLocalReceiveFixture() }
                            if let error = model.sampleError {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("Couldn’t open sample", systemImage: "exclamationmark.triangle")
                                        .font(.headline)
                                    Text(error)
                                    Text("No event was saved. This test opens inside the extension; it does not insert a message.")
                                        .font(.caption)
                                }
                                .textSelection(.enabled)
                            }
                            Text("The sample is “Trip to Chicago,” October 10–12, 2026. Saving requires the shared App Group setup; Google and the message help URL can be configured later.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Section("Message delivery tests") {
                            DisclosureGroup("Send sample cards") {
                                Text("These synthetic events test how a card arrives on another iPhone. A button inserts a draft; you then tap the normal Messages Send button.")
                                    .font(.caption)
                                Button("Insert all-day sample card") { model.selectSample(nearLimit: false) }
                                Button("Insert timed / daylight-saving sample") { model.selectSample(nearLimit: false, timed: true) }
                                Button("Insert large Unicode sample") { model.selectSample(nearLimit: true) }
                                if model.canRetryInsertion { Button("Retry insertion") { model.retryInsertion() } }
                                Text("Start with the all-day sample. The other cards test time changes and a message close to the size limit. Configure the owned HTTPS help URL before these tests.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section("Google · Direct connection") {
                        DisclosureGroup("Set up Google") {
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
                    }
                    Section("Test status") { Text(model.status).textSelection(.enabled) }
                    if !model.diagnostics.isEmpty {
                        Section {
                            DisclosureGroup("Message verification details") {
                                Text("For a sent card, compare the share ID and digest on both phones.").font(.caption)
                                Text(model.diagnostics).font(.caption.monospaced()).textSelection(.enabled)
                            }
                        }
                    }
                    if model.draft == nil {
                        Section {
                            DisclosureGroup("Reset test state") {
                                Text("Use this if a previous sample cannot be restored. Check your calendar for any earlier save before starting another test.").font(.caption)
                                Button("Clear pending receive data", role: .destructive) { model.closeReceive() }
                            }
                        }
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
                .onChange(of: model.draft?.snapshot.shareId) { _, shareID in
                    if shareID != nil { scroll.scrollTo("received-event", anchor: .top) }
                }
            }
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
