# Apple calendar M0 probe

Status: the user reported full access granted in the companion and subsequent extension enumeration of **5 calendars, 3 writable**, with no second prompt on **iPhone 16 Pro / iOS 26.7**. On October 5, the user confirmed sample opening, editing controls, destination selection, and a successful save visible in Apple Calendar. Exact saved-field/date semantics, restart/setup restoration, and the reverse permission sequence remain untested. See the [device report](M0-FEASIBILITY.md).

After full access, the companion and extension home show calendar names, account labels, and whether each calendar can accept events. They reload on activation and offer **Refresh calendars**. Calendar enumeration works before Google, the HTTPS help URL, or App Group storage is configured. The user's October 5 screenshot confirms the updated extension inventory displays calendar names and read-only labels.

To test a write next, open **Open sample to test saving** in the extension, choose a writable calendar, and tap Add. This creates the sample “Trip to Chicago” for October 10–12, 2026. Shared App Group storage must be configured so the attempted-write guard can be saved; Google and the HTTPS help URL are unnecessary for this local save test. The collapsed **Send sample cards** controls are separate tests of actual Messages delivery, and require the owned HTTPS URL.

### If opening the sample only flashes “Working…”

The sample first persists its receive state in the shared App Group. Apple calendar permission does not grant access to that storage. The original UI showed storage errors only in **Test status**, below the initiating button. The updated UI also keeps the error beside **Open sample to test saving**; after a successful open it requests expanded presentation and scrolls to the received event. It never inserts this local sample into the Messages compose box.

1. In Xcode, select **CalendarShare**, open **Signing & Capabilities**, and add/select the group under **App Groups** using your team. Put its exact identifier in `APP_GROUP_IDENTIFIER` in `Configuration/Local.xcconfig`. Replace the `group.your.owned.identifier.CalendarShare` example.
2. Enable that same group for **CalendarShareMessages**. Both signed provisioning profiles must authorize it. The repository's shared entitlement file already references `$(APP_GROUP_IDENTIFIER)`. Resolve any capability/signing errors in Xcode; entering an identifier in a file alone does not provision the capability.
3. Rebuild and install the signed companion with its embedded extension. Reopen the extension and tap **Open sample to test saving**. Expect the received event and writable-calendar choices; nothing is saved until an explicit Add.
4. If it still fails, record the complete inline error. A custom identifier alone is not proof that the signed entitlement or storage write works on the phone.

Apple's [current capability table](https://developer.apple.com/help/account/reference/supported-capabilities-ios) lists App Groups for free Apple Developer accounts as well as paid memberships (checked October 5, 2026). Use Xcode's capability/signing workflow; paid enrollment is not assumed necessary here. Actual signed storage access remains a device test.

### If the error says “Configure URLs”

The original configuration initializer parsed the Google redirect and message help URLs even when the caller only needed Apple shared storage. A copied Google redirect placeholder contains underscores and is not a valid URL scheme; this could stop the sample before checking its App Group. This was a code bug, not a requirement to configure Google for Apple testing.

The updated code validates settings only when the corresponding feature uses them. Rebuild with the fix, leave Google/help placeholders for later, and retry the sample. If App Group access is unavailable, the error now identifies shared storage and the Xcode steps above. The user supplied the old “Configure URLs” error on October 5 after setting a custom group identifier, using a free account, then confirmed successful sample opening and saving after the fix.

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
