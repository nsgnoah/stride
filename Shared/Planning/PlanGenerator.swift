import Foundation

/// Builds a week-by-week plan from the runner's goal, schedule, and current fitness.
///
/// Principles baked in:
///   - Start where she is (current weekly miles), build ~8%/week, cut back every 4th week.
///   - First two weeks are all easy running. Speed work comes once there's a base.
///   - One quality session a week (alternating tempo / intervals), one long run, rest easy.
///   - Taper before the race. Race week is short and sharp.
///   - Runs avoid lifting days. If a day must be shared, it's an easy run, and there is
///     never a long run or speed session the day after a lift.
///   - Every run gets a warm-up and cool-down. Two mobility sessions a week land on rest days.
struct PlanGenerator {
    var runner: RunnerProfile
    var calendar: Calendar = .current
    var startDate: Date = .now

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

    func makePlan() -> TrainingPlan {
        let paces = PaceCalculator.profile(for: runner)
        let totalWeeks = min(max(Self.weekCount(from: startDate, to: runner.raceDate, calendar: calendar), 4), 24)
        let volumes = weeklyVolumes(weeks: totalWeeks)

        var weeks: [PlannedWeek] = []
        let firstMonday = Self.firstMonday(from: startDate, calendar: calendar)
        for index in 0..<totalWeeks {
            let weekStart = calendar.date(byAdding: .day, value: 7 * index, to: firstMonday)!
            let isRaceWeek = index == totalWeeks - 1
            let isBase = index < 2
            let isTaper = !isRaceWeek && index >= totalWeeks - 1 - taperWeeks && totalWeeks > 6
            let quality: WorkoutType? = (isBase || isRaceWeek) ? nil : (index % 2 == 0 ? .intervals : .tempo)

            let schedule = daySchedule(quality: quality, isRaceWeek: isRaceWeek)
            let days = Weekday.ordered.map { weekday -> PlannedDay in
                let date = calendar.date(byAdding: .day, value: weekday.index, to: weekStart)!
                var workouts: [Workout] = []

                if runner.strengthDays.contains(weekday) {
                    workouts.append(strengthDay())
                }
                if let type = schedule[weekday] {
                    let w = workout(type: type, weekMiles: volumes[index], paces: paces, weekIndex: index, totalWeeks: totalWeeks, quality: quality, isTaper: isTaper, isRaceWeek: isRaceWeek)
                    workouts.append(w)
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

            let focus: String = if isRaceWeek { "Race week — short, sharp, and rested." }
                else if isBase { "Base building. All easy. Let the body adapt." }
                else if isTaper { "Taper. Volume drops, sharpness stays." }
                else if isCutback(index) { "Cutback week. Absorb the last three." }
                else { quality == .intervals ? "Build week with intervals." : "Build week with a tempo run." }

            weeks.append(PlannedWeek(number: index + 1, startDate: weekStart, days: days, focus: focus))
        }

        return TrainingPlan(createdAt: .now, goal: runner.goal, raceDate: runner.raceDate, weeks: weeks, paces: paces)
    }

    // MARK: - Volume

    private var taperWeeks: Int { runner.goal == .marathon ? 2 : 1 }

    private func isCutback(_ index: Int) -> Bool { index > 0 && (index + 1) % 4 == 0 }

    /// Weekly mileage target per week.
    private func weeklyVolumes(weeks: Int) -> [Double] {
        let days = Double(runner.runDaysPerWeek)
        let start = max(runner.currentWeeklyMiles, 3 * days)
        let peakCap: Double = switch runner.goal {
        case .fiveK: 12 + 3 * days
        case .tenK: 16 + 4 * days
        case .half: 20 + 5 * days
        case .marathon: 26 + 6 * days
        }
        var result: [Double] = []
        var current = start
        for index in 0..<weeks {
            let isRaceWeek = index == weeks - 1
            let isTaper = !isRaceWeek && index >= weeks - 1 - taperWeeks && weeks > 6
            if isRaceWeek {
                result.append(current * (runner.goal == .marathon ? 0.3 : 0.45))
            } else if isTaper {
                // Two-week tapers step down: 75% then 60%.
                let weeksOut = weeks - 1 - index
                result.append(current * (weeksOut == 1 ? (taperWeeks == 2 ? 0.6 : 0.7) : 0.75))
            } else if isCutback(index) {
                result.append(current * 0.8)
            } else {
                result.append(current)
                current = min(current * 1.08, peakCap)
            }
        }
        return result
    }

    // MARK: - Scheduling

    /// Which run lands on which weekday. Respects lifting days and the long-run preference.
    private func daySchedule(quality: WorkoutType?, isRaceWeek: Bool) -> [Weekday: WorkoutType] {
        let raceDay = Weekday(date: runner.raceDate)
        var schedule: [Weekday: WorkoutType] = [:]

        if isRaceWeek {
            schedule[raceDay] = .race
            // Shakeout the day before, unless the race is Monday (that day is last week).
            if raceDay.index >= 1 {
                schedule[Weekday.ordered[raceDay.index - 1]] = .shakeout
            }
            var easyDays = runner.runDaysPerWeek - 2
            for day in Weekday.ordered where easyDays > 0 && day.index < raceDay.index - 1 && !runner.strengthDays.contains(day) {
                schedule[day] = .easy
                easyDays -= 1
            }
            return schedule
        }

        let lifting = runner.strengthDays
        let dayAfterLift = Set(lifting.map { Weekday.ordered[($0.index + 1) % 7] })

        // Long run: preferred day unless she lifts that day; then the nearest free day.
        let longDay = bestDay(preferring: runner.longRunDay, avoidTiers: [lifting.union(dayAfterLift), lifting], taken: [])
        schedule[longDay] = .long

        // Quality: mid-week, at least two days from the long run, not on/after a lift.
        var taken: Set<Weekday> = [longDay]
        if let quality {
            let preferred = Weekday.ordered[(longDay.index + 4) % 7]
            let buffer = Set([-1, 0, 1].map { Weekday.ordered[(longDay.index + $0 + 7) % 7] })
            // Loosen constraints one at a time: first give up the long-run buffer, then the
            // day-after-lift rule. A hard run on a lifting day itself is the last resort.
            let q = bestDay(preferring: preferred, avoidTiers: [lifting.union(dayAfterLift).union(buffer), lifting.union(dayAfterLift), lifting], taken: taken)
            schedule[q] = quality
            taken.insert(q)
        }

        // Easy runs fill remaining days, spreading out. Free days first, then lifting days.
        var remaining = runner.runDaysPerWeek - schedule.count
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
        // Put mobility on the two rest days adjacent to the hardest sessions.
        let routine: Routine? = if schedule[Weekday.ordered[(weekday.index + 6) % 7]] == .long {
            RoutineLibrary.hipMobility
        } else if schedule[Weekday.ordered[(weekday.index + 6) % 7]].map({ $0 == .intervals || $0 == .tempo }) == true {
            RoutineLibrary.calfAnkle
        } else { nil }

        if let routine {
            return Workout(type: .mobility, title: routine.title, summary: routine.purpose, standaloneRoutineID: routine.id)
        }
        return .rest
    }

    private func workout(type: WorkoutType, weekMiles: Double, paces: PaceProfile, weekIndex: Int, totalWeeks: Int, quality: WorkoutType?, isTaper: Bool, isRaceWeek: Bool = false) -> Workout {
        let runDays = Double(runner.runDaysPerWeek)
        // Marathon long runs carry a bigger share of the week; that's the whole point of the build.
        let longShare: Double = runner.goal == .marathon ? 0.45 : (runDays <= 3 ? 0.4 : 0.33)
        let longMiles = min(weekMiles * longShare, runner.goal.longRunCapMiles)
        let progress = Double(weekIndex) / Double(max(1, totalWeeks - 1))
        // Speed work shrinks in the taper so the week's total actually drops.
        let qualityScale = isTaper ? 0.6 : 1.0

        // Easy days soak up whatever volume the long run and quality session don't.
        let qualityMiles: Double = if let quality, quality != type {
            Units.miles(workout(type: quality, weekMiles: weekMiles, paces: paces, weekIndex: weekIndex, totalWeeks: totalWeeks, quality: nil, isTaper: isTaper).plannedMeters)
        } else { 0 }
        let easyDays = max(1, runDays - 1 - (quality == nil ? 0 : 1))
        var easyMiles = max(2, (weekMiles - longMiles - qualityMiles) / easyDays)
        if isRaceWeek { easyMiles = min(easyMiles, 3) }

        let warmupJog = Segment(kind: .warmup, name: "Warm-up jog", goal: .time(8 * 60), pace: PaceRange(fast: paces.easy.fast, slow: paces.easy.slow + 60))
        let cooldownJog = Segment(kind: .cooldown, name: "Cool-down jog", goal: .time(5 * 60), pace: PaceRange(fast: paces.easy.fast, slow: paces.easy.slow + 90))

        switch type {
        case .easy:
            let miles = roundHalf(easyMiles)
            return Workout(
                type: .easy,
                title: "Easy \(fmt(miles)) mi",
                summary: "Conversational pace. If you can't chat, slow down. These miles build the engine.",
                segments: [
                    Segment(kind: .warmup, name: "Walk & drills", goal: .time(4 * 60), pace: nil),
                    Segment(kind: .work, name: "Easy run", goal: .distance(Units.meters(miles: miles)), pace: paces.easy),
                    Segment(kind: .cooldown, name: "Walk", goal: .time(3 * 60), pace: nil),
                ],
                plannedMeters: Units.meters(miles: miles),
                preRoutineID: RoutineLibrary.dynamicWarmup.id,
                postRoutineID: RoutineLibrary.cooldown.id
            )

        case .long:
            let miles = roundHalf(longMiles)
            return Workout(
                type: .long,
                title: "Long run \(fmt(miles)) mi",
                summary: "Relaxed and steady. Start slower than feels necessary. Bring water past 6 miles.",
                segments: [
                    Segment(kind: .warmup, name: "Walk & drills", goal: .time(4 * 60), pace: nil),
                    Segment(kind: .work, name: "Long run", goal: .distance(Units.meters(miles: miles)), pace: paces.long),
                    Segment(kind: .cooldown, name: "Walk", goal: .time(5 * 60), pace: nil),
                ],
                plannedMeters: Units.meters(miles: miles),
                preRoutineID: RoutineLibrary.dynamicWarmup.id,
                postRoutineID: RoutineLibrary.cooldown.id
            )

        case .tempo:
            let tempoMinutes = ((15 + progress * 15) * qualityScale).rounded() // 15 → 30 min
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
            let repMeters: Double = runner.goal == .fiveK ? 400 : 800
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
            return Workout(
                type: .shakeout,
                title: "Shakeout 2 mi",
                summary: "Very easy, with a few short pickups to remind the legs what fast feels like.",
                segments: [
                    Segment(kind: .work, name: "Easy jog", goal: .distance(Units.meters(miles: 2)), pace: PaceRange(fast: paces.easy.fast, slow: paces.easy.slow + 30)),
                ],
                plannedMeters: Units.meters(miles: 2),
                preRoutineID: RoutineLibrary.dynamicWarmup.id,
                postRoutineID: RoutineLibrary.cooldown.id
            )

        case .race:
            return Workout(
                type: .race,
                title: "\(runner.goal.name) Race",
                summary: "Trust the training. First mile controlled, settle in, empty the tank in the last quarter.",
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
