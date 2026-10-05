# Google M0 probe

Implementation is a feasibility harness. On October 5, the user reported successful Google
browsing sign-in followed by the saving-access upgrade on their physical iPhone. The user subsequently confirmed that Google calendars are visibly listed after the UI fix.
Google writes, actual scopes, and extension refresh after expiry remain unverified.

Both targets now show a Google inventory outside the setup disclosure, with calendar names,
read-only/writable labels, and loading/empty/error states. The extension reloads a connected
account on activation; **List Google calendars** and **Force refresh + list in extension**
also populate the inventory. In a receive, writable calendars appear in **Choose a calendar**;
the Google section keeps its count and controls. Add remains disabled without verified saving
access. No event is written by listing or consent. The user confirmed the visible inventory; empty/error states and forced-refresh results remain unverified.

Complete the device result table in the main feasibility report before considering M0 proved.

## Implemented

- [x] Containing-app AppAuth authorization-code presentation with PKCE; no client secret.
- [x] Complete read-only and read/write scope sets on every interactive request. An upgrade
  is another authorization flow, with no `include_granted_scopes` or old/new grant merging.
- [x] `openid` accompanies Calendar scopes so authenticated Google UserInfo can supply a
  stable `sub`. Account email/profile scopes are not requested.
- [x] Inspect actual token-response `scope`, including the response to a forced refresh,
  before accepting a connection. Requested scopes and `OIDAuthState.scope` fallbacks are
  not proof of consent. Missing scopes fail closed.
- [x] Require the candidate's own refresh token, force a real refresh immediately, check
  refreshed capabilities and account identity, then replace shared Keychain state. This
  rejects temporary-access-only upgrades. It does not splice the old refresh token into
  the candidate. A failed/canceled/partial upgrade retains prior local credentials and
  attempts a refresh of the old browsing connection to detect revocation.
- [x] Shared Keychain uses one atomic item and `AfterFirstUnlockThisDeviceOnly`; App Group
  storage contains only the refresh lock, never access/refresh tokens or token archives.
- [x] Cross-process file lock covers Keychain load, refresh and save. Each operation loads
  the latest state; an in-memory actor is not the only coordination mechanism.
- [x] Extension-safe `AppAuthCore` normal expiry refresh and an explicit force-refresh
  diagnostic. Grant invalidation persists a reconnect state; transient network errors
  and token-endpoint rate limits retain credentials. A persisted pending-identity flag
  prevents using a refreshed token after a temporary UserInfo failure until verification
  succeeds. A late rejection of an old token cannot invalidate its newer replacement.
- [x] Paginated CalendarList listing, route-labeled calendars, writable-role filtering,
  account identity tied to the token used, and fresh destination revalidation before POST.
- [x] Explicit sample-event insertion uses a new operation-derived event ID and private
  marker, ordinary event type, Free availability, and reminders explicitly disabled.
  Only snapshot title, dates/zones, location and opted-in note are mapped. No attendee,
  organizer, recurrence, source ID, iCalUID, attachment or conference field is copied.
- [x] No automatic POST retry. A network interruption, conflict or ambiguous response
  becomes an uncertain result; the M0 write guard prohibits blind retry. Full Google
  reconciliation and general browsing belong to later milestones.

## Configuration supplied by the developer

- [ ] In Google Cloud, enable the Calendar API and configure the OAuth consent screen,
  audience, test users, support/privacy URLs and requested Calendar scopes.
- [ ] Create an **iOS** OAuth client for the containing app's actual bundle ID. Configure
  its client ID and matching reversed-client-ID redirect scheme in local Xcode settings.
  There is no embedded client secret and no web OAuth client in this project.
- [ ] Configure the same signed Keychain access group and App Group for the app and
  Messages extension, with the correct Apple team/application identifier prefix.
- [ ] Use a real Google test account with an existing writable calendar. Keep Google
  calendar sync disabled in iPhone settings to prove direct Google access.
- [ ] Explain write consent accurately: Google's event-write scope permits reading,
  creating, editing and deleting calendar events even though this harness only creates
  explicitly requested copies. It does not request calendar-management/sharing scopes.

## Physical-device procedure

1. Start disconnected. In Messages, start browsing setup, manually complete authorization
   in the containing app, return to the original conversation and list Google calendars.
   Record the displayed granted scopes, refresh verification time, iOS version and result.
   Do not record tokens, account addresses, full URLs, or event contents in logs.
2. Receive a sample, edit it and explicitly choose a destination. Trigger save setup and
   authorize the complete write set. On return, verify edits remain, destination is kept
   only when still valid, and no event exists until Add is tapped.
3. Repeat step 2 with cancellation, denial and partial consent. Verify pending state
   remains and any still-valid browsing access still works. If access was revoked, the UI
   must require reconnect. A partial candidate must never replace a working credential.
4. Select a different Google account during full-set authorization. Verify destination
   selection is cleared on return and the next list belongs to the new account.
5. Disconnect, then connect from receiving with read/write from the beginning. Verify the
   refreshed token supports both list and insert and no write occurs during consent.
6. For **both** successful paths, use the force-refresh diagnostic from the extension,
   then separately wait until the displayed access-token expiry has passed, terminate
   both app and extension, cold-launch Messages, list and explicitly save. Record each
   result. A forced refresh or simulator build alone does not prove expiry/cold-launch.
7. Revoke access in Google's account settings. Force-refresh/cold-launch and verify
   reconnect is required. Restore access, then test offline listing and an interrupted
   save; the latter must remain uncertain/locked until manually checked.
8. Inspect saved events in Google Calendar: correct destination and times, ordinary
   independent copy, no guests/invitations, no recurrence, Free and no notifications.
   Repeat with a calendar whose defaults include reminders to check override behavior.

## Dependency and protocol evidence

The project pins AppAuth **1.7.6** for the available Xcode 15.0.1 / Swift 5.9 toolchain.
Its [tagged package manifest](https://github.com/openid/AppAuth-iOS/blob/1.7.6/Package.swift)
uses Swift tools 5.3 and exposes separate `AppAuthCore` and `AppAuth` products. Only the
containing app links presentation code. The
[tagged state implementation](https://github.com/openid/AppAuth-iOS/blob/1.7.6/Sources/AppAuthCore/OIDAuthState.m)
provides refresh with `performAction` and `setNeedsTokenRefresh`. Linkage/build validation
and signed-device validation are separate checks; record the latter rather than inferring it.

Google documents [complete native authorization, actual granted scopes and refresh responses](https://developers.google.com/identity/protocols/oauth2/native-app),
[Calendar scope meanings](https://developers.google.com/workspace/calendar/api/auth),
[CalendarList pagination and roles](https://developers.google.com/workspace/calendar/api/v3/reference/calendarList/list),
and [event insertion fields](https://developers.google.com/workspace/calendar/api/v3/reference/events/insert).
These references support the implementation choices; they are not observed device results.
