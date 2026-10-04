import XCTest
import CalendarDomain
import MessageCodec

final class ReceiveDestinationTests: XCTestCase {
    private func calendar(name: String = "Test", writable: Bool = true, account: String = "account") -> CalendarRef {
        CalendarRef(provider: .google, accountKey: account, calendarID: "calendar", displayName: name,
                    accountLabel: "Test account", isWritable: writable)
    }

    func testReturningFromSetupPreservesEditsAndRefreshesValidDestinationMetadata() {
        var draft = ReceiveDraft(snapshot: M0Samples.allDaySnapshot(), selectedDestination: calendar())
        draft.title = "Recipient edit"
        draft.note = "Keep this note"
        let renamed = calendar(name: "Renamed destination")

        draft.revalidateDestination(in: [renamed], provider: .google)

        XCTAssertEqual(draft.selectedDestination, renamed)
        XCTAssertEqual(draft.title, "Recipient edit")
        XCTAssertEqual(draft.note, "Keep this note")
        XCTAssertFalse(draft.writeAttempted)
    }

    func testRemovedReadOnlyOrSwitchedAccountDestinationsRequireNewSelection() {
        for available in [[], [calendar(writable: false)], [calendar(account: "other-account")]] {
            var draft = ReceiveDraft(snapshot: M0Samples.allDaySnapshot(), selectedDestination: calendar())
            draft.location = "Recipient location"

            draft.revalidateDestination(in: available, provider: .google)

            XCTAssertNil(draft.selectedDestination)
            XCTAssertEqual(draft.location, "Recipient location")
            XCTAssertFalse(draft.writeAttempted)
        }
    }

    func testListingAnotherProviderNeverClearsOrPreselectsDestination() {
        var selected = ReceiveDraft(snapshot: M0Samples.allDaySnapshot(), selectedDestination: calendar())
        selected.revalidateDestination(in: [], provider: .apple)
        XCTAssertEqual(selected.selectedDestination, calendar())

        var unselected = ReceiveDraft(snapshot: M0Samples.allDaySnapshot())
        unselected.revalidateDestination(in: [calendar()], provider: .google)
        XCTAssertNil(unselected.selectedDestination)
    }
}
