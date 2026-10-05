import SwiftUI
import UIKit
import EventKit
import CalendarDomain
import EventKitProvider
import AuthorizationStore
import GoogleCalendarProvider
import SharedStore

@main
struct CalendarShareApp: App {
    @StateObject private var model = CompanionModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                Form {
                    AppleCalendarsSection(permission: model.applePermission, calendars: model.appleCalendars,
                                          isLoading: model.appleLoading, error: model.appleError,
                                          onAction: model.requestApple)
                    Section("Google · Direct connection") {
                        DisclosureGroup("Set up Google") {
                            Text(model.googleStatus)
                            if let purpose = model.requestedPurpose {
                                Text(purpose == .save ? "Messages requested permission to save. After connecting, return manually and tap Add." : "Messages requested permission to browse.")
                            }
                            Button("Connect for browsing (read only)") { model.connect(.browse) }
                            Button("Connect / reauthorize for saving") { model.connect(.save) }
                            Text("Saving consent permits Google event creation, editing, and deletion. This harness only creates copies after Add; it never edits or deletes your existing events.")
                                .font(.caption)
                            Button("Force refresh and list calendars") { model.refreshProbe() }
                            Button("Disconnect Google", role: .destructive) { model.disconnect() }
                            if !model.scopes.isEmpty {
                                DisclosureGroup("Actually granted scopes") {
                                    ForEach(model.scopes, id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
                                }
                            }
                        }
                    }
                    Section("Return to Messages") {
                        Text("Open Messages, reopen the original conversation, and tap the event card. Your pending receive edits are restored. Choose a calendar if needed, then tap Add. Authorization never saves an event.")
                        Text("Enable Calendar Share in the conversation’s apps list. If opening setup from the extension fails, open this app from the Home Screen.")
                    }
                    if !model.message.isEmpty {
                        Section("Probe result") { Text(model.message).textSelection(.enabled) }
                    }
                    if model.busy { ProgressView("Working…") }
                    Section {
                        Text("M0 testing build · iOS \(UIDevice.current.systemVersion)").font(.caption)
                    }
                }
                .disabled(model.busy)
                .navigationTitle("Calendar Share M0")
            }
            .task { await model.reload() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.reload() } }
            }
            .onOpenURL { model.open($0) }
            .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
                guard !model.busy else { return }
                Task { await model.loadAppleCalendars() }
            }
        }
    }
}

@MainActor
final class CompanionModel: ObservableObject {
    @Published var applePermission = EventKitProbe.permissionStatus()
    @Published var appleCalendars: [CalendarRef]?
    @Published var appleLoading = false
    @Published var appleError: String?
    @Published var googleStatus = "Not checked"
    @Published var scopes: [String] = []
    @Published var message = ""
    @Published var busy = false
    @Published var requestedPurpose: GoogleAuthorizationPurpose?
    private let apple = EventKitProbe()
    private var authorization: GoogleAuthorizationController?

    func reload() async {
        await loadAppleCalendars()
        do {
            let store = try HarnessConfiguration().googleStore()
            if let connection = try await store.status() {
                googleStatus = connection.requiresReconnect ? "Reconnect required" : (connection.capabilities.canWrite ? "Browsing and saving authorized" : "Browsing authorized")
                scopes = connection.capabilities.scopes.sorted()
                if let expiry = connection.accessTokenExpiresAt {
                    googleStatus += " · token expires \(expiry.formatted(date: .omitted, time: .standard))"
                }
                googleStatus += " · refresh verified \(connection.refreshVerifiedAt.formatted(date: .omitted, time: .standard))"
            } else {
                googleStatus = "Not connected"
                scopes = []
            }
        } catch { googleStatus = error.localizedDescription }
    }

    func requestApple() {
        run {
            await self.loadAppleCalendars(requestAccess: true)
        }
    }

    func loadAppleCalendars(requestAccess: Bool = false) async {
        guard !appleLoading else { return }
        appleLoading = true
        appleError = nil
        defer { appleLoading = false }
        do {
            if requestAccess { _ = try await apple.requestFullAccess() }
            applePermission = EventKitProbe.permissionStatus()
            appleCalendars = nil
            if applePermission.canListCalendars {
                appleCalendars = try await apple.listCalendars()
            }
        } catch {
            applePermission = EventKitProbe.permissionStatus()
            appleCalendars = nil
            appleError = error.localizedDescription
        }
    }

    func connect(_ purpose: GoogleAuthorizationPurpose) {
        run {
            let config = HarnessConfiguration()
            let controller = try GoogleAuthorizationController(clientID: config.clientID, redirectURI: config.redirectURI, authorizationStore: config.googleStore())
            self.authorization = controller
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
                  let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else {
                throw ConfigurationError.missing("active authorization window")
            }
            var presenter = root
            while let presented = presenter.presentedViewController { presenter = presented }
            let change = try await controller.connect(purpose: purpose, presenting: presenter)
            self.authorization = nil
            if change.accountChanged {
                let pending = try PendingReceiveStore(containerURL: config.containerURL())
                try await pending.update { draft in
                    draft.invalidateGoogleDestination(unlessAccountKey: change.connection.accountKey)
                }
            }
            self.message = "Connection and fresh-token capability check complete. Return manually to Messages. No calendar write was performed." + (change.accountChanged ? " The Google account changed; select a destination again." : "")
            await self.reload()
        }
    }

    func refreshProbe() {
        run {
            let store = try HarnessConfiguration().googleStore()
            _ = try await store.accessToken(purpose: .browse, forceRefresh: true)
            let calendars = try await GoogleCalendarProvider(authorizationStore: store).listCalendars(purpose: .browse)
            self.message = "Companion refresh succeeded; listed \(calendars.count) calendars. Repeat this probe inside Messages after expiry and a cold launch."
            await self.reload()
        }
    }

    func disconnect() {
        run {
            let config = HarnessConfiguration()
            try await config.googleStore().disconnect()
            let pending = try PendingReceiveStore(containerURL: config.containerURL())
            try await pending.update { draft in
                draft.invalidateGoogleDestination(unlessAccountKey: nil)
            }
            self.message = "Google credentials cleared. Sent cards and calendar copies remain."
            await self.reload()
        }
    }

    func open(_ url: URL) {
        if authorization?.resume(url: url) == true { return }
        guard let scheme = try? HarnessConfiguration().setupScheme, url.scheme == scheme, url.host == "setup" else { return }
        requestedPurpose = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "purpose" })?.value.flatMap(GoogleAuthorizationPurpose.init(rawValue:))
        message = "Setup opened from Messages. Choose the connection action above, then return manually."
    }

    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do { try await operation() }
            catch { message = error.localizedDescription; await reload() }
        }
    }
}
