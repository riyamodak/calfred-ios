@testable import AuthorizationStore
import AppAuthCore
import CalendarDomain
import Foundation
import GoogleCalendarProvider
import XCTest

final class GoogleProbeTests: XCTestCase {
    func testRateLimitedOAuthErrorRemainsTransientAfterAppAuthInvalidatesState() {
        let httpError = NSError(domain: OIDHTTPErrorDomain, code: 429)
        let oauthError = NSError(domain: OIDOAuthTokenErrorDomain, code: -1, userInfo: [
            OIDOAuthErrorResponseErrorKey: ["error": "rate_limit_exceeded"],
            NSUnderlyingErrorKey: httpError
        ])
        XCTAssertEqual(GoogleRefreshFailure.classify(oauthError, stateIsAuthorized: false), .transient)
        for code in ["temporarily_unavailable", "server_error"] {
            let error = NSError(domain: OIDOAuthTokenErrorDomain, code: -1, userInfo: [
                OIDOAuthErrorResponseErrorKey: ["error": code]
            ])
            XCTAssertEqual(GoogleRefreshFailure.classify(error, stateIsAuthorized: false), .transient)
        }
    }

    func testRevokedGrantRequiresReconnectButNetworkFailureDoesNot() {
        let revoked = NSError(domain: OIDOAuthTokenErrorDomain, code: -10, userInfo: [
            OIDOAuthErrorResponseErrorKey: ["error": "invalid_grant"],
            NSUnderlyingErrorKey: NSError(domain: OIDHTTPErrorDomain, code: 400)
        ])
        XCTAssertEqual(GoogleRefreshFailure.classify(revoked, stateIsAuthorized: false), .reconnect)
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        XCTAssertEqual(GoogleRefreshFailure.classify(offline, stateIsAuthorized: true), .transient)
        let unavailable = NSError(domain: OIDHTTPErrorDomain, code: 503)
        XCTAssertEqual(GoogleRefreshFailure.classify(unavailable, stateIsAuthorized: false), .transient)
    }

    func testReadOnlyGrantCannotWriteAndCompleteWriteGrantCanBrowse() {
        let read = GoogleCapabilities(scopes: Set(GoogleAuthorizationPurpose.browse.requestedScopes))
        XCTAssertTrue(read.permits(.browse))
        XCTAssertFalse(read.permits(.save))
        let write = GoogleCapabilities(scopes: Set(GoogleAuthorizationPurpose.save.requestedScopes))
        XCTAssertTrue(write.permits(.browse))
        XCTAssertTrue(write.permits(.save))
        XCTAssertFalse(write.scopes.contains(GoogleCapabilities.eventsRead))
    }

    func testPartialOrLookalikeScopesNeverPermitSaving() {
        let partials: [Set<String>] = [
            ["openid", GoogleCapabilities.eventsWrite],
            ["openid", GoogleCapabilities.calendarListRead],
            [GoogleCapabilities.calendarListRead, GoogleCapabilities.eventsWrite],
            ["openid", GoogleCapabilities.calendarListRead, GoogleCapabilities.eventsWrite + ".readonly"],
            ["openid", "https://www.googleapis.com/auth/calendar"]
        ]
        for scopes in partials { XCTAssertFalse(GoogleCapabilities(scopes: scopes).permits(.save)) }
    }

    func testScopeResponseParsingChecksWholeGrantedTokens() {
        let scope = "openid\n\(GoogleCapabilities.calendarListRead)  \(GoogleCapabilities.eventsWrite)"
        XCTAssertTrue(GoogleCapabilities(scopeString: scope).permits(.save))
        XCTAssertFalse(GoogleCapabilities(scopeString: "").permits(.browse))
        XCTAssertFalse(GoogleCapabilities(scopeString: scope.uppercased()).permits(.save))
        XCTAssertEqual(Set(GoogleAuthorizationPurpose.save.requestedScopes),
                       ["openid", GoogleCapabilities.calendarListRead, GoogleCapabilities.eventsWrite])
    }

    func testAllDayCopyHasExclusiveEndAndNoSourceSemanticsOrDefaultReminders() throws {
        let event = SharedEvent(title: "October trip", time: .allDay(
            startDate: try LocalDate("2026-10-10"), endDateExclusive: try LocalDate("2026-10-13")),
            location: "Chicago", note: "Opted in", isSingleOccurrence: true)
        let body = try dictionary(ShareSnapshot(event: event))
        XCTAssertEqual(body["start"] as? [String: String], ["date": "2026-10-10"])
        XCTAssertEqual(body["end"] as? [String: String], ["date": "2026-10-13"])
        XCTAssertEqual(body["eventType"] as? String, "default")
        XCTAssertEqual(body["transparency"] as? String, "transparent")
        XCTAssertEqual(body["description"] as? String, "Opted in")
        let reminders = try XCTUnwrap(body["reminders"] as? [String: Any])
        XCTAssertEqual(reminders["useDefault"] as? Bool, false)
        XCTAssertEqual((reminders["overrides"] as? [Any])?.count, 0)
        XCTAssertEqual(Set(body.keys), ["id", "summary", "eventType", "transparency", "reminders",
                                         "extendedProperties", "location", "description", "start", "end"])
        for excluded in ["attendees", "organizer", "recurrence", "iCalUID", "conferenceData", "attachments", "source"] {
            XCTAssertNil(body[excluded])
        }
    }

    func testTimedCopyPreservesInstantsAndDistinctZones() throws {
        let start = try EventTimestamp.parse("2026-11-01T05:30:00.123Z")
        let end = try EventTimestamp.parse("2026-11-01T07:30:00.456Z")
        let event = SharedEvent(title: "Overnight", time: .timed(
            startInstant: start, endInstant: end,
            startTimeZone: "America/New_York", endTimeZone: "America/Chicago"))
        let body = try dictionary(ShareSnapshot(event: event))
        let startBody = try XCTUnwrap(body["start"] as? [String: String])
        let endBody = try XCTUnwrap(body["end"] as? [String: String])
        XCTAssertEqual(try EventTimestamp.parse(XCTUnwrap(startBody["dateTime"])), start)
        XCTAssertEqual(try EventTimestamp.parse(XCTUnwrap(endBody["dateTime"])), end)
        XCTAssertEqual(startBody["timeZone"], "America/New_York")
        XCTAssertEqual(endBody["timeZone"], "America/Chicago")
        XCTAssertNil(body["description"])
        XCTAssertNil(body["location"])
    }

    func testCopyIDIsNewPerOperationAndStableForSameOperation() throws {
        let snapshot = ShareSnapshot(event: fixtureEvent())
        let operation = UUID()
        let first = try GoogleCalendarProvider.makeEventBody(snapshot: snapshot, operationID: operation)
        XCTAssertEqual(first, try GoogleCalendarProvider.makeEventBody(snapshot: snapshot, operationID: operation))
        let firstBody = try XCTUnwrap(JSONSerialization.jsonObject(with: first) as? [String: Any])
        let id = try XCTUnwrap(firstBody["id"] as? String)
        XCTAssertTrue(id.allSatisfy { "0123456789abcdefghijklmnopqrstuv".contains($0) })
        XCTAssertTrue((5...1024).contains(id.count))
        XCTAssertNotEqual(id, snapshot.shareId.uuidString)
        let other = try dictionary(snapshot)
        XCTAssertNotEqual(id, other["id"] as? String)
    }

    func testCopyRejectsMalformedDatesAndUnsupportedSchemaBeforeWriting() throws {
        let bad = SharedEvent(title: "Invalid", time: .timed(
            startInstant: Date(timeIntervalSince1970: 20), endInstant: Date(timeIntervalSince1970: 10),
            startTimeZone: nil, endTimeZone: nil))
        XCTAssertThrowsError(try dictionary(ShareSnapshot(event: bad)))
        XCTAssertThrowsError(try dictionary(ShareSnapshot(schemaVersion: 2, event: fixtureEvent())))
    }

    private func fixtureEvent() -> SharedEvent {
        SharedEvent(title: "Probe", time: .timed(startInstant: Date(timeIntervalSince1970: 10),
                    endInstant: Date(timeIntervalSince1970: 20), startTimeZone: nil, endTimeZone: nil))
    }

    private func dictionary(_ snapshot: ShareSnapshot) throws -> [String: Any] {
        let data = try GoogleCalendarProvider.makeEventBody(snapshot: snapshot, operationID: UUID())
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
