# M0 implementation checklist

Scope: feasibility harness only. Full event browsing/search, recents, production import reconciliation, and release UI belong to M1–M4.

- [x] Read the complete specification and inspect the initially empty repository.
- [x] Create an iOS 17 SwiftUI companion, Messages extension, and shared Swift package.
- [x] Add sample/near-limit Unicode message insertion and received-payload diagnostics.
- [x] Add explicit EventKit full-access, calendar-list, and independent-copy probes.
- [x] Add both Google authorization entry paths and shared extension-safe refresh/list/write probes.
- [x] Preserve receive edits and explicit destination through setup; never write after consent.
- [x] Revalidate the selected destination after setup; preserve edits and disable Add when calendar access cannot be verified.
- [x] Run available local builds and focused unit tests (34 tests passed; unsigned simulator/iPhone SDK builds; companion simulator launch).
- [x] Record local evidence and remaining device feasibility gates in [M0-FEASIBILITY.md](M0-FEASIBILITY.md).

User configuration and execution:

- [ ] Apple Developer team, app/extension identifiers, App Group, shared Keychain, and signing profiles.
- [ ] Google Cloud Calendar API, consent/test users, and iOS OAuth client.
- [ ] Owned HTTPS help URL for transport and installed/uninstalled recipient tests.
- [ ] Two signed physical iPhones and Google test accounts; execute `docs/M0-FEASIBILITY.md`.
- [ ] Current shipping iOS/Xcode testing (this machine has Xcode 15.0.1 / iOS 17 SDK).

No physical-device test has been performed by this implementation task.

The implementation checklist is complete. **M0's feasibility exit gate remains open** until the external configuration and physical-device observations above are supplied and the matrix passes. M1–M4 have not been implemented.
