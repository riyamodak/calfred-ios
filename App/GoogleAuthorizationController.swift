import AppAuth
import AuthorizationStore
import UIKit

/// Authorization UI is deliberately confined to the containing app target.
@MainActor
final class GoogleAuthorizationController {
    private let clientID: String
    private let redirectURI: URL
    private let authorizationStore: GoogleAuthorizationStore
    private var currentFlow: OIDExternalUserAgentSession?
    private var connecting = false

    init(clientID: String, redirectURI: URL, authorizationStore: GoogleAuthorizationStore) {
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.authorizationStore = authorizationStore
    }

    func connect(purpose: GoogleAuthorizationPurpose, presenting: UIViewController) async throws -> GoogleConnectionChange {
        guard !connecting else { throw GoogleAuthorizationError.alreadyAuthorizing }
        guard clientID.hasSuffix(".apps.googleusercontent.com"), !clientID.contains("REPLACE"),
              let scheme = redirectURI.scheme, scheme.contains("."), !scheme.contains("REPLACE") else {
            throw GoogleAuthorizationError.configuration
        }
        connecting = true
        defer { connecting = false; currentFlow = nil }
        let configuration = OIDServiceConfiguration(
            authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!)
        let request = OIDAuthorizationRequest(configuration: configuration,
                                              clientId: clientID, clientSecret: nil,
                                              scopes: purpose.requestedScopes,
                                              redirectURL: redirectURI,
                                              responseType: OIDResponseTypeCode,
                                              additionalParameters: ["prompt": "consent select_account"])
        // AppAuth generates PKCE verifier/challenge, state and nonce for this code flow.
        // Every request includes the complete set; include_granted_scopes is not used.
        do {
            let candidate: OIDAuthState = try await withCheckedThrowingContinuation { continuation in
                currentFlow = OIDAuthState.authState(byPresenting: request, presenting: presenting) { state, _ in
                    if let state { continuation.resume(returning: state) }
                    else { continuation.resume(throwing: GoogleAuthorizationError.authorizationCanceledOrFailed) }
                }
            }
            return try await authorizationStore.install(candidate: candidate, purpose: purpose)
        } catch {
            // If a canceled/partial upgrade invalidated the old grant on Google's side,
            // the UI must show reconnect instead of asserting it remains usable.
            _ = try? await authorizationStore.accessToken(purpose: .browse, forceRefresh: true)
            throw error
        }
    }

    @discardableResult
    func resume(url: URL) -> Bool {
        currentFlow?.resumeExternalUserAgentFlow(with: url) ?? false
    }
}
