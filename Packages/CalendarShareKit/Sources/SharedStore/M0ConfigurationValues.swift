import Foundation

/// Validate only the setting being used. Apple storage must not require Google or transport setup.
public struct M0ConfigurationValues {
    private let values: [String: String]

    public init(_ values: [String: String]) {
        self.values = values
    }

    public func value(_ key: String) throws -> String {
        guard let value = values[key], !value.isEmpty, !value.contains("$(") else {
            throw M0ConfigurationError.missing(key)
        }
        return value
    }

    public func messageBaseURL() throws -> URL {
        let key = "CalendarShareMessageBaseURL"
        let raw = try value(key)
        guard let url = URL(string: raw), url.scheme == "https",
              let host = url.host, !host.isEmpty,
              host != "example.invalid", !host.lowercased().contains("your_owned_host") else {
            throw M0ConfigurationError.missing("MESSAGE_BASE_URL (owned HTTPS help URL; keep the https:/$()/ syntax)")
        }
        return url
    }

    public func googleRedirectURI() throws -> URL {
        let scheme = try value("CalendarShareGoogleRedirectScheme")
        guard !scheme.contains("REPLACE"), !scheme.contains("YOUR_"),
              let url = URL(string: scheme + ":/oauthredirect"), url.scheme == scheme else {
            throw M0ConfigurationError.missing("GOOGLE_REDIRECT_SCHEME (reversed iOS OAuth client ID)")
        }
        return url
    }
}

public enum M0ConfigurationError: LocalizedError {
    case missing(String)
    case appGroupUnavailable

    public var errorDescription: String? {
        switch self {
        case .missing(let setting):
            return "Configure \(setting) in Configuration/Local.xcconfig, then rebuild. See README."
        case .appGroupUnavailable:
            return "Shared storage is unavailable. In Xcode, enable the SAME App Group under Signing & Capabilities → App Groups for BOTH CalendarShare and CalendarShareMessages. Set APP_GROUP_IDENTIFIER in Configuration/Local.xcconfig to that exact group, resolve any signing errors, then rebuild and reinstall. Typing a group name alone does not grant access."
        }
    }
}
