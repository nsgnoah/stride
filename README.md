# Stride

A running coach for iPhone + Apple Watch. Tell it the race distance, how many days a week you can run, and which days you lift; it builds a week-by-week plan with warm-ups, cool-downs, and mobility work, and the watch taps your wrist when you drift off pace.

## Layout

- `Shared/` — models, plan generator, pace math, persistence, phone↔watch sync. Compiled into both apps.
- `Stride/` — iPhone app (setup, today, plan, progress charts, settings).
- `StrideWatch/` — watchOS app (today's run, live pace coaching, summary).
- `project.yml` — [xcodegen](https://github.com/yonaskolb/XcodeGen) spec. The `.xcodeproj` is generated and git-ignored.

## Build

```bash
xcodegen generate
open Stride.xcodeproj
```

Pick the `Stride` scheme and run on your iPhone; the watch app installs alongside it. Both apps need HealthKit (turned on in `project.yml`); the watch also asks for location so it can measure pace with GPS.

## How the plan is built

`Shared/Planning/PlanGenerator.swift`:

- Weekly volume starts at your current mileage, builds ~8%/week, cuts back 20% every 4th week, tapers before race week.
- Weeks 1–2 are all easy. After that: one quality session (alternating intervals / tempo), one long run, easy runs to fill.
- Runs are placed around lifting days. An easy run can share a day with a lift; long runs and speed work are never scheduled on or the day after one.
- Paces come from a recent run via Riegel's formula (`PaceCalculator.swift`): tempo ≈ one-hour race pace, intervals ≈ 3K pace, easy ≈ tempo + 80 s/mi.
- Every run carries a pre-run routine, watch segments (warm-up / work / recovery / cool-down with a pace window), and a post-run stretch. Mobility routines land on the rest days after the long run and the speed session.

## On the watch

`StrideWatch/WorkoutManager.swift` runs an `HKWorkoutSession` so the app stays alive with the screen off, measures distance from GPS and HealthKit (whichever has seen more ground), computes a 30-second rolling pace, and plays `directionUp` / `directionDown` haptics when pace is outside the segment's window — immediately on a change, then every 20 s while still off. Segments advance automatically; the Controls page lets you pause, skip, or end.
