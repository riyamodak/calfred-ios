# M0 feasibility report

Date: **October 4, 2026** (America/New_York). Status: **implementation available; device feasibility not yet proved**. No physical iPhone was used, no real Google account was authorized, and no signed provisioning configuration was supplied. Do not treat any pending row as passed.

## Local evidence

| Check | Observation |
| --- | --- |
| Environment | Xcode 15.0.1 (15A507), Apple Swift 5.9; iOS 17.0 SDK and simulator runtime |
| Native project | Companion app + embedded Messages extension + local Swift package; project and Info.plists parse successfully |
| Debug simulator build | Passed for arm64 and x86_64, signing disabled |
| Debug iPhone SDK build | Passed for arm64, signing disabled; this is compilation, not device execution |
| Simulator launch smoke check | App installed and launched on iPhone 15 simulator / iOS 17.0 with unconfigured example identifiers; no provider or Messages interaction verified |
| Shared unit tests | **34 passed, 0 failures** on macOS: 14 codec/date, 9 Google scope/mapping/error-classification, 8 pending-state/lock, 3 destination-restoration tests |
| AppAuth split | AppAuth 1.7.6 resolved. Extension binary contains AppAuthCore state/refresh symbols and no `OIDExternalUserAgentIOS` presentation class; app links presentation code |
| Signed shared Keychain/App Group | **Not tested**; requires developer entitlements and physical devices |
| Apple/Google network or calendar writes | **Not executed** against real accounts/calendars |
| Current shipping iOS | **Not tested**; installed SDK/runtime is iOS 17.0 |

No local logs contain tokens, account addresses, full message URLs, or real event contents. The visible probe UI shows actual scope names, synthetic event content, payload digest/size, and OS version for manual recording. Keep test notes free of private credentials and message payloads.

## Required physical-device matrix

For each row record tester, date, phone models, exact iOS versions/builds on both ends, app build, grant scopes where relevant, observation, and pass/fail. All observations are currently **not run**.

| ID | Procedure and required observation | Status |
| --- | --- | --- |
| M0-1a | In a 1:1 iMessage conversation, insert the ordinary sample, confirm it remains a draft until manual Send, send to the second phone, open and compare share ID, URL length and full SHA-256. Inspect complete decoded title/dates/location. | Not run |
| M0-1b | Repeat in a group; have two recipients open the same card. A recipient's local Add must not alter anyone else's card/state. | Not run |
| M0-1c | Send the near-limit Unicode fixture (expected approximately 4,500 URL characters). Verify all Unicode title/location/note content and digest survive. | Not run |
| M0-1d | Select another sample with a compose draft present: observe replacement behavior. Retry a failed insertion: same share ID. Select afresh: new share ID. Record actual Messages behavior. | Not run |
| M0-2a | Fresh permissions: open extension without Apple action, then request full access explicitly. List calendars and write only after selecting an existing writable destination and tapping Add. | Not run |
| M0-2b | Request first in companion vs first in extension on clean permission states; record **whether separate prompts occur**. Exercise denial/write-only/restriction where possible. | Not run |
| M0-2c | Verify actual destination, all-day dates, timed/DST instants, Free support, no recurrence, attendees/invitations or alarms. Distinguish local device-store success from remote sync. | Not run |
| M0-3a | Google browsing entry requests list-read + events-read + openid. Verify actual granted scopes and list in extension with Google sync disabled in iPhone Settings. | Not run |
| M0-3b | Upgrade the read-only connection through a new full-set authorization: list-read + events-write + openid. Candidate's own refresh must retain writing capability. Verify explicit Add works in extension. | Not run |
| M0-3c | Start disconnected and connect from receiving with the complete read/write set. Verify list and explicit Add in extension. | Not run |
| M0-3d | Repeat canceled, denied and partial-grant upgrades. Prior browsing works only if still valid; incomplete candidate never replaces it. Pending receive edits remain. | Not run |
| M0-3e | Switch Google accounts. Old destination clears, a new explicit selection is required, and no credentials/destination are combined across accounts. | Not run |
| M0-3f | For **each** successful initial/upgrade path: force-refresh from extension; then separately wait past displayed expiry, terminate app/extension, cold-launch Messages and list/save. Verify shared Keychain/refresh after cold launch. Forced refresh alone does not pass the expiry check. | Not run |
| M0-3g | Revoke Google access externally; refresh must show reconnect. Test network outage without destroying valid prior credentials. | Not run |
| M0-4a | Edit received title/location/note and choose a calendar, open setup through extension context, complete/cancel consent, return manually. Restore the combined screen and edits. Keep destination only if account and calendar are still valid. | Not run |
| M0-4b | Inspect destination before final Add: **no event exists due to consent or calendar selection**. Repeat with extension termination during setup. | Not run |
| M0-4c | If extension setup opening fails, follow manual Home Screen instructions; recover the pending screen by reopening the original message. Record actual open result. | Not run |
| M0-5a | Send to a phone without the app; record readable preview and exact installation/help behavior, without assuming an automatic App Store screen. Install via the developer-supplied channel and reopen the original card. | Not run |
| M0-5b | Forward ordinary and near-limit cards through supported 1:1/group paths and compare digest. Confirm HTTPS fragment round trip after delivery/forwarding and after installation/reopening. | Not run |

Provider details: [Apple checklist](APPLE-M0.md), [Google checklist](GOOGLE-M0.md).

## Execution blockers and smallest adjustments

- **External configuration is missing:** use the [README checklist](../README.md). Signed runtime operations and real Google authorization cannot be proved with example identifiers.
- **No current physical-device observations:** run the matrix on two signed iPhones before starting M1. Compilation is not a substitute. Record impossible-to-arrange permission states as untested.
- **Opening setup is a feasibility question:** manual setup/return instructions are already implemented as the smallest fallback. No automatic conversation return is promised.
- **If fragment/forwarding fails:** retain the failing payload size/digest and OS metadata without logging content. Isolate a reduced synthetic case before choosing a new documented transport. No fallback transport is claimed to work here.
- **If AppAuthCore/shared Keychain refresh fails:** inspect actual signed entitlements and granted/refresh scopes, then fix the extension-safe credential path before continuing. Do not route every routine save through companion authorization.
- **If a refresh response omits verifiable scopes:** this harness fails closed; do not infer requested scopes were granted. Investigate the real response and an authoritative capability check before accepting the connection.
- **Uncertain saves:** M0 persists an attempted flag and prevents blind retries for that pending probe. Inspect the test calendar manually, then explicitly clear it to start another test. This is not M3 reconciliation or production deduplication.

Setup return reloads a selected Google calendar and checks its current writable status before enabling Add. Removed/read-only destinations require a new selection; an unavailable listing preserves edits and selection while keeping Add disabled. A storage failure before the provider call reports that no calendar write was made; a failure to retain an already-confirmed success keeps that calendar confirmation visible. These behaviors have been reviewed and compiled locally; the real setup-return matrix above remains untested.

No core runtime path has yet been observed failing or passing on a physical device. The current result is an executable harness with explicit remaining gates, not a completed feasibility proof.
