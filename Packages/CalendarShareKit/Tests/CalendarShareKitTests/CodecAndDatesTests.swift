import CalendarDomain
import Foundation
import MessageCodec
import XCTest

final class CodecAndDatesTests: XCTestCase {
    private func codec() throws -> MessageCodec {
        try MessageCodec(baseURL: XCTUnwrap(URL(string: "https://calendar.example.test/share")))
    }

    func testAllDayPayloadRoundTripAndDigest() throws {
        let codec = try codec()
        let original = M0Samples.allDaySnapshot()
        let url = try codec.encode(original)
        let decoded = try codec.decode(url)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(try codec.digest(decoded), try codec.digest(original))
        XCTAssertEqual(try codec.digest(decoded).count, 64)
        XCTAssertNil(URLComponents(url: url, resolvingAgainstBaseURL: false)?.query)
    }

    func testTimedDSTOccurrencePreservesInstantsAndZones() throws {
        let codec = try codec()
        let original = M0Samples.timedSnapshot()
        let decoded = try codec.decode(codec.encode(original))
        XCTAssertEqual(decoded, original)
        guard case let .timed(start, end, startZone, endZone) = decoded.event.time else {
            return XCTFail("Expected timed event")
        }
        XCTAssertEqual(end.timeIntervalSince(start), 7_200)
        XCTAssertEqual(startZone, "America/New_York")
        XCTAssertEqual(endZone, "America/New_York")
        XCTAssertTrue(decoded.event.isSingleOccurrence)
    }

    func testNearLimitUnicodeFitsAndRoundTripsCompletely() throws {
        let codec = try codec()
        let original = try codec.nearLimitSnapshot()
        let url = try codec.encode(original)
        XCTAssertGreaterThanOrEqual(url.absoluteString.utf8.count, 4_400)
        XCTAssertLessThanOrEqual(url.absoluteString.utf8.count, MessageCodec.maximumURLLength)
        let decoded = try codec.decode(url)
        XCTAssertEqual(decoded, original)
        XCTAssertTrue(decoded.event.note?.contains("مرحبا") == true)
        XCTAssertEqual(try codec.digest(decoded), try codec.digest(original))
    }

    func testOversizeRequiredContentIsRejectedWithoutTruncation() throws {
        let codec = try codec()
        var event = M0Samples.allDaySnapshot().event
        event.title = String(repeating: "a", count: 2_000)
        event.location = String(repeating: "b", count: 2_000)
        let snapshot = ShareSnapshot(event: event)
        XCTAssertThrowsError(try codec.encode(snapshot)) { error in
            XCTAssertEqual(error as? MessageCodecError, .oversizedPayload)
        }
        XCTAssertEqual(snapshot.event.title.count, 2_000)
        XCTAssertEqual(snapshot.event.location?.count, 2_000)
    }

    func testOversizeURLIsRejectedBeforeDecoding() throws {
        let codec = try codec()
        let url = try XCTUnwrap(URL(string: "https://calendar.example.test/share#" + String(repeating: "a", count: 4_500)))
        XCTAssertThrowsError(try codec.decode(url)) { error in
            XCTAssertEqual(error as? MessageCodecError, .oversizedPayload)
        }
    }

    func testUnexpectedTransportComponentsAreRejected() throws {
        let codec = try codec()
        let valid = try codec.encode(M0Samples.allDaySnapshot())
        let fragment = try XCTUnwrap(URLComponents(url: valid, resolvingAgainstBaseURL: false)?.fragment)
        for base in ["http://calendar.example.test/share", "https://other.example.test/share",
                     "https://calendar.example.test/other", "https://calendar.example.test:443/share",
                     "https://user@calendar.example.test/share", "https://calendar.example.test/share?x=1",
                     "https://calendar.example.test/sh%61re"] {
            let url = try XCTUnwrap(URL(string: base + "#" + fragment))
            XCTAssertThrowsError(try codec.decode(url), base)
        }
    }

    func testInvalidBaseURLsAreRejected() throws {
        for string in ["http://calendar.example.test/share", "https://calendar.example.test/share#fragment",
                       "https://calendar.example.test/share?q=x", "https://calendar.example.test"] {
            XCTAssertThrowsError(try MessageCodec(baseURL: XCTUnwrap(URL(string: string))))
        }
    }

    func testUnknownSchemaShowsUpdateError() throws {
        let codec = try codec()
        let url = try mutatedURL { $0["schemaVersion"] = 9 }
        XCTAssertThrowsError(try codec.decode(url)) { error in
            XCTAssertEqual(error as? MessageCodecError, .unsupportedSchema(9))
        }
    }

    func testMalformedDatesAndMixedTimeVariantsAreRejected() throws {
        let codec = try codec()
        let modifications: [(inout [String: Any]) -> Void] = [
            { $0["startDate"] = "2026-02-30" },
            { $0["endDateExclusive"] = "2026-10-09" },
            { $0["startInstant"] = "2026-10-10T00:00:00Z" },
            { $0["kind"] = "unknown" },
            { $0["startDate"] = 20261010 }
        ]
        for mutation in modifications {
            let url = try mutatedURL { root in
                var event = root["event"] as! [String: Any]
                var time = event["time"] as! [String: Any]
                mutation(&time)
                event["time"] = time
                root["event"] = event
            }
            XCTAssertThrowsError(try codec.decode(url))
        }
        let timedWithAllDay = try mutatedURL(snapshot: M0Samples.timedSnapshot()) { root in
            var event = root["event"] as! [String: Any]
            var time = event["time"] as! [String: Any]
            time["startDate"] = "2026-10-10"
            event["time"] = time
            root["event"] = event
        }
        XCTAssertThrowsError(try codec.decode(timedWithAllDay))
    }

    func testPayloadDoesNotContainLocalOrSourceIdentity() throws {
        let codec = try codec()
        let data = try codec.canonicalData(M0Samples.allDaySnapshot())
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(root.keys), ["schemaVersion", "shareId", "createdAt", "event"])
        let event = try XCTUnwrap(root["event"] as? [String: Any])
        XCTAssertEqual(Set(event.keys), ["title", "time", "location", "isSingleOccurrence"])
        XCTAssertNil(event["note"], "Notes are omitted by default")
        let poisoned = try mutatedURL { root in root["accountKey"] = "untrusted-account" }
        XCTAssertThrowsError(try codec.decode(poisoned))
    }

    func testMalformedAndNonCanonicalBase64AreRejected() throws {
        let codec = try codec()
        for fragment in ["a", "****", "e30=", "e30%3D", "%%", "e30"] {
            var components = try XCTUnwrap(URLComponents(string: "https://calendar.example.test/share"))
            components.fragment = fragment
            let url = try XCTUnwrap(components.url)
            XCTAssertThrowsError(try codec.decode(url))
        }
    }

    func testGregorianDateValidationAndStrictTimestamps() throws {
        XCTAssertEqual(try LocalDate("2028-02-29").description, "2028-02-29")
        for string in ["2026-02-29", "2026-13-01", "2026-04-31", "2026-1-01", "0000-01-01", "２０２６-10-10"] {
            XCTAssertThrowsError(try LocalDate(string), string)
        }
        for string in ["2026-02-30T10:00:00Z", "2026-10-10T24:00:00Z", "2026-10-10T00:00:00", "2026-10-10T00:60:00Z"] {
            XCTAssertThrowsError(try EventTimestamp.parse(string), string)
        }
    }

    func testAllDayDatesStayLocalAcrossTimeZones() throws {
        let start = try LocalDate("2026-10-10")
        let end = try LocalDate("2026-10-13")
        for name in ["America/Los_Angeles", "Asia/Tokyo", "Pacific/Kiritimati"] {
            let zone = try XCTUnwrap(TimeZone(identifier: name))
            XCTAssertEqual(LocalDate.from(try start.date(in: zone), in: zone), start)
            XCTAssertEqual(LocalDate.from(try end.date(in: zone), in: zone), end)
            XCTAssertEqual(try end.date(in: zone).timeIntervalSince(start.date(in: zone)), 3 * 86_400)
        }
    }

    func testEmptyTitleHasDisplayFallback() {
        var event = M0Samples.allDaySnapshot().event
        event.title = " \n"
        XCTAssertEqual(event.displayTitle, "Untitled event")
    }

    private func mutatedURL(snapshot: ShareSnapshot = M0Samples.allDaySnapshot(), mutation: (inout [String: Any]) -> Void) throws -> URL {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: codec().canonicalData(snapshot)) as? [String: Any])
        mutation(&object)
        let data = try JSONSerialization.data(withJSONObject: object)
        let fragment = data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return try XCTUnwrap(URL(string: "https://calendar.example.test/share#" + fragment))
    }
}
