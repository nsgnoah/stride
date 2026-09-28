# Apple App Store audit — Stride

- **Date:** 2026-09-27, refreshed 2026-09-28 after adding widgets, reminders, and Health import
- **Project:** Stride (`co.nsgsolutions.Stride`) — iPhone app + watchOS app (`co.nsgsolutions.Stride.watchkitapp`), native SwiftUI, XcodeGen project, Xcode 27.0, deployment targets iOS 18 / watchOS 11.
- **Live Apple sources checked:** yes — [Upcoming requirements](https://developer.apple.com/news/upcoming-requirements/) and the [Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) were fetched on the audit date. Relevant items: Xcode 26+/iOS 26 SDK required for uploads since April 28 2026 (met: Xcode 27); updated age-rating questionnaire required since Jan 31 2026 (manual, below); required-reason API declarations (met: none used).

## Fixed

| # | Guideline | Change | Where |
|---|---|---|---|
| 1 | 5.1.1 / upload validation | Added a `PrivacyInfo.xcprivacy` to **both** targets and bundled it in each Resources phase. No tracking, no collected data types (everything stays on-device), no required-reason APIs (none are used — no UserDefaults, file timestamps, boot time, disk space, or keyboard APIs). | `Stride/PrivacyInfo.xcprivacy`, `StrideWatch/PrivacyInfo.xcprivacy`, `project.yml` |
| 2 | Export compliance | `ITSAppUsesNonExemptEncryption = false` in both Info.plists (the app uses no encryption beyond Apple frameworks). Removes the per-upload compliance question. | `project.yml` → both `Info.plist` |
| 3 | Build / 2.3 | The App Icon sets had no image at all (upload would fail). Generated a 1024×1024 opaque icon for iPhone and Watch. **It's a placeholder-quality mark — swap in real art before shipping.** | `Stride/Assets.xcassets/AppIcon.appiconset`, `StrideWatch/Assets.xcassets/AppIcon.appiconset` |
| 4 | 1.4.1 (health guidance) | Added a plain-language "not medical advice, check with a doctor" note in plan setup and Settings › About. | `Stride/Setup/PlanSetupView.swift`, `Stride/ContentView.swift` |
| 5 | 5.1.1(i) (privacy disclosure) | Added an in-app privacy statement in Settings › About: no account, no server, no analytics; runs saved to Health on-device. | `Stride/ContentView.swift` |
| 7 | 5.1.1 (HealthKit read on iPhone) | The iPhone's `NSHealthShareUsageDescription` is now backed by a real feature (Progress › Import runs from Health). Access is requested only from that button, never at launch; the foreground auto-import runs silently and returns nothing until she has granted it. | `Stride/HealthImporter.swift` |
| 8 | 5.1.1(ii) / 4.5.4 (notifications) | Morning reminders are opt-in from Settings, local only, and requested in context (no purpose string is required for `UNUserNotificationCenter`). Denial is handled with a pointer to iOS Settings. | `Stride/Reminders.swift`, `Stride/ContentView.swift` |
| 9 | Privacy manifest coverage | Widget extensions (iOS + watchOS) read the plan from the app group and use no required-reason APIs or tracking; they're covered by the app's manifest. App Group entitlement added to all four targets. | `project.yml` |
| 6 | 2.5.4 (crash on start) | Fixed a watchOS assertion crash when starting a run (`allowsBackgroundLocationUpdates` without a location background mode). Found during simulator testing, fixed in the previous commit. | `StrideWatch/WorkoutManager.swift` |

## Needs your decision

| # | Guideline | Risk | Recommended fix | Effort |
|---|---|---|---|---|
| 1 | 5.1.1(i) | A **Privacy Policy URL is required** in App Store Connect and Apple expects it reachable in-app. The app collects nothing off-device, but a policy page still has to exist. | Publish a one-page policy (e.g. `nsgsolutions.co/stride/privacy`) saying data stays on device / Health, then add a `Link` row under Settings › About. I did not invent a URL. | 15 min |
| 2 | 2.3 / 4.0 | The generated app icon is functional but generic. Reviewers don't reject for taste, but it's the first thing they and she will see. | Commission or design a real icon; drop the PNG into both `AppIcon.appiconset` folders. | your call |
| 3 | Distribution | Is this going on the App Store at all, or just to her phone? TestFlight (internal testers) or a direct Xcode install needs none of the manual items below and no review. | If it's only for her: skip App Store Connect entirely and install from Xcode; the audit fixes still make the build cleaner. | — |

## Manual (App Store Connect / outside the repo)

- [ ] **Privacy Policy URL** and **Support URL** on the app record (see decision #1).
- [ ] **Privacy nutrition label:** declare *Health & Fitness* and *Location* as **not collected** (used on-device only, never sent off device). Must match the (empty) `NSPrivacyCollectedDataTypes` in the manifests.
- [ ] **Age rating** questionnaire under the 2025/26 system (expected: 4+; answer "no" to medical/treatment info, "yes" only to general fitness).
- [ ] **App Review notes:** explain that pace coaching needs an Apple Watch with GPS and an outdoor run; mention the watch app can be exercised in-simulator via Free run. No login, no demo account needed.
- [ ] **Screenshots** for 6.9"/6.5" iPhone and 46mm/49mm Watch, showing real app screens (Today, Plan, Progress; watch coaching screen).
- [ ] **App name ≤ 30 chars / subtitle ≤ 30** — "Stride" is fine; check name availability in ASC (common word — you may need "Stride — Run Coach").
- [ ] **HealthKit:** in the App Store listing, describe how Health is used (Apple asks for this when the HealthKit entitlement is present).
- [ ] **EU DSA trader status** if you distribute in the EU (hobby apps can opt out of EU storefronts).
- [ ] **Signing:** the project is set to team `23FZ6AFC22`, automatic signing. Confirm the App ID and HealthKit capability are enabled in the developer portal (Xcode does this on first archive).

## Passed / N/A

| Item | Result | Evidence |
|---|---|---|
| Built with Xcode 26+ / iOS 26 SDK | Pass | Xcode 27.0 (27A266a) |
| Deployment target sane | Pass | iOS 18.0 / watchOS 11.0 |
| Launch screen | Pass | `UILaunchScreen: {}` in `project.yml` |
| Version / build | Pass | 0.1.0 (1) — bump to 1.0 before first submission |
| Bundle IDs not templates | Pass | `co.nsgsolutions.Stride`, `.watchkitapp` |
| Push entitlement | N/A | No push |
| Required-reason APIs | Pass | None used (grep of `Shared/`, `Stride/`, `StrideWatch/`) |
| Third-party SDK manifests | N/A | No third-party dependencies |
| HealthKit purpose strings | Pass | Specific strings in both targets (`project.yml` → Info.plist) + HealthKit entitlement on both |
| Location purpose string | Pass | Watch only, when-in-use, "Stride uses GPS to measure your distance and pace while you run." iPhone app doesn't use location and declares no key |
| Camera / photos / mic / contacts / etc. | N/A | Not used; no stray keys |
| Ask in context, degrade gracefully | Pass | HealthKit/location requested on watch launch (needed for the only feature); run still records and pace still works from HealthKit if location is denied; app never blocks on a permission |
| Always-location | N/A | When-in-use only |
| ATT / tracking | N/A | No ads, analytics, or identifiers; `NSPrivacyTracking = false` |
| Account creation / deletion | N/A | No accounts |
| Sign in with Apple | N/A | No third-party login |
| Payments / IAP / subscriptions | N/A | Nothing sold |
| Review prompt gating | N/A | No rating prompt |
| UGC / moderation | N/A | Nothing shared between users |
| Kids category | N/A | Not a kids app |
| Health claims | Pass | No diagnostic or measurement-accuracy claims; disclaimer added |
| Third-party AI disclosure | N/A | No AI/LLM calls |
| Placeholder / debug copy | Pass | Scanner found none; no "beta/test/TODO" strings in UI |
| Other-platform references | Pass | None |
| Minimum functionality | Pass | Native plan generator, charts, live watch coaching |
| Push notifications | N/A | Local reminders only, opt-in; no remote push |
| Apple trademarks | Pass | SF Symbols only |
| Private APIs | Pass | None |
| Downloaded code | N/A | None |
| Background modes | Pass | Watch: `workout-processing` only, backed by a real `HKWorkoutSession`. iPhone: none (widgets and Health import run in the foreground / WidgetKit's schedule) |
| ATS | Pass | No network calls at all; no `NSAllowsArbitraryLoads` |
| Deprecated APIs (`UIWebView`, etc.) | Pass | None |
| Offline / permission-denied behaviour | Pass | Fully offline app |
| Entitlements match usage | Pass | HealthKit (both apps), App Group (apps + widgets) — all used |
| iPad | N/A | `TARGETED_DEVICE_FAMILY = 1` (iPhone only) |
| Orientations | Pass | Portrait only, matches UI |
| Dark mode | Pass | System colors throughout |
| Required device capabilities | Pass | Default |
