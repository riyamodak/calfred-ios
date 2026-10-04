# Apple calendar M0 probe

Status: implemented as a development probe; **no physical-device result has been recorded**. A successful simulator or unsigned build does not prove the extension permission or save path.

`EventKitProbe` requests full event access only through an explicit action. Both targets need `NSCalendarsFullAccessUsageDescription`. Write-only access is shown as insufficient because the custom destination picker must enumerate real calendars. Calendar references remain local and are revalidated by calendar ID, source ID and write capability immediately before a save.

The probe creates a fresh ordinary `EKEvent` from approved snapshot fields and recipient edits. It sets no recurrence, attendees, source identifier, URL or alarms. It requests Free only where the calendar reports support, then reads back availability and alarms to help identify provider/device defaults. Saving confirms the device store accepted the copy; remote synchronization is separate. All-day dates are materialized in the device's local calendar zone, with an exclusive end. Distinct timed start/end zone labels cannot both be stored in EventKit's single time-zone field; their instants are preserved.

The containing app and extension should recheck authorization on activation and refresh calendar choices on `EKEventStoreChanged`. There is no cached default destination. An unavailable destination requires a new explicit choice. The M0 probe does not implement M3's durable import journal or EventKit uncertain-save reconciliation. Do not treat an ambiguous save error as proof that no event was created or automatically retry it.

## Physical-device checklist

Use a signed build on the actual test iPhones. Record device model, exact iOS version/build, app build, date, and observed result in the feasibility report. Use expendable test events and calendars; record no private event contents or account addresses in shared reports.

- [ ] On a fresh install, open Messages without choosing Apple: no Apple prompt appears.
- [ ] Request Apple access from the **extension** and record the actual prompt and resulting state.
- [ ] Open the companion app and record whether a separate prompt is required; repeat starting in the companion app on a clean permission state. Do not infer shared permission from simulator behavior.
- [ ] Exercise not-determined, full-access, write-only, denied and restricted states where the OS/device policy permits them. Record any state that cannot be arranged as untested.
- [ ] List readable calendars, including a readable read-only calendar when available; verify only writable calendars are offered for saving. Confirm account and Apple/device route labels distinguish similarly named calendars.
- [ ] Receive a sample card, edit title/location/note, choose a destination and tap Add. Confirm the copy exists in the chosen device calendar and uses the edits. Selecting a destination or granting access alone must not create an event.
- [ ] Verify the saved event is ordinary, independent, nonrecurring, has no attendees or invitation, and has no reminder. Read back Free when supported and inspect the remote calendar after sync for alerts silently introduced later.
- [ ] Test an all-day October 10–12 sample with end date October 13 on recipients in different zones; confirm the same three dates. Test overnight timed samples and distinct start/end zone labels; confirm the instants.
- [ ] Remove a calendar, make it read-only, or revoke access while a destination is selected. On return, observe refreshed authorization/destinations and require a valid new selection rather than falling back to a default.
- [ ] Save while offline to a device-backed remote calendar and distinguish local store success from subsequent account sync. Record synchronization behavior without promising immediate remote delivery.
- [ ] Interrupt the extension near a save only in a disposable test calendar. Record uncertainty honestly and inspect the calendar manually before any explicit retry; durable reconciliation belongs to M3.

Apple reference: [Accessing the event store](https://developer.apple.com/documentation/eventkit/accessing-the-event-store). API mapping was checked against the installed Xcode SDK headers; the checklist above still requires physical-device observations.
