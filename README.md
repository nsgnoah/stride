# Stride

A running coach for iPhone + Apple Watch. Tell it the distance you're building to, which days you run, and which days you lift; it builds a week-by-week plan with warm-ups, cool-downs, and mobility work, and the watch taps your wrist when you drift off pace.

## What it does

**iPhone**
- **Setup** — goal (5K / 10K / half / marathon), race day, runs per week, lifting days, long-run day, current mileage, one recent run. Training paces preview live.
- **Today** — the week at a glance (lifts included), today's session with its warm-up / watch segments / cool-down, missed runs with *Do it today* / *Skip*, log a lift.
- **Plan** — every week, expandable; planned vs. done mileage. Any workout can be moved to another day or skipped from its detail screen.
- **Progress** — planned-vs-actual weekly miles, easy-pace trend, this week's totals (runs, lifts, mobility), history with per-run detail and mile splits. Import runs recorded with the Workout app or another tracker from Apple Health.
- **Settings** — paces, morning reminder on run days, update paces from a recorded tempo/race, rebuild the plan (keeps week numbers, finished runs, skips and moved days), the full routine library, privacy/medical notes.
- **Widget** — today's run and the week on the Home Screen and Lock Screen.

**Apple Watch**
- Today's run with a Start button; free run; check off lifts/mobility from the wrist.
- During a run: segment name and countdown, big current pace colored green / orange / blue, target window, `directionUp` / `directionDown` haptics when off pace (immediately on a change, then every 20 s), mile-split tap with the split shown, three clicks as a timed segment ends, auto-pause when you stop, pause / skip segment / end on the controls page.
- Summary with splits and the cool-down stretches; saving sends the run to the phone instantly (or queues it if the phone's away) and writes a workout to Health.
- Complication for the Smart Stack / watch face.

## Layout

- `Shared/` — models, plan generator, pace math, persistence, phone↔watch sync. Compiled into every target.
- `Stride/` — iPhone app. `StrideWatch/` — watchOS app. `StrideWidget/` — WidgetKit code built for both iOS and watchOS.
- `StrideTests/` — Swift Testing suite for the generator, plan editing, and pace math.
- `project.yml` — [xcodegen](https://github.com/yonaskolb/XcodeGen) spec. The `.xcodeproj` is generated and git-ignored.

## Build

```bash
xcodegen generate
open Stride.xcodeproj
```

Pick the `Stride` scheme and run on an iPhone with a paired watch; the watch app and both widget extensions install alongside. Capabilities: HealthKit (both apps), an App Group (`group.co.nsgsolutions.stride`) shared with the widgets, location when-in-use on the watch. Automatic signing (team in `project.yml`) registers these on first archive.

Tests: `xcodebuild test -scheme Stride -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.

## How the plan is built

`Shared/Planning/PlanGenerator.swift`:

- Runs are sized per run, not from a weekly total: the longest run starts at the distance you can comfortably cover today and grows a little each week (lighter every 4th week) toward the goal's peak; other runs are shorter. One run a week is just that run. Tapers (two steps for a marathon) before a short race week. A race date is optional — without one the plan is as long as a safe build-up needs.
- Weeks 1–2 are all easy. After that: one quality session (alternating intervals / tempo), one long run, easy runs to fill. Speed work shrinks in the taper so the week's total actually drops.
- Runs are placed around lifting days. Constraints loosen in tiers: first the day-after-long-run buffer, then the day-after-lift rule; a hard run on a lifting day itself is the last resort. An easy run can share a lift day.
- Paces come from a recent run via Riegel's formula (`PaceCalculator.swift`): tempo ≈ one-hour race pace, intervals ≈ 3K pace, easy ≈ tempo + 80 s/mi.
- Every run carries a pre-run routine, watch segments (warm-up / work / recovery / cool-down with a pace window), and a post-run stretch. Mobility routines land on the rest days after the long run and the speed session.
- Workout ids are deterministic per slot, so rebuilding the plan (new paces, tweaked schedule) keeps completed runs matched to their records.

## On the watch

`StrideWatch/WorkoutManager.swift` runs an `HKWorkoutSession` so the app stays alive with the screen off, measures distance from GPS and HealthKit (whichever has seen more ground), computes a 30-second rolling pace, and coaches against the segment's window. Segments advance automatically.

## Sync

`Shared/Sync/Connectivity.swift`: the phone pushes the whole plan as `applicationContext` whenever it changes; the watch sends finished runs with `sendMessage` when the phone is reachable and `transferUserInfo` otherwise. Both apps persist to JSON in the app group, which the widgets read.

## The coach's voice

The watch only ships Apple's compact voices, so spoken cues are stitched from short recorded clips in `StrideWatch/Voice/` (about 400: numbers, units, segment names, a handful of phrases). `Shared/Voice/VoiceScript.swift` decides what is said and which clips say it; a cue with any clip missing is read by the system voice instead.

`Tools/render_voice.py` records the clips with an ElevenLabs voice (`ELEVENLABS_API_KEY` and `ELEVENLABS_VOICE_ID` in the environment or a git-ignored `.env`), trims and levels them, and encodes them as AAC. `--audition` records just enough for a few whole cues and writes them to `build/voice-samples/`; `--render` records everything that's missing (about 5,800 characters). After changing what the coach says, run `--manifest` and the tests, which check every cue against the clip list.
