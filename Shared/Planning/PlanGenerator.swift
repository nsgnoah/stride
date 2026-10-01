import Foundation

/// Builds a week-by-week plan from the runner's goal, schedule, and where she is today.
///
/// The plan is sized **per run**, not per week:
///   - The long run starts at the distance she can comfortably run now and grows a little
///     at a time (half a mile while it's short, more once it's long) toward the goal's
///     target, with a lighter week every fourth week. Weekly mileage is whatever the
///     week's runs add up to — one run a week means one run, not a week's miles in a day.
///   - Other runs are shorter than the long run (about 60% of it, capped by goal).
///   - First two weeks are all easy. After that, if she wants it, one faster session a
///     week (alternating intervals / tempo).
///   - A short taper, then race (or goal) week.
///   - Runs land on the weekdays she picked. A hard run avoids lifting days and the day
///     after them whenever her chosen days allow it.
///   - Every run gets a warm-up and cool-down; mobility lands on rest days after hard runs.
struct PlanGenerator {
    var runner: RunnerProfile
    var calendar: Calendar = .current
    var startDate: Date = .now

    // MARK: - Calendar

    /// Weeks in the plan, counting the week the race falls in. A plan started Friday or
    /// later begins the following Monday instead of burning week one on a weekend.
    static func weekCount(from start: Date, to raceDate: Date, calendar: Calendar = .current) -> Int {
        let first = firstMonday(from: start, calendar: calendar)
        let raceWeek = startOfWeek(raceDate, calendar: calendar)
        let days = calendar.dateComponents([.day], from: first, to: raceWeek).day ?? 0
        return max(1, days / 7 + 1)
    }

    static func firstMonday(from date: Date, calendar: Calendar = .current) -> Date {
        let monday = startOfWeek(date, calendar: calendar)
        if Weekday(date: date, calendar: calendar).index >= 4 {
            return calendar.date(byAdding: .day, value: 7, to: monday)!
        }
        return monday
    }

    static func startOfWeek(_ date: Date, calendar: Calendar = .current) -> Date {
        var cal = calendar
        cal.firstWeekday = 2
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps)!
    }

    // MARK: - Targets

    /// Week one's long run: what she says she can comfortably run today.
    static func startLongMiles(for runner: RunnerProfile) -> Double {
        let rounded = (runner.longestComfortableMiles * 2).rounded() / 2
        return min(max(rounded, 1), runner.goal.longRunCapMiles)
    }

    /// The long run the plan builds to. Slightly over distance for short races, under for long ones.
    static func peakLongMiles(for runner: RunnerProfile) -> Double {
        let base: Double = switch runner.goal {
        case .fiveK: 4
        case .tenK: 7
        case .half: 12
        case .marathon: 20
        }
        // Someone already running further keeps her long runs; we don't shrink them.
        return max(base, startLongMiles(for: runner))
    }

    /// Safe week-to-week growth for a long run of this length: half a mile while it's short,
    /// roughly 15% once it's longer, never more than two miles.
    static func maxStep(from miles: Double) -> Double {
        min(2, max(0.5, (miles * 0.15 * 2).rounded() / 2))
    }

    /// How many weeks the build takes when she hasn't given a date.
    static func suggestedWeeks(for runner: RunnerProfile) -> Int {
        var long = startLongMiles(for: runner)
        let peak = peakLongMiles(for: runner)
        var progressive = 1
        while long < peak {
            long = min(peak, long + maxStep(from: long))
            progressive += 1
        }
        let cutbacks = (progressive - 1) / 3 // every fourth week is lighter
        let taper = runner.goal == .marathon ? 2 : 1
        return min(max(progressive + cutbacks + taper + 1, 4), 30)
    }

    /// Week one's longest run and the longest the plan reaches, for the setup screen.
    static func longRunRange(for runner: RunnerProfile, start: Date = .now, calendar: Calendar = .current) -> (first: Double, peak: Double) {
        let r = resolved(runner, start: start, calendar: calendar)
        let weeks = min(max(weekCount(from: start, to: r.raceDate, calendar: calendar), 4), 30)
        let series = PlanGenerator(runner: r, calendar: calendar, startDate: start).longRunSeries(totalWeeks: weeks)
        return (series.first ?? 0, series.dropLast().max() ?? 0)
    }

    /// The profile with a concrete goal day. With no race date, the plan runs as long as
    /// the build needs and ends on the long-run day of its final week.
    static func resolved(_ runner: RunnerProfile, start: Date, calendar: Calendar = .current) -> RunnerProfile {
        guard !runner.hasRaceDate else { return runner }
        var r = runner
        let weeks = suggestedWeeks(for: runner)
        let first = firstMonday(from: start, calendar: calendar)
        r.raceDate = calendar.date(byAdding: .day, value: 7 * (weeks - 1) + runner.longRunDay.index, to: first)!
        return r
    }

    /// The weekdays the planner would pick on its own for this many runs. Used to pre-fill
    /// the run-day picker for plans made before she could choose days.
    static func automaticRunDays(for runner: RunnerProfile) -> Set<Weekday> {
        var r = runner
        r.runDays = []
        let quality: WorkoutType? = r.runCount >= 2 ? .tempo : nil
        return Set(PlanGenerator(runner: r).daySchedule(quality: quality, isRaceWeek: false).keys)
    }

    // MARK: - Build

    func makePlan() -> TrainingPlan {
        var generator = self
        generator.runner = Self.resolved(runner, start: startDate, calendar: calendar)
        return generator.build()
    }

    private func build() -> TrainingPlan {
        let paces = PaceCalculator.profile(for: runner)
        let totalWeeks = min(max(Self.weekCount(from: startDate, to: runner.raceDate, calendar: calendar), 4), 30)
        let longs = longRunSeries(totalWeeks: totalWeeks)

        var weeks: [PlannedWeek] = []
        let firstMonday = Self.firstMonday(from: startDate, calendar: calendar)
        for index in 0..<totalWeeks {
            let weekStart = calendar.date(byAdding: .day, value: 7 * index, to: firstMonday)!
            let isRaceWeek = index == totalWeeks - 1
            let isBase = index < 2
            let isTaper = !isRaceWeek && index >= totalWeeks - 1 - taperCount(totalWeeks)
            let long = longs[index]
            let easy = easyMiles(long: long, isRaceWeek: isRaceWeek)

            // Faster running needs a second day to live on, a couple of easy weeks first,
            // and a long run of at least 2.5 miles so there's a base under it.
            let wantsQuality = runner.includeSpeedWork && runner.runCount >= 2 && !isBase && !isRaceWeek && long >= 2.5
            let quality: WorkoutType? = wantsQuality ? (index % 2 == 0 ? .intervals : .tempo) : nil
            let progress = Double(index) / Double(max(1, totalWeeks - 1))

            let schedule = daySchedule(quality: quality, isRaceWeek: isRaceWeek)
            let days = Weekday.ordered.map { weekday -> PlannedDay in
                let date = calendar.date(byAdding: .day, value: weekday.index, to: weekStart)!
                var workouts: [Workout] = []

                if runner.strengthDays.contains(weekday) {
                    workouts.append(strengthDay())
                }
                if let type = schedule[weekday] {
                    workouts.append(workout(type: type, long: long, easy: easy, paces: paces, progress: progress, isTaper: isTaper))
                }
                if workouts.isEmpty {
                    workouts.append(restOrMobility(weekday: weekday, schedule: schedule))
                }
                // Stable ids per (week, day, type) so a rebuilt plan keeps her checkmarks.
                for i in workouts.indices {
                    workouts[i].id = Workout.stableID("w\(index)-\(weekday.rawValue)-\(workouts[i].type.rawValue)")
                }
                return PlannedDay(date: date, workouts: workouts)
            }

            let focus: String = if isRaceWeek {
                runner.hasRaceDate ? "Race week — short, sharp, and rested." : "Goal week — this is the one where you run the full distance."
            } else if isBase { "Getting started. All easy. Let the body adapt." }
            else if isTaper { "Taper. Shorter runs, fresh legs." }
            else if isCutback(index, totalWeeks: totalWeeks) { "Lighter week. Absorb the last three." }
            else if let quality { quality == .intervals ? "Build week with intervals." : "Build week with a tempo run." }
            else { "Build week. A little further than last time." }

            weeks.append(PlannedWeek(number: index + 1, startDate: weekStart, days: days, focus: focus))
        }

        return TrainingPlan(createdAt: .now, goal: runner.goal, raceDate: runner.raceDate, weeks: weeks, paces: paces)
    }

    // MARK: - Distances

    private func taperCount(_ totalWeeks: Int) -> Int {
        guard totalWeeks > 6 else { return 0 }
        return runner.goal == .marathon ? 2 : 1
    }

    private func buildCount(_ totalWeeks: Int) -> Int { max(1, totalWeeks - 1 - taperCount(totalWeeks)) }

    /// Every fourth week is lighter — except the last build week, which is the peak.
    private func isCutback(_ index: Int, totalWeeks: Int) -> Bool {
        (index + 1) % 4 == 0 && index < buildCount(totalWeeks) - 1
    }

    /// The long run for every week. It starts where she is, steps up toward the peak as fast
    /// as the calendar needs but never faster than `maxStep`, eases back every fourth week,
    /// and tapers at the end. (The race week's entry only sizes that week's easy runs.)
    func longRunSeries(totalWeeks: Int) -> [Double] {
        let start = Self.startLongMiles(for: runner)
        let peak = Self.peakLongMiles(for: runner)
        let build = buildCount(totalWeeks)
        let progressiveCount = (0..<build).filter { !isCutback($0, totalWeeks: totalWeeks) }.count

        var series = [Double](repeating: start, count: totalWeeks)
        var current = start
        var step = 0
        for index in 0..<build {
            if isCutback(index, totalWeeks: totalWeeks) {
                series[index] = max(1, roundHalf(current * 0.8))
                continue
            }
            if step > 0 {
                let ideal = roundHalf(start + (peak - start) * Double(step) / Double(max(1, progressiveCount - 1)))
                current = max(current, min(ideal, current + Self.maxStep(from: current)))
            }
            series[index] = current
            step += 1
        }
        for index in build..<totalWeeks {
            let weeksOut = totalWeeks - 1 - index
            let factor = weeksOut == 0 ? 0.5 : (weeksOut == 1 ? 0.6 : 0.75)
            series[index] = max(1, roundHalf(current * factor))
        }
        return series
    }

    /// The other runs of the week: comfortably shorter than the long run.
    private func easyMiles(long: Double, isRaceWeek: Bool) -> Double {
        let cap: Double = switch runner.goal {
        case .fiveK: 3
        case .tenK: 4.5
        case .half: 6
        case .marathon: 8
        }
        let miles = min(max(1, roundHalf(long * 0.6)), cap, long)
        return isRaceWeek ? min(miles, 3) : miles
    }

    // MARK: - Scheduling

    /// Which run lands on which weekday.
    func daySchedule(quality: WorkoutType?, isRaceWeek: Bool) -> [Weekday: WorkoutType] {
        let count = runner.runCount
        let chosen = runner.runDays
        let lifting = runner.strengthDays
        let dayAfterLift = Set(lifting.map { Weekday.ordered[($0.index + 1) % 7] })
        var schedule: [Weekday: WorkoutType] = [:]

        if isRaceWeek {
            let raceDay = Weekday(date: runner.raceDate, calendar: calendar)
            schedule[raceDay] = .race
            // Shakeout the day before, unless the race is Monday (that day is last week).
            if raceDay.index >= 1, count >= 2 {
                schedule[Weekday.ordered[raceDay.index - 1]] = .shakeout
            }
            var easyDays = count - 2
            let candidates = chosen.isEmpty ? Weekday.ordered.filter { !lifting.contains($0) } : chosen.sorted()
            for day in candidates where easyDays > 0 && day.index < raceDay.index - 1 {
                schedule[day] = .easy
                easyDays -= 1
            }
            return schedule
        }

        // Her own days: keep every run on them and choose which one is long / fast.
        if !chosen.isEmpty {
            let days = chosen.sorted()
            let clear: (Weekday) -> Bool = { !lifting.contains($0) && !dayAfterLift.contains($0) }
            let longDay: Weekday = if days.contains(runner.longRunDay) {
                runner.longRunDay
            } else {
                days.last(where: clear) ?? days.last { !lifting.contains($0) } ?? days.last!
            }
            schedule[longDay] = .long
            var rest = days.filter { $0 != longDay }
            if let quality, !rest.isEmpty {
                func gap(_ d: Weekday) -> Int {
                    let diff = abs(d.index - longDay.index)
                    return min(diff, 7 - diff)
                }
                // Loosen one constraint at a time; a hard run on a lifting day is the last resort.
                let tiers: [(Weekday) -> Bool] = [
                    { clear($0) && gap($0) >= 2 },
                    { clear($0) },
                    { !lifting.contains($0) },
                    { _ in true },
                ]
                for allowed in tiers {
                    if let day = rest.filter(allowed).max(by: { gap($0) < gap($1) }) {
                        schedule[day] = quality
                        rest.removeAll { $0 == day }
                        break
                    }
                }
            }
            for day in rest { schedule[day] = .easy }
            return schedule
        }

        // No days chosen (older plans): place runs around the lifting days.
        let longDay = bestDay(preferring: runner.longRunDay, avoidTiers: [lifting.union(dayAfterLift), lifting], taken: [])
        schedule[longDay] = .long

        var taken: Set<Weekday> = [longDay]
        if let quality {
            let preferred = Weekday.ordered[(longDay.index + 4) % 7]
            let buffer = Set([-1, 0, 1].map { Weekday.ordered[(longDay.index + $0 + 7) % 7] })
            let q = bestDay(preferring: preferred, avoidTiers: [lifting.union(dayAfterLift).union(buffer), lifting.union(dayAfterLift), lifting], taken: taken)
            schedule[q] = quality
            taken.insert(q)
        }

        var remaining = count - schedule.count
        let spread = spreadOrder(from: longDay)
        for day in spread where remaining > 0 && !taken.contains(day) && !lifting.contains(day) {
            schedule[day] = .easy
            taken.insert(day)
            remaining -= 1
        }
        for day in spread where remaining > 0 && !taken.contains(day) {
            schedule[day] = .easy
            taken.insert(day)
            remaining -= 1
        }
        return schedule
    }

    /// Nearest free day to `preferred`, trying each avoid-set in order (strictest first).
    private func bestDay(preferring preferred: Weekday, avoidTiers: [Set<Weekday>], taken: Set<Weekday>) -> Weekday {
        for avoiding in avoidTiers {
            if !avoiding.contains(preferred), !taken.contains(preferred) { return preferred }
            for offset in [1, -1, 2, -2, 3, -3] {
                let d = Weekday.ordered[(preferred.index + offset + 7) % 7]
                if !avoiding.contains(d), !taken.contains(d) { return d }
            }
        }
        for offset in 1...6 {
            let d = Weekday.ordered[(preferred.index + offset) % 7]
            if !taken.contains(d) { return d }
        }
        return preferred
    }

    /// Days ordered so consecutive picks are as far apart as possible from the anchor.
    private func spreadOrder(from anchor: Weekday) -> [Weekday] {
        [2, 5, 3, 4, 6, 1].map { Weekday.ordered[(anchor.index + $0) % 7] }
    }

    // MARK: - Workouts

    private func strengthDay() -> Workout {
        Workout(type: .strength, title: "Lift",
                summary: "Your strength day. Runs are scheduled around it. No program of your own? Runner Strength below takes 15 minutes.",
                standaloneRoutineID: RoutineLibrary.runnerStrength.id)
    }

    private func restOrMobility(weekday: Weekday, schedule: [Weekday: WorkoutType]) -> Workout {
        // Put mobility on the rest days right after the hardest sessions.
        let yesterday = schedule[Weekday.ordered[(weekday.index + 6) % 7]]
        let routine: Routine? = if yesterday == .long {
            RoutineLibrary.hipMobility
        } else if yesterday == .intervals || yesterday == .tempo {
            RoutineLibrary.calfAnkle
        } else { nil }

        if let routine {
            return Workout(type: .mobility, title: routine.title, summary: routine.purpose, standaloneRoutineID: routine.id)
        }
        return .rest
    }

    private func workout(type: WorkoutType, long: Double, easy: Double, paces: PaceProfile, progress: Double, isTaper: Bool) -> Workout {
        // Speed work shrinks in the taper so the week actually gets lighter.
        let qualityScale = isTaper ? 0.6 : 1.0

        let warmupJog = Segment(kind: .warmup, name: "Warm-up jog", goal: .time(8 * 60), pace: PaceRange(fast: paces.easy.fast, slow: paces.easy.slow + 60))
        let cooldownJog = Segment(kind: .cooldown, name: "Cool-down jog", goal: .time(5 * 60), pace: PaceRange(fast: paces.easy.fast, slow: paces.easy.slow + 90))

        switch type {
        case .easy:
            return Workout(
                type: .easy,
                title: "Easy \(fmt(easy)) mi",
                summary: "Conversational pace. If you can't chat, slow down. These miles build the engine.",
                segments: [
                    Segment(kind: .warmup, name: "Walk & drills", goal: .time(4 * 60), pace: nil),
                    Segment(kind: .work, name: "Easy run", goal: .distance(Units.meters(miles: easy)), pace: paces.easy),
                    Segment(kind: .cooldown, name: "Walk", goal: .time(3 * 60), pace: nil),
                ],
                plannedMeters: Units.meters(miles: easy),
                preRoutineID: RoutineLibrary.dynamicWarmup.id,
                postRoutineID: RoutineLibrary.cooldown.id
            )

        case .long:
            // With one run a week there's nothing for it to be "long" relative to.
            let title = runner.runCount == 1 ? "Run \(fmt(long)) mi" : "Long run \(fmt(long)) mi"
            return Workout(
                type: .long,
                title: title,
                summary: "Relaxed and steady. Start slower than feels necessary. Bring water past 6 miles.",
                segments: [
                    Segment(kind: .warmup, name: "Walk & drills", goal: .time(4 * 60), pace: nil),
                    Segment(kind: .work, name: runner.runCount == 1 ? "Run" : "Long run", goal: .distance(Units.meters(miles: long)), pace: paces.long),
                    Segment(kind: .cooldown, name: "Walk", goal: .time(5 * 60), pace: nil),
                ],
                plannedMeters: Units.meters(miles: long),
                preRoutineID: RoutineLibrary.dynamicWarmup.id,
                postRoutineID: RoutineLibrary.cooldown.id
            )

        case .tempo:
            let tempoMinutes = max(8, ((10 + progress * 15) * qualityScale).rounded()) // 10 → 25 min
            let tempoMiles = tempoMinutes * 60 / paces.tempo.midpoint
            let total = 13.0 * 60 / paces.easy.midpoint + tempoMiles
            return Workout(
                type: .tempo,
                title: "Tempo \(Int(tempoMinutes)) min",
                summary: "Comfortably hard — you could say a few words but not hold a conversation. Even effort start to finish.",
                segments: [
                    warmupJog,
                    Segment(kind: .work, name: "Tempo", goal: .time(tempoMinutes * 60), pace: paces.tempo),
                    cooldownJog,
                ],
                plannedMeters: Units.meters(miles: total),
                preRoutineID: RoutineLibrary.speedWarmup.id,
                postRoutineID: RoutineLibrary.cooldown.id
            )

        case .intervals:
            let reps = max(3, Int(((4 + progress * 4) * qualityScale).rounded())) // 4 → 8
            // Short reps while her runs are short or the goal is a 5K; half-mile reps after that.
            let repMeters: Double = (runner.goal == .fiveK || long < 5) ? 400 : 800
            let recoverySeconds: TimeInterval = repMeters == 400 ? 90 : 120
            var segments: [Segment] = [warmupJog]
            for i in 1...reps {
                segments.append(Segment(kind: .work, name: "Rep \(i) of \(reps)", goal: .distance(repMeters), pace: paces.interval))
                if i < reps {
                    segments.append(Segment(kind: .recovery, name: "Recover", goal: .time(recoverySeconds), pace: nil))
                }
            }
            segments.append(cooldownJog)
            let workMiles = Units.miles(repMeters * Double(reps))
            let total = 13.0 * 60 / paces.easy.midpoint + workMiles + Double(reps - 1) * recoverySeconds / 60 / 12
            return Workout(
                type: .intervals,
                title: "\(reps) × \(Int(repMeters)) m",
                summary: "Fast but controlled — the last rep should feel like the first. Jog or walk the recoveries.",
                segments: segments,
                plannedMeters: Units.meters(miles: total),
                preRoutineID: RoutineLibrary.speedWarmup.id,
                postRoutineID: RoutineLibrary.cooldown.id
            )

        case .shakeout:
            let miles = min(2, max(1, easy))
            return Workout(
                type: .shakeout,
                title: "Shakeout \(fmt(miles)) mi",
                summary: "Very easy, with a few short pickups to remind the legs what fast feels like.",
                segments: [
                    Segment(kind: .work, name: "Easy jog", goal: .distance(Units.meters(miles: miles)), pace: PaceRange(fast: paces.easy.fast, slow: paces.easy.slow + 30)),
                ],
                plannedMeters: Units.meters(miles: miles),
                preRoutineID: RoutineLibrary.dynamicWarmup.id,
                postRoutineID: RoutineLibrary.cooldown.id
            )

        case .race:
            return Workout(
                type: .race,
                title: runner.hasRaceDate ? "\(runner.goal.name) Race" : "Run your \(runner.goal.name)",
                summary: runner.hasRaceDate
                    ? "Trust the training. First mile controlled, settle in, empty the tank in the last quarter."
                    : "This is the one you've been building to. Start easy, settle in, and enjoy going the whole way.",
                segments: [
                    Segment(kind: .work, name: runner.goal.name, goal: .distance(runner.goal.meters), pace: paces.race),
                ],
                plannedMeters: runner.goal.meters,
                preRoutineID: RoutineLibrary.raceDayWarmup.id,
                postRoutineID: RoutineLibrary.cooldown.id
            )

        case .strength, .mobility, .rest:
            return Workout(type: type, title: type.name, summary: "")
        }
    }

    private func roundHalf(_ x: Double) -> Double { (x * 2).rounded() / 2 }

    private func fmt(_ x: Double) -> String {
        x == x.rounded() ? String(Int(x)) : String(format: "%.1f", x)
    }
}
