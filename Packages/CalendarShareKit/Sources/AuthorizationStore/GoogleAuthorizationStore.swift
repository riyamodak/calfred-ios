import AppAuthCore
import Foundation
import Security
import SharedStore

/// Credentials are one atomic Keychain value. The App Group holds only the lock file.
/// The lock covers load → refresh → validation → persistence across app and extension.
public final class GoogleAuthorizationStore: @unchecked Sendable {
    private let keychainAccessGroup: String
    private let lock: FileLock
    private let session: URLSession
    private let service = "CalendarShare.GoogleAuthorization.v1"

    private struct Record: Codable {
        var connection: GoogleConnection
        var archive: Data
        // Optional for compatibility with existing M0 Keychain records. A refresh
        // can rotate credentials before UserInfo becomes available; persist that
        // state but never hand out its token until identity verification completes.
        var identityVerificationPending: Bool? = false
    }

    public init(keychainAccessGroup: String, lockURL: URL) {
        self.keychainAccessGroup = keychainAccessGroup
        lock = FileLock(url: lockURL)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        session = URLSession(configuration: configuration)
    }

    public func status() async throws -> GoogleConnection? {
        try await lock.withLock { try self.read()?.connection }
    }

    /// The fresh candidate is never combined with the prior account's credential state.
    /// It must prove its own refresh credential supports the requested capabilities.
    public func install(candidate: OIDAuthState, purpose: GoogleAuthorizationPurpose) async throws -> GoogleConnectionChange {
        try await lock.withLock {
            let prior = try self.read()
            guard let firstToken = candidate.lastTokenResponse?.accessToken,
                  let firstScopes = candidate.lastTokenResponse?.scope else {
                throw GoogleAuthorizationError.missingScopes
            }
            guard GoogleCapabilities(scopeString: firstScopes).permits(purpose) else {
                throw GoogleAuthorizationError.missingScopes
            }
            guard let refresh = candidate.refreshToken, !refresh.isEmpty else {
                throw GoogleAuthorizationError.missingRefreshToken
            }
            let firstAccount = try await self.accountKey(accessToken: firstToken)
            candidate.setNeedsTokenRefresh()
            let refreshed = try await self.freshToken(candidate)
            // Inspect the actual refresh response, never AppAuth's requested-scope fallback.
            guard let refreshedScopes = candidate.lastTokenResponse?.scope else {
                throw GoogleAuthorizationError.missingScopes
            }
            let capabilities = GoogleCapabilities(scopeString: refreshedScopes)
            guard capabilities.permits(purpose) else { throw GoogleAuthorizationError.missingScopes }
            let refreshedAccount = try await self.accountKey(accessToken: refreshed)
            guard refreshedAccount == firstAccount else { throw GoogleAuthorizationError.identityMismatch }
            let connection = GoogleConnection(accountKey: firstAccount, capabilities: capabilities,
                                              refreshVerifiedAt: Date(),
                                              accessTokenExpiresAt: candidate.lastTokenResponse?.accessTokenExpirationDate,
                                              requiresReconnect: false)
            let record = Record(connection: connection, archive: try self.archive(candidate))
            try self.write(record)
            return GoogleConnectionChange(oldAccountKey: prior?.connection.accountKey, connection: connection)
        }
    }

    public func accessToken(purpose: GoogleAuthorizationPurpose, forceRefresh: Bool = false) async throws -> GoogleAccessToken {
        try await lock.withLock {
            guard var record = try self.read(), !record.connection.requiresReconnect else {
                throw GoogleAuthorizationError.reconnect
            }
            guard record.connection.capabilities.permits(purpose) else { throw GoogleAuthorizationError.missingScopes }
            guard let state = try NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: record.archive),
                  state.isAuthorized, state.refreshToken != nil else {
                record.connection.requiresReconnect = true
                try self.write(record)
                throw GoogleAuthorizationError.reconnect
            }
            if forceRefresh { state.setNeedsTokenRefresh() }
            let oldResponse = state.lastTokenResponse
            do {
                let token = try await self.freshToken(state)
                let didRefresh = state.lastTokenResponse !== oldResponse
                if didRefresh {
                    record.identityVerificationPending = true
                    guard let scope = state.lastTokenResponse?.scope else {
                        throw GoogleAuthorizationError.missingScopes
                    }
                    record.connection.capabilities = GoogleCapabilities(scopeString: scope)
                    guard record.connection.capabilities.permits(purpose) else {
                        throw GoogleAuthorizationError.missingScopes
                    }
                }
                if record.identityVerificationPending == true {
                    let refreshedAccount = try await self.accountKey(accessToken: token)
                    guard refreshedAccount == record.connection.accountKey else {
                        throw GoogleAuthorizationError.identityMismatch
                    }
                    record.connection.refreshVerifiedAt = Date()
                    record.connection.accessTokenExpiresAt = state.lastTokenResponse?.accessTokenExpirationDate
                    record.identityVerificationPending = false
                }
                record.archive = try self.archive(state)
                try self.write(record)
                return GoogleAccessToken(value: token, connection: record.connection)
            } catch {
                // Persist rotated tokens even if the identity network check failed. Do not
                // turn a transient outage into a destructive local disconnect.
                let transientInvalidation: Bool
                if let authError = error as? GoogleAuthorizationError,
                   case .network = authError, !state.isAuthorized {
                    transientInvalidation = true
                } else {
                    transientInvalidation = false
                }
                // AppAuth invalidates any OAuth 4xx response, including some temporary
                // errors. Such a failed refresh has issued no new token; retain the
                // pre-request archive rather than persisting its invalidated state.
                if !transientInvalidation { record.archive = try self.archive(state) }
                if (!state.isAuthorized && !transientInvalidation) || Self.isPermanent(error) {
                    record.connection.requiresReconnect = true
                }
                try self.write(record)
                throw error
            }
        }
    }

    /// A late response for an old token must not invalidate a newer same-account grant.
    public func requireReconnect(accountKey: String, rejectedAccessToken: String) async throws {
        try await lock.withLock {
            guard var record = try self.read(), record.connection.accountKey == accountKey,
                  let state = try NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: record.archive),
                  state.lastTokenResponse?.accessToken == rejectedAccessToken else { return }
            record.connection.requiresReconnect = true
            try self.write(record)
        }
    }

    public func disconnect() async throws {
        try await lock.withLock {
            let result = SecItemDelete(self.query as CFDictionary)
            guard result == errSecSuccess || result == errSecItemNotFound else {
                throw GoogleAuthorizationError.keychain(result)
            }
        }
    }

    private static func isPermanent(_ error: Error) -> Bool {
        guard let error = error as? GoogleAuthorizationError else { return false }
        switch error {
        case .reconnect, .missingScopes, .identityMismatch: return true
        default: return false
        }
    }

    private func freshToken(_ state: OIDAuthState) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            state.performAction { token, _, error in
                if let error {
                    let failure = GoogleRefreshFailure.classify(error, stateIsAuthorized: state.isAuthorized)
                    continuation.resume(throwing: failure == .transient ? GoogleAuthorizationError.network : .reconnect)
                } else if let token, !token.isEmpty {
                    continuation.resume(returning: token)
                } else {
                    continuation.resume(throwing: GoogleAuthorizationError.reconnect)
                }
            }
        }
    }

    private func accountKey(accessToken: String) async throws -> String {
        // Trust Google's authenticated UserInfo response, not an unverified JWT payload.
        var request = URLRequest(url: URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw GoogleAuthorizationError.network }
        guard let http = response as? HTTPURLResponse else { throw GoogleAuthorizationError.invalidResponse }
        guard http.statusCode == 200 else {
            throw http.statusCode == 401 ? GoogleAuthorizationError.reconnect : .invalidResponse
        }
        struct Identity: Decodable { let sub: String }
        guard let identity = try? JSONDecoder().decode(Identity.self, from: data),
              !identity.sub.isEmpty, identity.sub.count <= 255 else { throw GoogleAuthorizationError.invalidResponse }
        return identity.sub
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "single-google-account",
         kSecAttrAccessGroup as String: keychainAccessGroup,
         kSecAttrSynchronizable as String: false]
    }

    private func read() throws -> Record? {
        guard !keychainAccessGroup.isEmpty, !keychainAccessGroup.contains("$(") else {
            throw GoogleAuthorizationError.configuration
        }
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let result = SecItemCopyMatching(request as CFDictionary, &value)
        if result == errSecItemNotFound { return nil }
        guard result == errSecSuccess, let data = value as? Data else {
            throw GoogleAuthorizationError.keychain(result)
        }
        guard let record = try? JSONDecoder().decode(Record.self, from: data) else {
            throw GoogleAuthorizationError.invalidResponse
        }
        return record
    }

    private func archive(_ state: OIDAuthState) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: state, requiringSecureCoding: true)
    }

    private func write(_ record: Record) throws {
        let data = try JSONEncoder().encode(record)
        let values: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var result = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if result == errSecItemNotFound {
            result = SecItemAdd(query.merging(values, uniquingKeysWith: { _, new in new }) as CFDictionary, nil)
        }
        guard result == errSecSuccess else { throw GoogleAuthorizationError.keychain(result) }
    }
}

/// AppAuth treats token-endpoint OAuth 4xx errors as grant failures. HTTP 408/429
/// and explicit temporary OAuth errors must remain retryable, even if AppAuth has
/// already set isAuthorized=false. Error bodies are inspected but never logged.
enum GoogleRefreshFailure: Equatable {
    case transient, reconnect

    static func classify(_ error: Error, stateIsAuthorized: Bool) -> Self {
        var current: NSError? = error as NSError
        for _ in 0..<8 {
            guard let value = current else { break }
            if value.domain == NSURLErrorDomain { return .transient }
            if value.domain == OIDHTTPErrorDomain,
               value.code == 408 || value.code == 429 || (500...599).contains(value.code) {
                return .transient
            }
            if let response = value.userInfo[OIDOAuthErrorResponseErrorKey] as? [String: Any],
               let code = response["error"] as? String,
               ["server_error", "temporarily_unavailable"].contains(code) {
                return .transient
            }
            current = value.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return stateIsAuthorized ? .transient : .reconnect
    }
}
