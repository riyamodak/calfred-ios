# Calendar Share — M0

Native iOS 17+ feasibility harness for the [implementation spec](imessage-calendar-sharing-spec.md). The repository began with only that spec. M0 code is implemented; **the physical-device feasibility gates are still pending**. No Apple Developer account, Google Cloud account, OAuth login, or signing identity was configured by this task.

Open **`CalendarShare.xcodeproj`**, select the **CalendarShare** scheme, and build. The containing SwiftUI app embeds `CalendarShareMessages`, a SwiftUI interface hosted by `MSMessagesAppViewController`. Shared Swift code lives in `Packages/CalendarShareKit`. AppAuth is pinned to **1.7.6**; the app links `AppAuth`, while the extension links only the shared targets and `AppAuthCore`.

## What M0 contains

- Synthetic all-day, timed/DST, and near-limit Unicode cards; draft insertion uses the normal Messages Send button. Retrying an insertion reuses its snapshot. Sender/receiver diagnostics show share ID, URL length, and SHA-256 for comparison without logging the payload.
- Explicit Apple full-access and calendar-list probes, plus fresh independent-copy creation from the extension.
- Explicit Google browse-only, initial read/write, and full-set reauthorization in the companion. Actual scopes and account identity are checked before and after refreshing a new grant. The extension has calendar-list, silent expiry refresh, force-refresh, and explicit copy-create probes.
- A single receive screen with no default destination, inline title/location/note edits and Add. Shared pending state survives setup; the selected destination is revalidated on return. An unavailable calendar check preserves edits and keeps Add disabled. Consent never triggers a calendar write.
- Shared Keychain credentials, App Group pending state, and OS file locks. A persisted attempted-write flag blocks a repeat Add for that pending M0 probe, including after an uncertain result.

This is a one-pending-receive-slot development harness. Full source browsing/search, recents, date-edit controls, import receipts, automatic reconciliation, production duplicate prevention, and release readiness are M1–M4. Clearing pending state or reopening older cards can permit another copy; inspect the test calendar first. No backend or calendar monitoring is included.

## Your configuration checklist

1. Copy `Configuration/Local.xcconfig.example` to `Configuration/Local.xcconfig` (ignored by Git). Replace every example value. `Base.xcconfig` defaults deliberately permit an unsigned build but block unconfigured message transport/shared storage at runtime. Keep the `https:/$()/` syntax because xcconfig interprets `//` as a comment.
2. **Apple Developer/signing:** supply your team and register a containing app ID and a Messages extension ID prefixed by the containing ID. Register one App Group and enable it for both targets. Use the same shared Keychain group for both, with the real application-identifier prefix. The entitlement expands `$(AppIdentifierPrefix)$(KEYCHAIN_GROUP_SUFFIX)`; do not assume a transferred app's prefix equals its team ID. Select automatic signing/profiles that authorize both capabilities. This repository cannot invent these identifiers or profiles.
3. **Google Cloud:** enable Google Calendar API, configure consent/audience/support/privacy URLs and test users, and create an **iOS** OAuth client whose bundle ID exactly matches the containing app. Set the client ID and reversed client ID URL scheme. The redirect is `<reversed-client-ID>:/oauthredirect`. No client secret is used. Requests include `openid` plus the complete Calendar scope set described in [Google M0](docs/GOOGLE-M0.md).
4. **Owned HTTPS URL:** set `MESSAGE_BASE_URL` to a real HTTPS help URL you control, with a stable path and no query/fragment. Both devices must use the same URL configuration. Host a script-free installation/help page; `Configuration/help-page.html` is an unpublished template. Supply your actual install channel/App Store URL yourself. Do not add fragment-reading scripts or analytics. No website is deployed by this task.
5. **Physical devices:** enable Developer Mode as needed, trust the development machine, register/provision two real iPhones, and install the same signed build on both. Use real iMessage accounts/conversations and disposable existing writable calendars. Keep Google sync disabled in iPhone Settings for the direct-Google checks. Enable Calendar Share in the Messages app list.
6. Run the [M0 feasibility matrix](docs/M0-FEASIBILITY.md), including group conversations, manual return after setup, expiry/cold launch, revoked/partial grants, forwarding, and uninstalled recipients. Record OS/build versions and actual observations. M0 is not proved by compilation or the simulator launch check.

Both targets include `NSCalendarsFullAccessUsageDescription`; opening the app or extension does not request Apple access. Authorization UI stays in the companion. If `NSExtensionContext.open` cannot open setup, the extension provides manual Home Screen setup instructions and preserves the pending receive. It never promises a return to a particular conversation.

## Build and local checks

This session used Xcode 15.0.1 (15A507), Swift 5.9, and the iOS 17.0 SDK/runtime. Use an appropriate current Xcode to test current physical iPhones; current shipping iOS is not validated here.

```sh
swift test --package-path Packages/CalendarShareKit
xcodebuild -project CalendarShare.xcodeproj -scheme CalendarShare \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/calfred-derived CODE_SIGNING_ALLOWED=NO build
xcodebuild -project CalendarShare.xcodeproj -scheme CalendarShare \
  -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/calfred-device-derived CODE_SIGNING_ALLOWED=NO build
```

The last command compiles device binaries without signing; it does not install or run them on an iPhone. Network access is needed once to resolve AppAuth. The committed `Package.resolved` files pin the resolved revision. AppAuth 1.7.6 emits legacy API deprecation warnings in its presentation implementation; dependency modernization/release review remains later work.

The Xcode project and Info.plists are checked in. If adding/removing Swift files, run `python3 scripts/generate-project.py` to regenerate their references; no XcodeGen or Ruby gems are required. Change build settings/Info.plist templates in that script, then regenerate. Keep private configuration in `Local.xcconfig`.

Implementation progress: [checklist](docs/IMPLEMENTATION-PLAN.md). Observed results and remaining gates: [feasibility report](docs/M0-FEASIBILITY.md). Detailed provider procedures: [Apple](docs/APPLE-M0.md), [Google](docs/GOOGLE-M0.md).
