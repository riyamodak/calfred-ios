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
- [x] Preserve receive edits and explicit destination through setup; never write after consent.
- [x] Revalidate the selected destination after setup; preserve edits and disable Add when calendar access cannot be verified.
- [x] Run available local builds and focused unit tests (34 tests passed; unsigned simulator/iPhone SDK builds; companion simulator launch).
- [x] Record local evidence and remaining device feasibility gates in [M0-FEASIBILITY.md](M0-FEASIBILITY.md).

User configuration and execution:

- [x] User configured Apple signing and app/extension identifiers and ran both on iPhone 16 Pro / iOS 26.7.
- [x] User observed the companion full-access prompt, then extension enumeration of 5 calendars / 3 writable without a second prompt (app-first sequence).
- [x] October 5 user screenshot confirms calendar names and read-only labels are visible in the extension.
- [x] October 5 user confirmed the sample opens, fields can be edited, a destination can be chosen, and the saved event appears in Apple Calendar. This also exercises extension-side pending-state persistence before the write.
- [ ] Verify pending-state restoration across termination and companion setup/return; verify shared Keychain independently. A successful extension save does not prove companion access to the shared state.
- [ ] Inspect the saved copy's edited values, exact dates, destination, availability, and absence of recurrence, attendees, and alerts; test access revocation and repeat-Add prevention.
- [ ] Google Cloud Calendar API, consent/test users, and iOS OAuth client.
- [ ] Owned HTTPS help URL for transport and installed/uninstalled recipient tests.
- [ ] Two signed physical iPhones and Google test accounts; execute `docs/M0-FEASIBILITY.md`.
- [ ] Complete the current iOS/Xcode matrix (selected Xcode is now 27.0; initial local validation used Xcode 15.0.1 / iOS 17 SDK).

The user has reported the physical-device observations above, including one successful Apple Calendar save. Google flows, setup/return restoration, and two-device message tests remain unverified.

The implementation checklist is complete. **M0's feasibility exit gate remains open** until the external configuration and physical-device observations above are supplied and the matrix passes. M1–M4 have not been implemented.
