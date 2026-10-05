# M0 feasibility report

Updated: **October 5, 2026** (America/New_York). Status: **Apple permission, calendar inventory, sample opening, and a successful extension save reported on one physical iPhone; remaining M0 gates pending**. The user configured signing and ran the companion and extension on an iPhone 16 Pro with iOS 26.7. Google authorization, shared-state restoration through the companion, shared Keychain operation, and two-device message delivery have not been verified. Do not treat any pending row as passed.

## User-reported device observation

On October 4, the user reported this sequence on **iPhone 16 Pro / iOS 26.7** (exact OS build and app build not supplied):

1. Installed a signed build through Xcode; the companion launched and the extension appeared in Messages. The extension initially appeared empty; the cause was not established.
2. Tapped the Apple access button in the companion, saw the iOS permission prompt, and allowed full access.
3. Returned to the extension, which reported full access. Its calendar-list action reported **5 device calendars, 3 writable**, with **no additional permission prompt**.
4. Calendar names were not visible on the extension home screen because the original UI only displayed destinations inside a receive test. The updated UI now exposes the full calendar inventory in both app and extension, automatically loads already-authorized calendars, and offers Refresh. The October 5 screenshot below later confirmed the extension inventory UI.
5. The user subsequently reported that **Open sample to test saving** briefly showed “Working…” then returned without opening the sample. No compose content appeared (this local test is not supposed to insert a message). Local inspection found `APP_GROUP_IDENTIFIER` still used the copied example. The code saves pending state before showing a receive and previously reported failure only in the lower Test status section. The change rejects that placeholder explicitly, displays the error beside the button, and expands/scrolls to a successfully opened receive. The subsequent error report and successful retest are recorded below.

On October 5, the user reported a custom App Group identifier with a free account and no portal registration. The sample showed **“Configure URLs in Configuration/Local.xcconfig”**; the screenshot also confirms the extension's named-calendar inventory and read-only labels. Inspection found a separate code blocker: eager configuration initialization parsed unrelated Google/transport URLs before checking App Group storage. The fix validates each setting only when its feature uses it. This corrects the earlier incomplete diagnosis; the old error did not establish whether signed App Group access works. Apple's current capability table lists App Groups as supported for free accounts; The subsequent sample/save retest succeeded as recorded below; companion access to shared state and Keychain behavior remain unverified.

Later on October 5, the user confirmed that the sample opens, certain fields can be edited, a destination can be chosen, and the saved event appears in Apple Calendar. This exercises extension-side pending-state persistence before the provider write. It does not independently verify companion access to the same storage, restoration after termination, shared Keychain, exact saved-field/date semantics, or duplicate handling. Exact app build remains unspecified.

This is evidence for the app-first permission/listing sequence, extension calendar inventory, and a successful Apple event creation on this device. The extension-first sequence and denied/restricted states remain unverified. No private event or account names were recorded.

## Local evidence

| Check | Observation |
| --- | --- |
| Environment | Initial validation: Xcode 15.0.1 (15A507), Swift 5.9 / iOS 17 SDK. Calendar-list UI compilation: Xcode 27.0 (27A266a) |
| Native project | Companion app + embedded Messages extension + local Swift package; project and Info.plists parse successfully |
| Debug simulator build | Passed for arm64 and x86_64, signing disabled |
| Debug iPhone SDK build | Passed for arm64, signing disabled; this is compilation, not device execution |
| Updated Apple calendar-list UI | iPhone SDK build passed with Xcode 27.0. Simulator build encountered mixed arm64/x86_64 package targets; an arm64-only retry was not authorized, so no simulator visual check was completed; the user subsequently supplied physical-device inventory and save observations above |
| Local sample-opening error and presentation fix | Unsigned iPhone SDK build passed with Xcode 27.0; placeholder App Group rejection, inline failure instructions, and expanded/scrolled receive compiled. The user subsequently confirmed sample opening and saving on the phone; full restoration/signing matrix remains pending |
| October 5 configuration isolation fix | Unsigned iPhone SDK build passed. Four new configuration regression tests passed using a standalone macOS XCTest runner compiled from the unchanged production configuration source and test methods. Full `swift test` rerun was blocked by AppAuth Git checkout/tag-resolution errors, including attempts using the existing cache and pinned revision. Device sample opening and an Apple save were subsequently confirmed by the user |
| Simulator launch smoke check | App installed and launched on iPhone 15 simulator / iOS 17.0 with unconfigured example identifiers; no provider or Messages interaction verified |
| Shared unit tests | **34 passed, 0 failures** on macOS: 14 codec/date, 9 Google scope/mapping/error-classification, 8 pending-state/lock, 3 destination-restoration tests |
| AppAuth split | AppAuth 1.7.6 resolved. Extension binary contains AppAuthCore state/refresh symbols and no `OIDExternalUserAgentIOS` presentation class; app links presentation code |
| Signed shared Keychain/App Group | Extension-side pending-state writes exercised by the reported Apple save; cross-process restoration and shared Keychain remain untested |
| Apple/Google network or calendar writes | User confirmed one Apple save visible in Apple Calendar. Google writes and remote-sync behavior remain untested; the agent performed no real provider writes |
| Full current-iOS matrix | **Not completed**; user reported partial permission/listing/UI results on iOS 26.7. Latest local compilation used Xcode 27.0; compilation is not device execution |

No local logs contain tokens, account addresses, full message URLs, or real event contents. The visible probe UI shows actual scope names, synthetic event content, payload digest/size, and OS version for manual recording. Keep test notes free of private credentials and message payloads.

## Required physical-device matrix

For each row record tester, date, phone models, exact iOS versions/builds on both ends, app build, grant scopes where relevant, observation, and pass/fail. Partial results below come from the user's device report; other rows remain untested.

| ID | Procedure and required observation | Status |
| --- | --- | --- |
| M0-1a | In a 1:1 iMessage conversation, insert the ordinary sample, confirm it remains a draft until manual Send, send to the second phone, open and compare share ID, URL length and full SHA-256. Inspect complete decoded title/dates/location. | Not run |
| M0-1b | Repeat in a group; have two recipients open the same card. A recipient's local Add must not alter anyone else's card/state. | Not run |
| M0-1c | Send the near-limit Unicode fixture (expected approximately 4,500 URL characters). Verify all Unicode title/location/note content and digest survive. | Not run |
| M0-1d | Select another sample with a compose draft present: observe replacement behavior. Retry a failed insertion: same share ID. Select afresh: new share ID. Record actual Messages behavior. | Not run |
| M0-2a | Fresh permissions: open extension without Apple action, then request full access explicitly. List calendars and write only after selecting an existing writable destination and tapping Add. | Partial: after companion grant, extension reported 5 calendars / 3 writable on iPhone 16 Pro, iOS 26.7. Sample opening, editing controls, destination selection and one Apple save confirmed October 5. Extension-first prompt and no-write-before-Add checks remain pending |
| M0-2b | Request first in companion vs first in extension on clean permission states; record **whether separate prompts occur**. Exercise denial/write-only/restriction where possible. | Partial: companion displayed a prompt; extension subsequently listed without another prompt. Reverse order and other states not run |
| M0-2c | Verify actual destination, all-day dates, timed/DST instants, Free support, no recurrence, attendees/invitations or alarms. Distinguish local device-store success from remote sync. | Partial: event creation visible in Apple Calendar confirmed. Detailed saved-field/date/property inspection and remote sync not yet reported |
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

- **Remaining external configuration:** signing, extension pending-state persistence and an Apple save have been reported. Cross-process App Group/Keychain behavior, real Google authorization and the owned transport URL still require the [README checklist](../README.md).
- **Incomplete physical-device observations:** extend the one-device Apple report to the full matrix on two signed iPhones before starting M1. Record impossible-to-arrange permission states as untested.
- **Opening setup is a feasibility question:** manual setup/return instructions are already implemented as the smallest fallback. No automatic conversation return is promised.
- **If fragment/forwarding fails:** retain the failing payload size/digest and OS metadata without logging content. Isolate a reduced synthetic case before choosing a new documented transport. No fallback transport is claimed to work here.
- **If AppAuthCore/shared Keychain refresh fails:** inspect actual signed entitlements and granted/refresh scopes, then fix the extension-safe credential path before continuing. Do not route every routine save through companion authorization.
- **If a refresh response omits verifiable scopes:** this harness fails closed; do not infer requested scopes were granted. Investigate the real response and an authoritative capability check before accepting the connection.
- **Uncertain saves:** M0 persists an attempted flag and prevents blind retries for that pending probe. Inspect the test calendar manually, then explicitly clear it to start another test. This is not M3 reconciliation or production deduplication.

Setup return reloads a selected Google calendar and checks its current writable status before enabling Add. Removed/read-only destinations require a new selection; an unavailable listing preserves edits and selection while keeping Add disabled. A storage failure before the provider call reports that no calendar write was made; a failure to retain an already-confirmed success keeps that calendar confirmation visible. These behaviors have been reviewed and compiled locally; the real setup-return matrix above remains untested.

The user has observed Apple permission, calendar inventory, sample opening/editing/selection, and a successful Apple save on one physical device. The remaining matrix requires further device testing before M0 can be marked complete.
