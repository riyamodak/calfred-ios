import Foundation

public enum GoogleAuthorizationPurpose: String, Codable, Sendable {
    case browse, save

    /// Every interactive request is a complete set; no incremental grant assumptions.
    public var requestedScopes: [String] {
        ["openid", GoogleCapabilities.calendarListRead,
         self == .save ? GoogleCapabilities.eventsWrite : GoogleCapabilities.eventsRead]
    }
}

public struct GoogleCapabilities: Codable, Equatable, Sendable {
    public static let calendarListRead = "https://www.googleapis.com/auth/calendar.calendarlist.readonly"
    public static let eventsRead = "https://www.googleapis.com/auth/calendar.events.readonly"
    public static let eventsWrite = "https://www.googleapis.com/auth/calendar.events"
    public let scopes: Set<String>

    public init(scopes: Set<String>) { self.scopes = scopes }
    public init(scopeString: String) {
        scopes = Set(scopeString.split(whereSeparator: \.isWhitespace).map(String.init))
    }
    public var canBrowse: Bool {
        scopes.contains(Self.calendarListRead)
            && (scopes.contains(Self.eventsRead) || scopes.contains(Self.eventsWrite))
    }
    public var canWrite: Bool { canBrowse && scopes.contains(Self.eventsWrite) }
    public func permits(_ purpose: GoogleAuthorizationPurpose) -> Bool {
        scopes.contains("openid") && (purpose == .save ? canWrite : canBrowse)
    }
}

public struct GoogleConnection: Codable, Equatable, Sendable {
    public let accountKey: String
    public var capabilities: GoogleCapabilities
    public var refreshVerifiedAt: Date
    public var accessTokenExpiresAt: Date?
    public var requiresReconnect: Bool
}

public struct GoogleConnectionChange: Sendable {
    public let oldAccountKey: String?
    public let connection: GoogleConnection
    public var accountChanged: Bool { oldAccountKey != nil && oldAccountKey != connection.accountKey }
}

/// Intentionally no CustomStringConvertible/debug logging implementation.
public struct GoogleAccessToken: Sendable {
    public let value: String
    public let connection: GoogleConnection
}

public enum GoogleAuthorizationError: Error, LocalizedError, Sendable {
    case configuration, reconnect, missingScopes, missingRefreshToken, identityMismatch
    case network, invalidResponse, keychain(Int32), authorizationCanceledOrFailed, alreadyAuthorizing

    public var errorDescription: String? {
        switch self {
        case .configuration: return "Configure the Google iOS client and shared Keychain before connecting."
        case .reconnect: return "Reconnect Google in Calendar Share. The previous grant is no longer usable."
        case .missingScopes: return "Google did not grant all required permissions. A previous connection was not replaced."
        case .missingRefreshToken: return "Google did not provide durable refresh access. Connect again and grant consent."
        case .identityMismatch: return "Google account verification changed unexpectedly. Connect again."
        case .network: return "Google could not be reached. Check the connection and try again."
        case .invalidResponse: return "Google returned an incomplete response. Connect again if this persists."
        case .keychain: return "Shared Keychain access failed. Check signing and Keychain access-group configuration."
        case .authorizationCanceledOrFailed: return "Google authorization was canceled or declined. Any still-valid previous connection is retained."
        case .alreadyAuthorizing: return "A Google connection is already in progress."
        }
    }
}
