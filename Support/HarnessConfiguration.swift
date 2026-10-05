import Foundation
import CalendarDomain
import MessageCodec
import SharedStore
import AuthorizationStore
import GoogleCalendarProvider

struct HarnessConfiguration {
    private let values: M0ConfigurationValues
    var appGroup: String { get throws { try values.value("CalendarShareAppGroup") } }
    var keychainGroup: String { get throws { try values.value("CalendarShareKeychainGroup") } }
    var setupScheme: String { get throws { try values.value("CalendarShareSetupScheme") } }
    var clientID: String { get throws { try values.value("CalendarShareGoogleClientID") } }
    var redirectURI: URL { get throws { try values.googleRedirectURI() } }

    init(bundle: Bundle = .main) {
        values = M0ConfigurationValues((bundle.infoDictionary ?? [:]).compactMapValues { $0 as? String })
    }

    func containerURL() throws -> URL {
        let appGroup = try appGroup
        guard !appGroup.contains("com.example"),
              !appGroup.contains("your.owned.identifier"),
              !appGroup.contains("YOUR_"),
              let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            throw ConfigurationError.appGroupUnavailable
        }
        return url
    }

    func googleStore() throws -> GoogleAuthorizationStore {
        let clientID = try clientID
        guard !clientID.contains("REPLACE_ME"), !clientID.contains("YOUR_") else {
            throw ConfigurationError.missing("Google iOS OAuth client")
        }
        return GoogleAuthorizationStore(keychainAccessGroup: try keychainGroup,
                                        lockURL: try containerURL().appendingPathComponent("google-auth.lock"))
    }

    func codec() throws -> MessageCodec {
        try MessageCodec(baseURL: values.messageBaseURL())
    }
}

typealias ConfigurationError = M0ConfigurationError
