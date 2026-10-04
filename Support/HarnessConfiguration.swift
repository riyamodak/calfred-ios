import Foundation
import CalendarDomain
import MessageCodec
import SharedStore
import AuthorizationStore
import GoogleCalendarProvider

struct HarnessConfiguration {
    let appGroup: String
    let keychainGroup: String
    let setupScheme: String
    let clientID: String
    let redirectURI: URL
    let messageBaseURL: URL

    init(bundle: Bundle = .main) throws {
        func value(_ key: String) throws -> String {
            guard let value = bundle.object(forInfoDictionaryKey: key) as? String,
                  !value.isEmpty, !value.contains("$(") else { throw ConfigurationError.missing(key) }
            return value
        }
        appGroup = try value("CalendarShareAppGroup")
        keychainGroup = try value("CalendarShareKeychainGroup")
        setupScheme = try value("CalendarShareSetupScheme")
        clientID = try value("CalendarShareGoogleClientID")
        guard let redirect = URL(string: try value("CalendarShareGoogleRedirectScheme") + ":/oauthredirect"),
              let base = URL(string: try value("CalendarShareMessageBaseURL")) else {
            throw ConfigurationError.missing("URLs")
        }
        redirectURI = redirect
        messageBaseURL = base
    }

    func containerURL() throws -> URL {
        guard !appGroup.contains("com.example"),
              let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            throw ConfigurationError.missing("App Group and signing entitlements")
        }
        return url
    }

    func googleStore() throws -> GoogleAuthorizationStore {
        guard !clientID.contains("REPLACE_ME") else { throw ConfigurationError.missing("Google iOS OAuth client") }
        return GoogleAuthorizationStore(keychainAccessGroup: keychainGroup,
                                        lockURL: try containerURL().appendingPathComponent("google-auth.lock"))
    }

    func codec() throws -> MessageCodec {
        guard messageBaseURL.host != "example.invalid", messageBaseURL.host != "YOUR_OWNED_HOST" else {
            throw ConfigurationError.missing("owned HTTPS help URL")
        }
        return try MessageCodec(baseURL: messageBaseURL)
    }
}

enum ConfigurationError: LocalizedError {
    case missing(String)
    var errorDescription: String? {
        switch self {
        case .missing(let setting): return "Configure \(setting) in Configuration/Local.xcconfig, then rebuild. See README."
        }
    }
}
