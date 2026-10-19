# Personal bests on the Progress tab

## Choice

Stride records every run (watch, manual log, or Health import) with distance, time and mile
splits, but nothing ever tells the runner she has done something new: her longest run, her
fastest mile, her quickest 5K. The Progress tab shows trends (weekly miles, easy pace) but no
milestones. Personal bests are the obvious missing piece of a training app, they build directly
on data that already exists, and the logic is pure enough to unit-test.

No TODOs or roadmap files point elsewhere, and there are no open garden PRs to collide with.

## Plan

- `Shared/Models/PersonalBests.swift`: computes from `[ActivityRecord]`:
  - longest run (meters)
  - fastest full-mile split (ignoring sub-3:00 splits as GPS jumps)
  - best average pace over runs at least each goal distance (5K / 10K / half / marathon),
    with 2% slack for GPS coming up short
  - biggest Monday–Sunday week of running
  - ties go to the run that set the record first
  - `titles(for:)` lists the records a given run holds
- Progress tab: a "Personal bests" section, each row opening the run that set it.
- Run detail: a "Personal best: …" footer under the stats when the run holds a record.
- Swift Testing suite `StrideTests/PersonalBestsTests.swift`.

Not stored anywhere, so deleting or importing runs updates the records straight away and there
is no migration.

## Left out on purpose

- "New PB!" on the watch summary or a notification: needs the phone's full history on the watch.
- Exact best-effort times inside a longer run (e.g. a fastest 5K inside a 10K): needs per-second
  distance samples that aren't stored.
