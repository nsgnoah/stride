import Testing
import Foundation
@testable import Stride

/// Invariants the plan generator must hold for any sensible runner profile.
struct PlanGeneratorTests {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        return c
    }()

    static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 9))!
    }

    static func profile(goal: GoalDistance = .tenK, days: Int = 4, lifts: Set<Weekday> = [], longDay: Weekday = .saturday, weeks: Int = 10, start: Date = date(2026, 9, 28)) -> RunnerProfile {
        var p = RunnerProfile()
        p.goal = goal
        p.runDaysPerWeek = days
        p.strengthDays = lifts
        p.longRunDay = longDay
        p.currentWeeklyMiles = 12
        p.raceDate = calendar.date(byAdding: .day, value: 7 * weeks - 1, to: start)! // a Sunday
        return p
    }

    static func plan(_ p: RunnerProfile, start: Date = date(2026, 9, 28)) -> TrainingPlan {
        PlanGenerator(runner: p, calendar: calendar, startDate: start).makePlan()
    }

    /// Every combination we care about: 4 goals × 3–6 days × a few lifting patterns.
    static var grid: [RunnerProfile] {
        var out: [RunnerProfile] = []
        for goal in GoalDistance.allCases {
            for days in 1...6 {
                for lifts in [Set<Weekday>(), [.monday, .thursday], [.tuesday, .friday], [.monday, .wednesday, .friday]] {
                    out.append(profile(goal: goal, days: days, lifts: lifts, weeks: goal.defaultWeeks))
                }
            }
        }
        return out
    }

    // MARK: - Calendar math

    @Test func startingOnSundayBeginsNextMonday() {
        let sunday = Self.date(2026, 9, 27)
        let monday = PlanGenerator.firstMonday(from: sunday, calendar: Self.calendar)
        #expect(Self.calendar.component(.weekday, from: monday) == 2)
        #expect(Self.calendar.isDate(monday, inSameDayAs: Self.date(2026, 9, 28)))
    }

    @Test func startingMidweekKeepsCurrentWeek() {
        let wednesday = Self.date(2026, 9, 30)
        let monday = PlanGenerator.firstMonday(from: wednesday, calendar: Self.calendar)
        #expect(Self.calendar.isDate(monday, inSameDayAs: Self.date(2026, 9, 28)))
    }

    @Test func raceWeekIsTheLastWeek() {
        let p = Self.profile(weeks: 10)
        let plan = Self.plan(p)
        #expect(plan.weeks.count == 10)
        let last = plan.weeks.last!
        #expect(last.days.contains { Self.calendar.isDate($0.date, inSameDayAs: p.raceDate) })
        let raceDay = last.days.first { Self.calendar.isDate($0.date, inSameDayAs: p.raceDate) }!
        #expect(raceDay.workouts.contains { $0.type == .race })
    }

    @Test func mondayRaceHasNoShakeoutAfterTheRace() {
        var p = Self.profile()
        p.raceDate = Self.date(2026, 12, 7) // a Monday
        let plan = Self.plan(p)
        let last = plan.weeks.last!
        let raceIndex = last.days.firstIndex { $0.workouts.contains { $0.type == .race } }!
        #expect(raceIndex == 0)
        #expect(!last.days.dropFirst().contains { $0.workouts.contains { $0.type.isRun } })
    }

    // MARK: - Schedule shape

    @Test func runsPerWeekMatchesTheProfile() {
        for p in Self.grid {
            let plan = Self.plan(p)
            for week in plan.weeks.dropLast() {
                #expect(week.runCount == p.runDaysPerWeek, "\(p.goal) \(p.runDaysPerWeek)d lifts=\(p.strengthDays.count) week \(week.number)")
            }
        }
    }

    @Test func hardRunsAvoidLiftingDays() {
        for p in Self.grid where p.runDaysPerWeek + p.strengthDays.count <= 7 {
            let plan = Self.plan(p)
            for day in plan.allDays {
                let types = Set(day.workouts.map(\.type))
                if types.contains(.strength) {
                    #expect(!types.contains(.long) && !types.contains(.tempo) && !types.contains(.intervals),
                            "\(p.goal) \(p.runDaysPerWeek)d: hard run on a lift day \(day.weekday)")
                }
            }
        }
    }

    @Test func noHardRunTheDayAfterALift() {
        // Only where it's satisfiable: at least two days that are neither a lift nor the day after one.
        for p in Self.grid where p.runDaysPerWeek + p.strengthDays.count <= 6 && Self.freeDays(p).count >= 2 {
            let plan = Self.plan(p)
            for week in plan.weeks.dropLast() {
                for (i, day) in week.days.enumerated() where i > 0 {
                    let liftYesterday = week.days[i - 1].workouts.contains { $0.type == .strength }
                    let hardToday = day.workouts.contains { [.long, .tempo, .intervals].contains($0.type) }
                    #expect(!(liftYesterday && hardToday), "\(p.goal) \(p.runDaysPerWeek)d lifts=\(p.strengthDays): hard run after lift on \(day.weekday)")
                }
            }
        }
    }

    static func freeDays(_ p: RunnerProfile) -> Set<Weekday> {
        let after = Set(p.strengthDays.map { Weekday.ordered[($0.index + 1) % 7] })
        return Set(Weekday.ordered).subtracting(p.strengthDays).subtracting(after)
    }

    @Test func oneDayAWeekIsJustTheLongRun() {
        let plan = Self.plan(Self.profile(days: 1))
        for week in plan.weeks.dropLast() {
            let runs = week.days.flatMap(\.workouts).filter { $0.type.isRun }
            #expect(runs.map(\.type) == [.long], "week \(week.number)")
        }
        let raceWeekRuns = plan.weeks.last!.days.flatMap(\.workouts).filter { $0.type.isRun }
        #expect(raceWeekRuns.map(\.type) == [.race])
    }

    @Test func twoDaysAWeekAlwaysKeepsTheLongRun() {
        let plan = Self.plan(Self.profile(days: 2, lifts: [.monday, .thursday]))
        for week in plan.weeks.dropLast() {
            let types = week.days.flatMap(\.workouts).filter { $0.type.isRun }.map(\.type)
            #expect(types.count == 2 && types.contains(.long), "week \(week.number): \(types)")
        }
    }

    @Test func firstTwoWeeksAreAllEasy() {
        for p in Self.grid {
            let plan = Self.plan(p)
            for week in plan.weeks.prefix(2) {
                #expect(!week.days.flatMap(\.workouts).contains { $0.type == .tempo || $0.type == .intervals })
            }
        }
    }

    @Test func everyRunHasWarmupAndCooldownRoutines() {
        let plan = Self.plan(Self.profile())
        for w in plan.allDays.flatMap(\.workouts) where w.type.isRun {
            #expect(RoutineLibrary.routine(w.preRoutineID) != nil, "\(w.title)")
            #expect(RoutineLibrary.routine(w.postRoutineID) != nil, "\(w.title)")
            #expect(!w.segments.isEmpty)
        }
    }

    @Test func mobilityLandsAfterLongRun() {
        let plan = Self.plan(Self.profile(days: 4, longDay: .saturday))
        let week = plan.weeks[2]
        let sunday = week.days.last!
        #expect(sunday.workouts.contains { $0.type == .mobility })
    }

    // MARK: - Volume

    @Test func volumeNeverJumpsMoreThanFifteenPercentAboveThePriorPeak() {
        for p in Self.grid {
            let plan = Self.plan(p)
            let miles = plan.weeks.dropLast().map { Units.miles($0.plannedMeters) }
            var peak = miles[0]
            for i in 1..<miles.count {
                // A week after a cutback jumps back up; what matters is never overshooting
                // the previous peak by more than the build rate (rounding to half miles adds slack).
                #expect(miles[i] <= peak * 1.15 + 0.5, "\(p.goal) \(p.runDaysPerWeek)d week \(i + 1): peak \(peak) → \(miles[i])")
                peak = max(peak, miles[i])
            }
        }
    }

    @Test func longRunNeverExceedsTheGoalCap() {
        for p in Self.grid {
            let plan = Self.plan(p)
            for w in plan.allDays.flatMap(\.workouts) where w.type == .long {
                #expect(Units.miles(w.plannedMeters) <= p.goal.longRunCapMiles + 0.01)
            }
        }
    }

    @Test func raceWeekIsLighterThanTheWeekBefore() {
        for p in Self.grid where p.goal != .fiveK {
            let plan = Self.plan(p)
            let weeks = plan.weeks
            let raceWeekTraining = Units.miles(weeks.last!.plannedMeters - p.goal.meters)
            let before = Units.miles(weeks[weeks.count - 2].plannedMeters)
            #expect(raceWeekTraining < before, "\(p.goal) \(p.runDaysPerWeek)d")
        }
    }

    // MARK: - Stability

    @Test func rebuildingKeepsWorkoutIDs() {
        let p = Self.profile()
        let a = Self.plan(p)
        var p2 = p
        p2.recentRunSeconds += 120 // slower recent run → new paces, same schedule
        let b = Self.plan(p2)
        let idsA = a.allDays.flatMap(\.workouts).map(\.id)
        let idsB = b.allDays.flatMap(\.workouts).map(\.id)
        #expect(idsA == idsB)
        #expect(Set(idsA).count == idsA.count, "ids must be unique within a plan")
    }

    @Test func moveAndSkipRoundTrip() {
        var plan = Self.plan(Self.profile())
        let tuesday = plan.weeks[0].days[1]
        let run = tuesday.workouts.first { $0.type.isRun }!
        let thursday = plan.weeks[0].days[3].date
        plan.move(workoutID: run.id, to: thursday)
        #expect(plan.weeks[0].days[3].workouts.contains { $0.id == run.id })
        #expect(!plan.weeks[0].days[1].workouts.contains { $0.id == run.id })
        #expect(!plan.weeks[0].days[1].workouts.isEmpty) // rest placeholder, never an empty day
        plan.skipped.insert(run.id)
        #expect(plan.isSkipped(run))
    }

    @Test func plansRoundTripThroughJSON() throws {
        let plan = Self.plan(Self.profile())
        let data = try JSONEncoder().encode(plan)
        let back = try JSONDecoder().decode(TrainingPlan.self, from: data)
        #expect(back == plan)
    }
}

struct PlanEditingTests {
    @Test func movingOntoALiftDaySharesIt() {
        var plan = PlanGeneratorTests.plan(PlanGeneratorTests.profile(lifts: [.monday, .thursday]))
        let week = plan.weeks[1]
        let run = week.days.first { $0.workouts.contains { $0.type.isRun } }!.workouts.first { $0.type.isRun }!
        let monday = week.days[0]
        #expect(monday.workouts.contains { $0.type == .strength })
        plan.move(workoutID: run.id, to: monday.date)
        let after = plan.weeks[1].days[0].workouts
        #expect(after.contains { $0.type == .strength })
        #expect(after.contains { $0.id == run.id })
    }

    @Test func movingToAnUnknownDateIsANoOp() {
        var plan = PlanGeneratorTests.plan(PlanGeneratorTests.profile())
        let before = plan
        let run = plan.allDays.flatMap(\.workouts).first { $0.type.isRun }!
        plan.move(workoutID: run.id, to: Date.distantFuture)
        #expect(plan == before)
        #expect(plan.date(of: run.id) == before.date(of: run.id))
    }

    @Test func movesAreRememberedAndSurviveARebuild() {
        var plan = PlanGeneratorTests.plan(PlanGeneratorTests.profile())
        let run = plan.weeks[1].days[1].workouts.first { $0.type.isRun }!
        let sunday = plan.weeks[1].days[6].date
        plan.move(workoutID: run.id, to: sunday)
        #expect(plan.moves[run.id] == sunday)

        // A rebuild with new paces regenerates every slot, then re-applies the move.
        var rebuilt = PlanGeneratorTests.plan(PlanGeneratorTests.profile())
        for (id, date) in plan.moves { rebuilt.move(workoutID: id, to: date) }
        #expect(PlanGeneratorTests.calendar.isDate(rebuilt.date(of: run.id)!, inSameDayAs: sunday))
    }

    @Test func skipsAndMovesRoundTripThroughJSON() throws {
        // Snapshot round-trip keeps skips and moves; that's what the watch relies on.
        var plan = PlanGeneratorTests.plan(PlanGeneratorTests.profile())
        let run = plan.allDays.flatMap(\.workouts).first { $0.type.isRun }!
        plan.skipped.insert(run.id)
        let data = try JSONEncoder().encode(plan)
        let back = try JSONDecoder().decode(TrainingPlan.self, from: data)
        #expect(back.isSkipped(run))
        #expect(back == plan)
    }

    @Test @MainActor func droppingThePlanKeepsLoggedRuns() {
        let store = AppStore(filename: "stride-test-\(UUID().uuidString).json")
        defer { store.reset() }
        store.createPlan(from: PlanGeneratorTests.profile())
        store.record(ActivityRecord(date: .now, type: .easy, durationSeconds: 1800, meters: 4800))
        store.dropPlan()
        #expect(store.plan == nil)
        #expect(store.freeMode)
        #expect(store.activities.count == 1)
        #expect(store.profile != nil) // her schedule is kept for the next plan's setup
    }

    @Test @MainActor func skippedRunsAreNeitherMissedNorNext() {
        let store = AppStore(filename: "stride-test-\(UUID().uuidString).json")
        defer { store.reset() }
        var profile = PlanGeneratorTests.profile()
        profile.raceDate = Calendar.current.date(byAdding: .weekOfYear, value: 10, to: .now)!
        store.createPlan(from: profile)
        // Pretend the plan started two weeks ago so there are runs in the past.
        var plan = PlanGenerator(runner: profile, startDate: Calendar.current.date(byAdding: .day, value: -14, to: .now)!).makePlan()
        let pastRun = plan.allDays.first { $0.date < Calendar.current.startOfDay(for: .now) && $0.workouts.contains { $0.type.isRun } }!.workouts.first { $0.type.isRun }!
        plan.skipped.insert(pastRun.id)
        store.replacePlan(plan)
        #expect(!store.missedRuns.contains { $0.workout.id == pastRun.id })
        #expect(store.nextRun?.workout.id != pastRun.id)
    }
}

struct RecalibrationTests {
    static func record(_ type: WorkoutType, miles: Double, minutes: Double, daysAgo: Int) -> ActivityRecord {
        ActivityRecord(date: Date.now.addingTimeInterval(-Double(daysAgo) * 86400), type: type, durationSeconds: minutes * 60, meters: Units.meters(miles: miles))
    }

    @Test func prefersHardEffortsOverLongRuns() {
        let acts = [
            Self.record(.long, miles: 8, minutes: 88, daysAgo: 3),   // faster-equivalent, but a long run
            Self.record(.tempo, miles: 3, minutes: 27, daysAgo: 10),
            Self.record(.easy, miles: 3, minutes: 24, daysAgo: 1),   // fast easy run, must be ignored
        ]
        let best = PaceCalculator.bestRecentEffort(in: acts)
        #expect(best?.type == .tempo)
    }

    @Test func fallsBackToLongRunsAndIgnoresOldOrShortOnes() {
        let acts = [
            Self.record(.long, miles: 6, minutes: 66, daysAgo: 5),
            Self.record(.race, miles: 6.2, minutes: 50, daysAgo: 60), // too old
            Self.record(.tempo, miles: 0.5, minutes: 4, daysAgo: 2),  // too short
        ]
        #expect(PaceCalculator.bestRecentEffort(in: acts)?.type == .long)
        #expect(PaceCalculator.bestRecentEffort(in: []) == nil)
    }
}

struct PaceCalculatorTests {
    @Test func zonesAreOrdered() {
        var p = RunnerProfile()
        p.recentRunMeters = Units.meters(miles: 3)
        p.recentRunSeconds = 30 * 60
        let z = PaceCalculator.profile(for: p)
        #expect(z.interval.midpoint < z.tempo.midpoint)
        #expect(z.tempo.midpoint < z.easy.midpoint)
        #expect(z.race.midpoint > z.interval.midpoint)
        #expect(z.race.midpoint < z.easy.midpoint)
    }

    @Test func riegelPredictsSlowerPaceForLongerRaces() {
        let fiveK = PaceCalculator.predictedPace(forMeters: 5000, fromMeters: 5000, seconds: 25 * 60)
        let half = PaceCalculator.predictedPace(forMeters: 21_097.5, fromMeters: 5000, seconds: 25 * 60)
        #expect(abs(fiveK - 25 * 60 / Units.miles(5000)) < 0.01)
        #expect(half > fiveK)
    }
}
