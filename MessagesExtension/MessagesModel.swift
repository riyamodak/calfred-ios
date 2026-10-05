import SwiftUI
import CalendarDomain
import MessageCodec
import SharedStore
import EventKitProvider
import AuthorizationStore
import GoogleCalendarProvider

@MainActor
final class MessagesModel: ObservableObject {
    @Published var draft: ReceiveDraft?
    @Published var calendars: [CalendarRef] = []
    @Published var status = "Allow calendar access to see calendars on this iPhone. Open a sample below when you are ready to test saving."
    @Published var applePermission = EventKitProbe.permissionStatus()
    @Published var appleCalendars: [CalendarRef]?
    @Published var appleLoading = false
    @Published var appleError: String?
    @Published var googleStatus = "Google not checked"
    @Published var googleCalendars: [CalendarRef]?
    @Published var googleLoading = false
    @Published var googleError: String?
    @Published var googleCanWrite = false
    @Published var grantedScopes: [String] = []
    @Published var diagnostics = ""
    @Published var busy = false
    @Published var canRetryInsertion = false
    @Published var sampleError: String?
    @Published var insertionError: String?
    var insert: ((ShareSnapshot, URL) async throws -> Void)?
    var openSetup: ((URL) async -> Bool)?
    var expandPresentation: (() -> Void)?
    private let apple = EventKitProbe()
    private var insertionSnapshot: ShareSnapshot?
    private var persistence: Task<Void, Never>?
    private struct Activation { let messageURL: URL? }
    private var pendingActivation: Activation?

    var canAdd: Bool {
        guard !busy, let draft, !draft.writeAttempted, let selected = draft.selectedDestination else { return false }
        if selected.provider == .google && !googleCanWrite { return false }
        return calendars.contains { $0.id == selected.id && $0.isWritable }
    }

    var messageConfigurationError: String? {
        do { _ = try HarnessConfiguration().codec(); return nil }
        catch { return error.localizedDescription }
    }

    private func pendingStore() throws -> PendingReceiveStore {
        try PendingReceiveStore(containerURL: HarnessConfiguration().containerURL())
    }

    func activate(messageURL: URL?) async {
        guard !busy else {
            pendingActivation = Activation(messageURL: messageURL)
            return
        }
        busy = true
        defer { finishWork() }
        await persistence?.value
        do {
            let stored = try await pendingStore().load()
            if let url = messageURL {
                let codec = try HarnessConfiguration().codec()
                let snapshot = try codec.decode(url)
                if stored?.snapshot == snapshot { draft = stored }
                else { draft = ReceiveDraft(snapshot: snapshot); try await persistCurrent() }
                diagnostics = try describe(snapshot, codec: codec)
                status = "Payload decoded. Select a destination and tap Add to save an independent copy."
            } else if let stored {
                draft = stored
                // A local save sample does not require a configured Messages help URL.
                diagnostics = (try? describe(stored.snapshot, codec: HarnessConfiguration().codec())) ?? "Local sample: message delivery has not been tested."
                status = "Pending receive restored. Review your edits and tap Add when ready."
            }
        } catch {
            // A malformed selected card must never expose a previous card's Add button.
            if messageURL != nil { draft = nil; calendars = []; diagnostics = "" }
            status = error.localizedDescription
        }
        // Calendar access can be checked even before App Group or transport setup.
        await refreshConnectionsInternal()
    }

    func refreshConnections() async {
        guard !busy else { return }
        busy = true
        defer { finishWork() }
        await persistence?.value
        await refreshConnectionsInternal()
    }

    private func refreshConnectionsInternal() async {
        // Rebuild choices rather than enabling Add from a stale in-memory list.
        calendars = []
        googleCalendars = nil
        googleError = nil
        googleCanWrite = false
        await loadAppleCalendars()
        do {
            let store = try HarnessConfiguration().googleStore()
            let connection = try await store.status()
            draft?.invalidateGoogleDestination(unlessAccountKey: connection?.accountKey)
            grantedScopes = connection?.capabilities.scopes.sorted() ?? []
            googleStatus = connection.map {
                $0.requiresReconnect ? "Reconnect Google" : ($0.capabilities.canWrite ? "Google browsing + saving authorized" : "Google read-only; authorize saving in setup")
            } ?? "Google not connected"
            if connection?.requiresReconnect == true, draft?.selectedDestination?.provider == .google {
                draft?.selectedDestination = nil
            }
            if connection?.requiresReconnect == false {
                _ = try await loadGoogleCalendars(store: store, forceRefresh: false)
            }
        } catch {
            googleStatus = error.localizedDescription
            googleError = error.localizedDescription
            if draft?.selectedDestination?.provider == .google {
                status = "The selected Google calendar could not be checked. Your edits are preserved. Retry listing calendars before Add."
            }
        }
        do { try await persistCurrent() } catch { status = error.localizedDescription }
    }

    func selectSample(nearLimit: Bool, timed: Bool = false) {
        run {
            self.insertionError = nil
            self.insertionSnapshot = nil
            self.canRetryInsertion = false
            do {
                let codec = try HarnessConfiguration().codec()
                let snapshot = try nearLimit ? codec.nearLimitSnapshot() : (timed ? M0Samples.timedSnapshot() : codec.sampleSnapshot())
                self.insertionSnapshot = snapshot
                self.canRetryInsertion = true
                self.diagnostics = try self.describe(snapshot, codec: codec)
                try await self.insertSnapshot(snapshot, codec: codec)
            } catch {
                self.insertionError = error.localizedDescription
                throw error
            }
        }
    }

    func retryInsertion() {
        guard let snapshot = insertionSnapshot else { return }
        run {
            self.insertionError = nil
            do { try await self.insertSnapshot(snapshot, codec: HarnessConfiguration().codec()) }
            catch { self.insertionError = error.localizedDescription; throw error }
        }
    }

    private func insertSnapshot(_ snapshot: ShareSnapshot, codec: MessageCodec) async throws {
        guard let insert else { throw MessagesProbeError.noConversation }
        try await insert(snapshot, codec.encode(snapshot))
        canRetryInsertion = false
        status = "Inserted into compose. Review the draft, then tap Messages Send. Compare this digest on the receiving device."
    }

    func openLocalReceiveFixture() {
        run {
            self.sampleError = nil
            let snapshot = M0Samples.allDaySnapshot()
            let sample = ReceiveDraft(snapshot: snapshot)
            do {
                try await self.pendingStore().save(sample)
            } catch {
                // Keep the failure beside the initiating button, not only below the fold.
                self.sampleError = error.localizedDescription
                throw error
            }
            self.draft = sample
            self.diagnostics = "Local sample: message delivery has not been tested."
            self.status = "Sample ready. Choose a writable calendar, then tap Add to create a real test event."
            self.expandPresentation?()
            await self.refreshConnectionsInternal()
        }
    }

    func requestApple() {
        run {
            await self.loadAppleCalendars(requestAccess: true)
            if let listed = self.appleCalendars {
                self.status = "Found \(listed.count) device calendars, \(listed.filter(\.isWritable).count) writable."
            }
        }
    }

    private func loadAppleCalendars(requestAccess: Bool = false) async {
        appleLoading = true
        appleError = nil
        appleCalendars = nil
        calendars.removeAll { $0.provider == .apple }
        defer { appleLoading = false }
        do {
            if requestAccess { _ = try await apple.requestFullAccess() }
            applePermission = EventKitProbe.permissionStatus()
            if applePermission.canListCalendars {
                let listed = try await apple.listCalendars()
                appleCalendars = listed
                calendars += listed.filter(\.isWritable)
                draft?.revalidateDestination(in: listed, provider: .apple)
            } else if draft?.selectedDestination?.provider == .apple {
                draft?.selectedDestination = nil
            }
        } catch {
            applePermission = EventKitProbe.permissionStatus()
            appleError = error.localizedDescription
        }
    }

    func listGoogle(forceRefresh: Bool) {
        run {
            let listed: [CalendarRef]
            do {
                let store = try HarnessConfiguration().googleStore()
                listed = try await self.loadGoogleCalendars(store: store, forceRefresh: forceRefresh)
            } catch {
                self.googleCalendars = nil
                self.googleCanWrite = false
                self.calendars.removeAll { $0.provider == .google }
                self.googleError = error.localizedDescription
                self.googleStatus = "Google calendars could not be loaded."
                throw error
            }
            self.status = "Extension \(forceRefresh ? "forced fresh-token refresh and " : "")listed \(listed.count) Google calendars. \(listed.filter(\.isWritable).count) writable. No event was written."
            try await self.persistCurrent()
        }
    }

    private func loadGoogleCalendars(store: GoogleAuthorizationStore, forceRefresh: Bool) async throws -> [CalendarRef] {
        googleLoading = true
        googleError = nil
        googleCalendars = nil
        googleCanWrite = false
        calendars.removeAll { $0.provider == .google }
        defer { googleLoading = false }
        let token = try await store.accessToken(purpose: .browse, forceRefresh: forceRefresh)
        let listed = try await GoogleCalendarProvider(authorizationStore: store).listCalendars(purpose: .browse)
        let connection = try await store.status()
        draft?.invalidateGoogleDestination(unlessAccountKey: connection?.accountKey)
        guard let connection, !connection.requiresReconnect,
              connection.accountKey == token.connection.accountKey,
              listed.allSatisfy({ $0.accountKey == connection.accountKey }) else {
            throw MessagesProbeError.changedDestination
        }
        calendars += listed.filter(\.isWritable)
        googleCalendars = listed
        googleCanWrite = connection.capabilities.canWrite
        draft?.revalidateDestination(in: listed, provider: .google)
        grantedScopes = connection.capabilities.scopes.sorted()
        googleStatus = connection.capabilities.canWrite ? "Google browsing + saving authorized" : "Google read-only; authorize saving in setup"
        return listed
    }

    func setup(_ purpose: GoogleAuthorizationPurpose) {
        run {
            try await self.persistCurrent()
            let configuration = HarnessConfiguration()
            var components = URLComponents()
            components.scheme = try configuration.setupScheme
            components.host = "setup"
            components.queryItems = [URLQueryItem(name: "purpose", value: purpose.rawValue)]
            guard let url = components.url else { throw ConfigurationError.missing("setup URL scheme") }
            let opened = await self.openSetup?(url) ?? false
            self.status = opened
                ? "Setup opened. After consent, return manually to this conversation. Review the destination and tap Add."
                : "Open Calendar Share from the Home Screen, connect Google, then return to this conversation and reopen the card. Your edits are saved."
        }
    }

    func edit(_ keyPath: WritableKeyPath<ReceiveDraft, String>, value: String) {
        guard !busy, draft?.writeAttempted == false else { return }
        draft?[keyPath: keyPath] = value
        queuePersistence()
    }

    func selectDestination(_ calendar: CalendarRef) {
        guard !busy, draft?.writeAttempted == false else { return }
        draft?.selectedDestination = calendar
        queuePersistence()
    }

    func add() {
        guard canAdd else { return }
        run {
            guard var current = self.draft, let selected = current.selectedDestination else { throw MessagesProbeError.noDestination }
            try current.effectiveEvent.validate()
            // Validate authorization and live destination before marking this one-shot probe attempted.
            let google: GoogleCalendarProvider?
            let currentCalendars: [CalendarRef]
            if selected.provider == .google {
                let store = try HarnessConfiguration().googleStore()
                let fresh = try await store.accessToken(purpose: .save)
                guard fresh.connection.accountKey == selected.accountKey else {
                    self.draft?.selectedDestination = nil
                    try await self.persistCurrent()
                    throw MessagesProbeError.changedDestination
                }
                google = GoogleCalendarProvider(authorizationStore: store)
                currentCalendars = try await google!.listCalendars(purpose: .save)
            } else {
                google = nil
                currentCalendars = try await self.apple.listCalendars(writableOnly: true)
            }
            guard currentCalendars.contains(where: { $0.id == selected.id && $0.isWritable }) else {
                self.draft?.selectedDestination = nil
                try await self.persistCurrent()
                throw MessagesProbeError.changedDestination
            }
            current.writeAttempted = true
            current.writeResult = "Save attempt recorded. If no confirmation appears, check the destination calendar. M0 blocks retries of uncertain writes."
            self.draft = current
            do {
                try await self.persistCurrent() // Must succeed before contacting either provider.
            } catch {
                self.draft?.writeResult = "No calendar write was made. The save attempt could not be stored. Fix shared storage before starting another probe."
                throw error
            }
            do {
                if let google {
                    let snapshot = ShareSnapshot(shareId: current.snapshot.shareId, createdAt: current.snapshot.createdAt, event: current.effectiveEvent)
                    _ = try await google.createSampleCopy(snapshot: snapshot, destination: selected, operationID: UUID())
                    self.draft?.writeResult = "Added to \(selected.displayName). Google confirmed creation of an independent copy."
                } else {
                    let result = try await self.apple.createCopy(event: current.effectiveEvent, destination: selected)
                    self.draft?.writeResult = "Added to \(result.destinationName) in the device calendar store. Remote sync may still be pending. Availability: \(result.availabilityDescription)." + (result.hadUnexpectedAlarmsAfterSave ? " Unexpected alarms were observed — record this M0 blocker." : " No alarms observed on read-back.")
                }
            } catch {
                self.draft?.writeResult = "No save confirmation was received. Check \(selected.displayName) before another test. M0 blocks another attempt for this pending probe."
                self.status = error.localizedDescription
                // The durable attempted flag already exists even if this message cannot be stored.
                try? await self.persistCurrent()
                return
            }
            do {
                try await self.persistCurrent()
                self.status = "Save confirmed. Record the observed calendar result in the M0 feasibility checklist."
            } catch {
                self.status = "The calendar confirmed this save, but its local confirmation could not be stored. Check the calendar before clearing pending state."
            }
        }
    }

    func closeReceive() {
        run {
            try await self.pendingStore().clear()
            self.draft = nil
            self.diagnostics = ""
            self.status = "Pending local receive cleared. Existing calendar copies and sent messages remain."
        }
    }

    private func describe(_ snapshot: ShareSnapshot, codec: MessageCodec) throws -> String {
        "Share ID: \(snapshot.shareId.uuidString)\nURL characters: \(try codec.encode(snapshot).absoluteString.count)/4500\nSHA-256: \(try codec.digest(snapshot))"
    }

    private func queuePersistence() {
        let preceding = persistence
        let frozen = draft
        persistence = Task {
            await preceding?.value
            guard let frozen else { return }
            do { try await pendingStore().save(frozen) }
            catch { status = "Edits could not be preserved: \(error.localizedDescription)" }
        }
    }

    private func persistCurrent() async throws {
        await persistence?.value
        if let draft { try await pendingStore().save(draft) }
    }

    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        Task {
            await persistence?.value
            defer { finishWork() }
            do { try await operation() }
            catch { status = error.localizedDescription }
        }
    }

    private func finishWork() {
        busy = false
        if let activation = pendingActivation {
            pendingActivation = nil
            Task { await activate(messageURL: activation.messageURL) }
        }
    }
}

extension EventTime {
    var probeDescription: String {
        switch self {
        case let .timed(start, end, startZone, endZone):
            let dates = "\(start.formatted(date: .abbreviated, time: .shortened)) – \(end.formatted(date: .abbreviated, time: .shortened))"
            return dates + " · device time" + (startZone.map { " · source \($0)" } ?? "") + (endZone.flatMap { $0 != startZone ? " → \($0)" : nil } ?? "")
        case let .allDay(start, exclusiveEnd):
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            if let end = try? exclusiveEnd.date(in: calendar.timeZone), let last = calendar.date(byAdding: .day, value: -1, to: end) {
                let formatter = DateFormatter()
                formatter.calendar = calendar
                formatter.timeZone = calendar.timeZone
                formatter.dateStyle = .medium
                return "\(start) – \(formatter.string(from: last)) · all day"
            }
            return "\(start) · all day"
        }
    }
}
