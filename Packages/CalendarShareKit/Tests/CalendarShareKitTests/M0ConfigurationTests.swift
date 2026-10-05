import Foundation
import SharedStore
import XCTest

final class M0ConfigurationTests: XCTestCase {
    func testAppGroupCanBeReadWithAbsentOrMalformedUnrelatedURLs() throws {
        for extra in [[:], ["CalendarShareGoogleRedirectScheme": "not a scheme",
                            "CalendarShareMessageBaseURL": "https://[invalid"]] {
            let settings = M0ConfigurationValues(extra.merging([
                "CalendarShareAppGroup": "group.test.calendar"
            ]) { _, new in new })
            XCTAssertEqual(try settings.value("CalendarShareAppGroup"), "group.test.calendar")
        }
    }

    func testSetupReturnDoesNotRequireGoogleOrTransportURLs() throws {
        let settings = M0ConfigurationValues(["CalendarShareSetupScheme": "calendar-test"])
        XCTAssertEqual(try settings.value("CalendarShareSetupScheme"), "calendar-test")
    }

    func testTransportAndOAuthReportTheirOwnConfigurationErrors() throws {
        let settings = M0ConfigurationValues([
            "CalendarShareGoogleRedirectScheme": "not a scheme",
            "CalendarShareMessageBaseURL": "https:"
        ])
        XCTAssertThrowsError(try settings.messageBaseURL()) {
            XCTAssertTrue($0.localizedDescription.contains("MESSAGE_BASE_URL"))
        }
        XCTAssertThrowsError(try settings.googleRedirectURI()) {
            XCTAssertTrue($0.localizedDescription.contains("GOOGLE_REDIRECT_SCHEME"))
        }
    }

    func testConfiguredURLsResolveIndependently() throws {
        let transport = M0ConfigurationValues(["CalendarShareMessageBaseURL": "https://calendar.example.org/share"])
        XCTAssertEqual(try transport.messageBaseURL().absoluteString, "https://calendar.example.org/share")
        let oauth = M0ConfigurationValues(["CalendarShareGoogleRedirectScheme": "com.googleusercontent.apps.test-client"])
        XCTAssertEqual(try oauth.googleRedirectURI().absoluteString, "com.googleusercontent.apps.test-client:/oauthredirect")
    }
}
