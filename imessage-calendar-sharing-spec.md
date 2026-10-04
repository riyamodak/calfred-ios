# iMessage Calendar Sharing Implementation Spec

Version 1.1 · October 3, 2026 · Working product name: Calendar Share

## 1. Purpose and outcome

Build an iPhone app with an iMessage extension that lets someone select an existing Apple or Google calendar event within a conversation, put an event card into the Messages compose field, and send it. A recipient opens the card, selects one of their own calendars, and saves an independent copy.

Example: a friend sends their vacation event in a group chat. Each person can independently save it into a different calendar without becoming an attendee, inviting anyone, or sharing an entire calendar. Travel is an example; the product supports ordinary events of any subject.

This document is a build specification. Product defaults below are proposed implementation choices, not additional requirements supplied by the user. Platform-dependent behavior must pass the feasibility milestone before the full implementation proceeds.

## 2. Confirmed requirements and proposed defaults

| Area | Decision | Status |
| --- | --- | --- |
| Entry point | Open the extension inside an existing person or group iMessage conversation | Confirmed |
| Home | Show recently used calendars across Apple and Google, separate Apple and Google browsing entry points, and Search all connected calendars | Confirmed |
| Discovery | Browse/search one calendar or search events across all connected, authorized calendars within a visible date range | Confirmed |
| Compose | Selecting an event inserts a card into the Messages compose field; the person taps the normal Send button | Confirmed; API behavior documented [S1] |
| Google | Direct Google account connection; no requirement to enable Google sync in Apple Calendar | Confirmed |
| Receiving | Event details, recent destinations, inline calendar selection, optional edits and Add share one screen; explicitly select a destination for each save | Confirmed |
| Defaults | Do not create or require a Friends calendar; do not preselect a destination | Confirmed |
| Copies | Changes and deletions never propagate between sender and recipient copies | Confirmed |
| Installation | Require installation to send or save through this product; readable message preview for others | Recommended v1 scope |
| Companion app | Minimal native app for connections, permissions, help, and settings | Proposed architecture |
| Devices | iPhone, iOS 17 or later; validate against current shipping iOS before release | Proposed baseline |
| Accounts | One directly connected Google account in v1; multiple device calendar accounts supported by EventKit | Proposed scope limit |
| Recurrence | Share one selected occurrence as a nonrecurring copy | Proposed scope limit |
| Backend | No application event database or user account system; static install/help page only | Proposed architecture |

Requiring installation on both sides preserves the intended calendar picker and in-extension save flow. A no-install recipient path would require another save experience, such as a web flow or calendar file import. Defer that until the native experience works. Do not promise that the operating system automatically launches a specific installation screen; verify the actual behavior on devices.

## 3. User experience

### First use and connections

Opening the extension shows Apple and Google connection options. Either can be used alone. Do not request Apple permission just because a Google-only user opens the product.

Apple means calendars available through the iPhone calendar database, including iCloud and local calendars. It is not a separate Sign in with Apple account flow. Device calendars can also include accounts from other services. Subtitle this option “Calendars on this iPhone.” Google means a direct authenticated Google Calendar connection.

Connecting Google opens the companion app for authorization if required. A connection started from browsing requests read permissions; one started from saving requests the complete read/write permission set. A person who connected for browsing can authorize saving later through the explicit reauthorization flow in section 7. Preserve the pending operation, show clear return-to-Messages instructions, and resume when the extension next activates. Do not depend on an automatic return to a particular conversation. If opening the app from the extension is unavailable, show manual setup instructions. Initial setup or a later permission upgrade may leave Messages; subsequent browsing and authorized saving should not.

### Sender flow

1. Open a person or group conversation and launch the extension.
2. Home shows up to five recent source calendars, newest first, with provider badge, calendar color, name, and account label, plus Search all connected calendars. Recency means use within this product, not activity detected in another calendar app.
3. Select a recent calendar, choose Apple/Google to browse calendars, or start Search all connected calendars without selecting a provider or calendar. Choosing an unconnected provider starts its setup flow; global search uses only connections already authorized.
4. For calendar browsing, search calendar names within connected or authorized accounts and select one. This is not public calendar discovery. The global search path skips this step.
5. Show events chronologically, with title, date/time, and location when available. Default range: today through the next 90 days, including events already in progress. Keep the search scope and date range visible and let the person choose past or future dates. Global results also show each event's calendar, provider and account.
6. Search event titles and locations across the chosen scope. Apply a consistent local text filter to fetched results; debounce input, cancel stale requests, and stream paginated results. Keep partial results usable while clearly showing calendars still loading or unavailable. Do not show a definitive no-results state until all accessible calendars in scope finish loading.
7. Selecting an event creates a share snapshot and immediately inserts its default card into the Messages compose field. An optional Details control before selection lets the sender inspect fields, omit location, or include a short note.
8. The sender reviews the visible draft and taps the normal Messages Send button. Insertion success must not be labeled “Sent.”

Default shared fields: title, start/end, all-day status, time zone, and location. Notes are off by default. Show a concise explanation of this near the event list. Never share attendees, organizer addresses, calendar/account names, booking codes from notes, attachments, or conferencing links by default.

A fresh selection produces a fresh share ID. Retrying a failed insertion reuses its original snapshot and ID. Selecting another event intentionally replaces the current extension draft; test actual compose behavior in the feasibility milestone.

### Search across connected calendars

Search all connected calendars uses every readable calendar available through authorized device access and the directly connected Google account. Offer optional provider/calendar filters without requiring them. The same date-range and title/location matching rules apply to single-calendar and global search. Changing the query, scope or range must prevent stale responses from overwriting current results.

Paginate each provider/calendar independently and merge results chronologically, using calendar and event identifiers for stable ordering and route-local deduplication. Fetch at most three Google calendar pages concurrently, reuse in-memory results for the same date interval, and honor rate limits. Preserve matches from other calendars if one fails; show which calendar could not be searched and a targeted retry. Do not request new permissions automatically when global search opens. List unconnected providers as optional setup choices outside the active search scope.

Use a status such as “Searching 3 of 8 calendars” until the scope completes. If any calendar fails, say “No matches in the calendars searched” instead of claiming there are no matches anywhere. A calendar visible through both device access and direct Google remains explicitly labeled unless a reliable identity mapping proves it is the same source; do not merge results by title/date alone.

### Recipient flow

1. Tap the event card to open a single receive-and-save screen in the extension.
2. Show title, dates, location, included note, and “Saves an independent copy.” The received snapshot is authoritative; do not fetch the sender's calendar. Show recent writable destination calendars directly below the details, with account and provider labels. Nothing is selected automatically.
3. Tap a recent destination, or expand All calendars in place to search writable calendars grouped by Apple/Google and account. If there are no recent destinations, show the expanded list immediately. Keep connection actions available for missing providers. Source and destination recents are tracked separately.
4. Show the chosen calendar and an enabled “Add to [calendar name]” button on this same screen. Until a valid destination is selected, Add is disabled with the prompt “Choose a calendar.” Optional Edit details controls expand in place for this copy's title, dates, location, note, availability and reminder. Edits never modify the received message or source event.
5. Save only after the recipient taps Add. Selecting a calendar never saves automatically. Disable repeated taps while saving and show progress in place; do not require a separate review or confirmation screen.
6. Replace the save controls with an inline confirmation naming the actual destination. Google success follows API confirmation. EventKit success means saved to the device calendar store; remote account sync may still be pending. Show recoverable errors on the same screen with the selected calendar and edits preserved when still valid.

After setup, the common receiving path is three taps: open card, select a recent calendar, and Add. Keep the Add control reachable while browsing destinations or expanding optional fields, including at large text sizes. If authorization requires leaving Messages, restore this screen and its pending state on return; require the final Add tap rather than saving automatically after consent.

The saved event keeps the shared title by default. Do not infer or prefix the sender's contact name. Availability defaults to Free when the destination supports it, with an editable Busy/Free choice. Do not copy the sender's alarms; default to no reminders and offer an optional reminder. Verify provider/device defaults do not silently reintroduce alerts.

“Added” is local recipient state. It must not change the card globally, notify the sender, or mark the event added for everyone in a group. Saving to another calendar requires another explicit destination selection.

### Screen inventory

| Screen | Main content and actions |
| --- | --- |
| Extension home | Recent source calendars; Search all connected calendars; Apple; Google; Settings |
| Calendar browser | Provider/account, calendar-name search, readable/writable indicators |
| Event browser and global search | Visible scope/date range, event search, provider/calendar filters, labeled results, partial-loading status, optional Details |
| Sender details | Exact shared fields, location toggle, opt-in note, Insert |
| Received event and save | Snapshot, independent-copy explanation, inline recent destinations and expandable calendar list, optional edits, Add; success/already-added/retry states stay on this screen |
| Companion app | Connect/disconnect Google, Apple permission status, setup/help |

Support compact and expanded Messages layouts, Dynamic Type, VoiceOver, dark mode, keyboard navigation where applicable, and meaningful loading/empty/error states. Do not rely on color alone to identify providers or calendars.

## 4. Event semantics and boundaries

- Support timed, all-day, multiday, and overnight events, including long travel blocks.
- Preserve timed-event instants and available source time-zone identifiers. Display the recipient's local time with source-zone context when different. Handle distinct start/end zones where supplied; EventKit may expose only one event time zone, so never invent a second one.
- Model all-day dates separately from timestamps. Store start date and exclusive end date; display the last included day to the user. An October 10–12 trip is encoded with end date October 13. Never UTC-shift all-day dates.
- A recurring event appears as dated occurrences. Mark “This occurrence only”; the copy has no recurrence rule.
- Specialized provider items may be copied as ordinary events only if their dates and visible fields are representable. Do not reproduce out-of-office auto-decline behavior, working-location semantics, or conference configuration. Tasks/reminders are outside v1.
- Readable shared calendars may be sources. Only writable calendars may be destinations. Busy-only/redacted records and canceled events cannot be shared.
- A source edit after insertion does not update the draft or sent card. Reselect the event to create a new snapshot. Deleting a source event does not invalidate an existing card.
- Display empty titles as “Untitled event” and permit correction. Reject invalid dates or unsupported payloads with a readable error.

## 5. Architecture

Use Swift with SwiftUI views hosted inside `MSMessagesAppViewController`. Share domain models and provider logic through a local Swift package. Use async/await, cancelable reads, and main-actor UI updates. Pin compatible dependency versions at implementation time.

| Component | Responsibility |
| --- | --- |
| iOS app target | Account authorization, permissions/setup, help, connection management |
| Messages extension target | Browse, select, insert cards, decode received cards, select destination, save |
| CalendarDomain | Provider-independent calendar, event, snapshot, date and error models |
| EventKitProvider | Device calendar reads and writes |
| GoogleCalendarProvider | Direct Calendar REST calls and pagination |
| EventSearchCoordinator | Search one/all authorized calendars, limit concurrent reads, merge results, cancel stale work and report partial failures |
| AuthorizationStore | Credentials in shared Keychain; refresh and reconnect states |
| SharedStore | App Group storage for recents, operation journal, pending setup and import receipts |
| MessageCodec | Versioned payload validation, encoding, decoding and size checks |

Provider interface: list calendars for a read/write purpose; list events in a calendar and interval with a cursor; load an event occurrence; create a copy with an operation key; reconcile an uncertain creation. Use an opaque provider-specific cursor. Provider IDs stay local and never enter a share payload.

Do not run a service that monitors calendars. No background source synchronization, conversation scraping, contact upload, or app-specific social account is needed.

## 6. Apple calendar integration

Use EventKit and request full event access only when the person chooses Apple. Browsing existing events and providing a custom picker for real calendars require access beyond write-only. Include `NSCalendarsFullAccessUsageDescription` in the appropriate targets. Apple's write-only mode exposes a virtual calendar rather than a usable list of real destinations [S3].

Suggested permission explanation: “Choose calendar events to share and select where to save events you receive.” Handle not-determined, full-access, write-only, denied, and restricted states explicitly. Recheck authorization on activation; do not assume app and extension permission behavior without device testing.

Fetch bounded date windows off the UI thread. Use EventKit calendar identifiers locally and `allowsContentModifications` for destinations; revalidate before saving. Observe store changes and invalidate stale selections. Create a fresh `EKEvent`; never mutate a source event or copy its attendees.

A Google calendar may appear both through EventKit and the direct Google connector. Label its access route. Do not merge calendars by name or guessed account identity. Prefer the direct Google route when a reliable mapping is available; otherwise keep explicitly labeled entries. Receipt-based duplicate prevention across unmatched routes is a documented limitation.

## 7. Direct Google integration

Use AppAuth for native OAuth authorization-code flow with PKCE in the companion app, an iOS OAuth client, and an external system authentication session. Do not embed a client secret. Link the extension only to extension-safe token/state code such as AppAuthCore; keep authorization presentation in the companion app. Verify this exact package split and credential lifecycle in M0 [S7, S8, S10, S12].

Use explicit authorization requests with the complete required scope set. Google's generic native OAuth documentation does not support assuming incremental authorization; this AppAuth design must not depend on `include_granted_scopes` or automatic merging of old and new grants [S7]. A later write request is a new interactive authorization for the full read/write set, not a token refresh or an undocumented SDK scope-add operation.

| Entry point | Complete Calendar scope set requested | Behavior |
| --- | --- | --- |
| Connect from browsing | `calendar.calendarlist.readonly` and `calendar.events.readonly` | Enable calendar/event discovery after verifying both granted capabilities |
| Connect from receiving/saving | `calendar.calendarlist.readonly` and `calendar.events` | Authorize browsing and saving in the initial connection |
| Existing read-only connection attempts Add | `calendar.calendarlist.readonly` and `calendar.events` | Explain the extra access, perform a new full-set authorization, then return to the pending receive screen |

The table abbreviates the common `https://www.googleapis.com/auth/` prefix. The event-write scope also covers event reads and permits editing/deletion beyond the product's create-only UI; explain that consent accurately. Do not request broad calendar-management or calendar-sharing scopes [S4].

Check the actually granted scopes and Google account identity, not just whether authorization returned a token. Never combine credentials belonging to different accounts. If a different account is selected, treat it as an account switch and require a new destination selection. For a canceled, denied or insufficient same-account upgrade, retain any still-valid prior browsing connection and pending receive state; do not replace it with an incomplete credential set. If prior access has been revoked, show reconnect rather than promising browsing remains available.

Keep durable authorization state in a shared Keychain access group. App Group files contain no access or refresh tokens. Serialize refresh operations across processes and persist refreshed state atomically. M0 must prove that both the initial and upgraded connection can obtain a fresh access token after expiry and a cold launch; these are developer tests, not delays imposed on user setup. An upgrade cannot rely solely on a temporary access token: verify that its retained refresh credentials also support the newly granted capability. Refreshes use the established grant and cannot add permissions. Normal token expiry should refresh silently in the extension; revoked grants or an unrecoverable refresh require explicit reconnection. If the chosen package configuration cannot refresh from the extension, treat that as an M0 blocker to resolve rather than routing every routine save through the companion app.

Use CalendarList.list for connected calendars, Events.list for dated occurrences, and Events.insert for copies. Handle page tokens. Expand recurrence with `singleEvents=true`, order by start time, filter canceled records, and use a bounded interval [S5, S6]. Check access role/capability for each destination and handle server-side permission changes.

Create a normal event with only approved snapshot fields and recipient edits. Do not copy attendees, organizer, source ID, source iCalUID, recurrence, conference data, or attachments. Use a new destination ID and private import marker. Set reminders explicitly. The recipient never needs permission to the sender's original calendar [S9].

Google saves require network access. Do not silently queue writes for later in v1. After successful authorization, restore the selected destination if it remains valid, but wait for an explicit Add tap before writing. Disconnect clears credentials and account-scoped cached data; already-created calendar events remain intact.

## 8. Message transport and data model

Use `MSMessage` with `MSMessageTemplateLayout` for the preview and `MSConversation.insert` for the compose field [S1]. Use a fresh message for each share; do not use a collaborative `MSSession` to publish per-recipient save status.

Transmit a self-contained snapshot in `MSMessage.url`, not a link to the private source event. Apple documents a 5,000-character maximum and HTTP/HTTPS/data schemes [S2]. Proposed format: an owned HTTPS help URL with a fragment carrying base64url-encoded UTF-8 JSON. The exact fragment round trip is a feasibility gate.

The complete encoded URL must fit a conservative 4,500-character application limit. Use no compression in v1. Never silently truncate titles, dates, or location. If optional notes make a card too large, ask the sender to shorten or omit them. If required content is too large, block insertion with an explanation.

Example all-day payload:

```json
{
  "schemaVersion": 1,
  "shareId": "8e9d449a-210f-499b-8b95-ea9f8c360ecc",
  "createdAt": "2026-10-04T03:00:00Z",
  "event": {
    "title": "Trip to Chicago",
    "time": {
      "kind": "allDay",
      "startDate": "2026-10-10",
      "endDateExclusive": "2026-10-13"
    },
    "location": "Chicago",
    "note": null,
    "isSingleOccurrence": false
  }
}
```

For timed events, `time` contains `kind: "timed"`, `startInstant` and `endInstant` as RFC3339 timestamps, and optional `startTimeZone`/`endTimeZone` IANA names. No all-day fields are allowed in this variant. Copy mapping must preserve instants even if one destination cannot retain both zone labels.

Local-only records:

- `CalendarRef`: provider, account key, calendar ID, display name, color, write capability.
- `RecentCalendar`: CalendarRef plus use time and source/destination purpose.
- `ImportOperation`: operation ID, share ID, payload hash, destination reference, frozen recipient edits, attempt state and optional provider result ID.
- `ImportReceipt`: share ID, destination reference, payload hash, saved event ID and completion time.

Validate scheme, expected host/path, schema version, types, string lengths, dates, enum values, and encoded/decoded size before displaying or saving. Unknown schema versions show an update-app message. Render notes as plain text. Base64 is encoding, not encryption; do not claim the payload is authenticated or end-to-end encrypted by this app. Do not trust payload-supplied identities.

The static HTTPS page provides installation/help information without displaying event content. No analytics or scripts reading the fragment, no automatic URL fetching from payload fields, and no request logging of message payloads. Installation has no guaranteed deferred deep link: tell recipients to reopen the original message after setup. Choose a real owned domain and App Store URL before release; placeholders must not ship.

## 9. Reliable saves and duplicate handling

Deduplicate the same share into the same destination on the current installation. Do not deduplicate solely by matching title and date: distinct events can legitimately match. Do not promise global deduplication across devices, reinstalls, independent reshares, or unmatched provider aliases.

Before writing, persist an operation with its immutable payload/edits, destination and ID. Use cross-process coordination so app/extension retries cannot issue concurrent writes. An in-process Swift actor alone does not coordinate separate processes.

For Google, generate a valid deterministic event ID for that operation, following Google's allowed ID format, and include a private import marker. On timeout or conflict, retrieve and verify the event by that ID before retrying. Never generate a fresh ID for an uncertain retry. If recipient edits change after an uncertain attempt, reconcile the original operation before starting another.

For EventKit, save a local receipt and a namespaced operation marker in the new event's notes, alongside any user note. After a crash or uncertain result, reconcile using the receipt and a bounded event search for the marker. If the outcome cannot be determined, say so and ask the person to check their calendar before explicitly retrying. EventKit does not provide an app-defined transactional idempotency key; do not promise exactly-once creation.

If a receipt resolves to a live event, show “Already added to [calendar].” If it is verified deleted, offer Add again. If access has disappeared, show an unverifiable status rather than guessing. Preserve existing calendar events when clearing local history.

## 10. Failure behavior

| Condition | Required behavior |
| --- | --- |
| No account/permission | Connect or explain settings; preserve pending receive snapshot |
| Google disconnected/expired grant | Reconnect; restore the pending operation after return |
| No matching events | Show current scope, query and date range; offer range adjustment; distinguish complete searches from partial failures |
| One calendar fails during global search | Keep matches from other calendars, identify the unavailable calendar and offer a targeted retry |
| Google write authorization canceled/insufficient | Preserve pending receive state and any still-valid browsing grant; explain missing permission and allow retry or another provider |
| No writable destination | Explain and let the person choose/connect another provider |
| Network error before Google write | Keep the combined receive-and-save screen and edits; retry only on user action |
| Timeout after write began | Reconcile before retry; never label it definitely failed prematurely |
| Rate limit/server error | Bounded backoff respecting Retry-After; visible retry state |
| Calendar removed or permission changed | Clear selection; require a new explicit choice |
| Malformed/unsupported message | Explain without crashing or writing any event |
| Sender event changed/deleted | Existing snapshot stays usable and unchanged |
| Extension suspended/terminated | Persist only necessary pending state and resume safely |
| Recipient lacks app | Readable card; platform installation behavior verified on devices |

No event contents, account addresses, access tokens, or full message URLs in logs or analytics. Cache only what is needed: event search results in memory, minimal pending state on disk, and protected local receipts. Clear canceled pending drafts and disconnected-account caches. Explain that sent messages and already-created copies cannot be revoked by disconnecting.

## 11. Implementation milestones for Codex

### M0 Prove the platform paths

Create a minimal signed containing app and Messages extension. Use real iPhones and a real Google test account to prove:

1. Select a sample event, insert its card into the compose field, manually send it, tap it on another device, and decode the complete payload. Include group chats and a near-limit Unicode payload.
2. Verify Apple full-access requests, calendar listing, and event creation from the actual extension context. Record whether the app and extension require separate prompts.
3. Prove both Google entry paths: read-only connection followed by a full-set write reauthorization, and initial read/write connection from receiving. Test canceled, denied and partial grants, plus account switching. List and write through the extension after initial access-token expiry and a cold launch; verify AppAuth/AppAuthCore linkage, shared Keychain entitlements, refresh and revoked grants. Record actual granted scopes without logging credentials.
4. Verify opening setup from Messages and restoring the combined receive-and-save screen after manual return, preserving edits and any still-valid destination. Confirm consent never triggers an automatic calendar write.
5. Observe uninstalled-recipient behavior and reopening the message after installation. Verify the HTTPS fragment survives message delivery and supported forwarding paths.

Deliver a short feasibility report with observed OS versions and results. Do not claim these behaviors are tested merely because the project compiles. If any core path fails, isolate the blocker and propose the smallest user-visible adjustment before proceeding.

### M1 Domain and device calendars

Implement normalized models, date mapping, validated codec, EventKit provider, calendar/event browsing, the search coordinator, permissions and recents. Prove multi-calendar search first with device calendars and provider fixtures. Use fixtures for all-day, overnight, time-zone and recurring-instance cases.

### M2 Direct Google

Implement the explicit full-set authorization and reauthorization paths, durable credential refresh, calendar listing, paginated occurrence reads, writes and reconciliation. Connect Google reads to global search with bounded concurrency, partial results and per-calendar retries. Validate with Google sync disabled in iPhone settings.

### M3 Complete the conversation flow

Implement insertion and preview, plus the single receive-and-save screen with inline destination selection, optional edits and inline result states. Validate the three-tap path for a connected recipient using a recent calendar. Implement operation journal and provider-specific duplicate handling.

### M4 Release readiness

Run the acceptance matrix, accessibility checks, release builds, privacy disclosures, current dependency review, Google consent/verification setup, and TestFlight distribution. Test with at least two people. Record limitations and exact external setup steps in README.

## 12. Acceptance criteria

| ID | Test and expected result |
| --- | --- |
| A1 | With Apple and Google connected, home shows recent source calendars from both, provider/calendar browsing and Search all connected calendars |
| A2 | Selecting an event populates a draft card; no message is sent until the user presses Send |
| A3 | Google-only sender and recipient complete the flow without enabling Google in Apple Calendar |
| A4 | Test Apple→Apple, Apple→Google, Google→Apple, and Google→Google; each produces an accurate independent copy |
| A5 | Every receive starts with no destination selected, even after prior saves; recent destinations remain one-tap choices |
| A6 | Two group recipients save the same card into different calendars; neither changes the other's state |
| A7 | Saving creates no invitation, RSVP, attendee email or source modification |
| A8 | October 10–12 all-day trip retains all three dates across recipient time zones; DST and overnight timed cases retain instants |
| A9 | A recurring occurrence becomes exactly one nonrecurring event; no additional instances appear |
| A10 | Repeated Add taps, reopening a card and retrying a timed-out Google request do not create duplicate copies in the same destination |
| A11 | Termination around EventKit save triggers reconciliation or an honest uncertain-state prompt, not blind retry |
| A12 | Permission denial/revocation, read-only calendars, offline Google, deleted calendars and expired tokens have recoverable states |
| A13 | Notes and meeting/attendee details are excluded by default; only opted-in fields reach the recipient |
| A14 | Invalid JSON, oversized payload, unknown schema, Unicode titles and malformed dates cannot crash the extension or cause a write |
| A15 | Source edit/deletion after sending does not change received cards or saved copies |
| A16 | Disconnecting clears credentials; it does not delete saved calendar events |
| A17 | Device and direct-provider routes are distinguishable when the same Google calendar is visible through both |
| A18 | Accessibility labels, large text, compact/expanded layout and dark mode remain usable |
| A19 | From a received card, a connected recipient can tap a recent destination and Add on the same screen; no separate save-review screen or automatic write occurs |
| A20 | Global search returns matching title/location events from Apple and Google without first choosing a calendar; each result identifies its calendar/provider/account and the date range stays visible |
| A21 | Global search handles pagination, one failed calendar, rate limits and a changed query; results remain usable, incomplete coverage is visible and stale results never overwrite the current search |
| A22 | Both initial Google read/write authorization and read-only-to-read/write full-set reauthorization yield the required verified capabilities; cancellation/partial grants preserve any still-valid prior browsing state |
| A23 | Google credentials refresh in the extension after expiry and cold launch; authorization restoration never saves automatically, and changing accounts clears the old destination |

Unit-test codec bounds, date conversion, excluded-field mapping, operation-state transitions, search pagination/partial failure/cancellation and granted-scope capability checks. Integration-test real provider behavior, particularly authorization upgrades, refresh and uncertain writes. Simulator tests do not replace the two-device Messages checks.

## 13. External setup and non-goals

Development requires macOS with Xcode for Apple builds and device testing, Apple signing configuration, App Group and Keychain entitlements, and a Google Cloud project with Calendar API enabled and iOS OAuth client configured. A public launch may require Google OAuth verification; prepare consent, support and privacy URLs and test-user configuration early [S4]. App Store identifiers, domain ownership and signing credentials are developer-supplied configuration, never values for Codex to invent.

Out of scope: automatic updates, shared-calendar subscriptions, invitations/RSVPs, whole-series sharing, batch event sharing, creating source events, natural-language event generation, Android/SMS/RCS support, web calendar writes, multiple directly connected Google accounts, and guaranteed cross-device duplicate prevention. Calendar creation itself is also outside v1; choose an existing writable calendar.

## 14. Suggested first Codex prompt

> Read this specification and inspect the repository before making changes. Implement M0 first using a native iOS app, Messages extension and shared Swift package. Preserve the confirmed product requirements. Produce a buildable project, clear external configuration instructions, and a feasibility checklist separating device-verified results from unverified assumptions. Do not add a backend, invitations, automatic sync, or a preselected destination calendar. Prove the specified Google full-set authorization/reauthorization paths, extension token refresh and real two-device Messages payload handling before implementing the complete UI. Later milestones must include global event search and the single receive-and-save screen. If this environment cannot run Xcode or device tests, implement what it can and clearly document the remaining execution steps without claiming they passed.

## 15. Technical references

Reviewed October 3, 2026. These sources establish API capabilities; the product choices and feasibility gates above are design recommendations.

- S1 — Apple, MSConversation insertion: https://developer.apple.com/documentation/messages/msconversation
- S2 — Apple, MSMessage URL and its constraints: https://developer.apple.com/documentation/messages/msmessage/url
- S3 — Apple, EventKit permissions and event store: https://developer.apple.com/documentation/eventkit/accessing-the-event-store
- S4 — Google, Calendar API authorization scopes and verification: https://developers.google.com/workspace/calendar/api/auth
- S5 — Google, CalendarList.list: https://developers.google.com/workspace/calendar/api/v3/reference/calendarList/list
- S6 — Google, Events.list: https://developers.google.com/workspace/calendar/api/v3/reference/events/list
- S7 — Google, native OAuth: https://developers.google.com/identity/protocols/oauth2/native-app
- S8 — OpenID Foundation, AppAuth for iOS: https://github.com/openid/AppAuth-iOS
- S9 — Google, Events.insert: https://developers.google.com/workspace/calendar/api/v3/reference/events/insert
- S10 — Apple, app extension shared code and containers: https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html
- S11 — Apple, iMessage apps and distribution: https://developer.apple.com/imessage/
- S12 — OpenID Foundation, AppAuth and AppAuthCore package products: https://github.com/openid/AppAuth-iOS/blob/master/Package.swift
