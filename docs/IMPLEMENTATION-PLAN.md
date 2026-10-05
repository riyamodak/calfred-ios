# M0 implementation checklist

Scope: feasibility harness only. Full event browsing/search, recents, production import reconciliation, and release UI belong to M1–M4.

- [x] Read the complete specification and inspect the initially empty repository.
- [x] Create an iOS 17 SwiftUI companion, Messages extension, and shared Swift package.
- [x] Add sample/near-limit Unicode message insertion and received-payload diagnostics.
- [x] Add explicit EventKit full-access, calendar-list, and independent-copy probes.
- [x] Show all authorized device calendars in both app and extension; replace the permission action with Refresh and explain the separate save/delivery tests.
- [x] Surface sample-opening storage errors beside the button, reject the copied App Group placeholder, and expand/scroll to a successfully opened sample.
- [x] Separate configuration validation by feature so Apple shared storage never parses Google or message URLs; add regression coverage for absent/malformed unrelated settings.
- [x] Validate the configuration fix: unsigned iPhone build and four focused macOS XCTest cases passed. Full package-suite rerun encountered dependency checkout errors; the earlier 34-test result remains historical evidence.
- [x] Add both Google authorization entry paths and shared extension-safe refresh/list/write probes.
- [x] Display all returned Google calendars, including read-only entries, in both targets; show list failures inline and load the connected inventory when the extension activates.
- [x] Show the message help-URL requirement beside disabled insertion buttons before a probe starts; show actual insertion failures beside Retry.
- [x] Preserve receive edits and explicit destination through setup; never write after consent.
- [x] Revalidate the selected destination after setup; preserve edits and disable Add when calendar access cannot be verified.
- [x] Run available local builds and focused unit tests (34 tests passed; unsigned simulator/iPhone SDK builds; companion simulator launch).
- [x] Record local evidence and remaining device feasibility gates in [M0-FEASIBILITY.md](M0-FEASIBILITY.md).

User configuration and execution:

- [x] User configured Apple signing and app/extension identifiers and ran both on iPhone 16 Pro / iOS 26.7.
- [x] User observed the companion full-access prompt, then extension enumeration of 5 calendars / 3 writable without a second prompt (app-first sequence).
- [x] October 5 user screenshot confirms calendar names and read-only labels are visible in the extension.
- [x] October 5 user confirmed the sample opens, fields can be edited, a destination can be chosen, and the saved event appears in Apple Calendar. This also exercises extension-side pending-state persistence before the write.
- [x] User reported all five follow-up Apple checks passed: saved-copy inspection, no save before Add, draft restoration after leaving/reopening Messages, repeat-Add prevention for the same pending receive, and access revocation/recovery.
- [x] User configured Google Cloud/auth details and reported successful browsing sign-in followed by the saving-access upgrade.
- [x] User confirmed Google calendars are now listed and a sample can be sent after configuring MESSAGE_BASE_URL.
- [ ] Verify forced refresh, actual scopes, direct Google saving, expiry/cold launch, and shared Keychain. Listing alone does not prove writing or refresh after expiry.
- [ ] Verify pending edits/destination through Google consent, cancellation, and account switching. Apple-only companion navigation/restoration was reported passed.
- [x] User configured MESSAGE_BASE_URL to the repository help-file URL; sample sending now succeeds.
- [ ] Verify the help/installation experience for an uninstalled recipient and reopening after installation; verify received payloads on another signed phone.
- [ ] Two signed physical iPhones and Google test accounts; execute `docs/M0-FEASIBILITY.md`.
- [ ] Complete the current iOS/Xcode matrix (selected Xcode is now 27.0; initial local validation used Xcode 15.0.1 / iOS 17 SDK).

The user has reported the physical-device observations above. Google sign-in/upgrade, calendar listing, and sample sending have been reported. Google saving/expiry refresh and recipient decoding/save tests remain unverified. Message URL configuration no longer blocks sending.

The implementation checklist is complete. **M0's feasibility exit gate remains open** until the external configuration and physical-device observations above are supplied and the matrix passes. M1–M4 have not been implemented.
