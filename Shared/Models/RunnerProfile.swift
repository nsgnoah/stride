import Foundation

/// What the runner tells us during setup. Everything the planner needs.
struct RunnerProfile: Codable, Hashable, Sendable {
    var goal: GoalDistance = .tenK
    var raceDate: Date = Calendar.current.date(byAdding: .weekOfYear, value: 10, to: .now)!
    /// False when she just wants to build up to the distance; the planner then picks the
    /// length and `raceDate` becomes the goal day it worked out.
    var hasRaceDate: Bool = false
    /// The weekdays she runs. Empty only for plans made before days could be chosen; the
    /// planner then places `runDaysPerWeek` runs itself.
    var runDays: Set<Weekday> = [.tuesday, .thursday, .saturday]
    var runDaysPerWeek: Int = 3
    /// Days she lifts. Hard runs avoid these and the day after; they show up in the week view.
    var strengthDays: Set<Weekday> = []
    /// Preferred long run day.
    var longRunDay: Weekday = .saturday
    /// How far she can comfortably run today, miles. Week one's longest run; everything grows from it.
    var longestComfortableMiles: Double = 3
    /// One faster session a week (intervals / tempo) after the first two weeks.
    var includeSpeedWork: Bool = true
    /// Legacy: weekly mileage from the first version of setup. No longer used by the planner.
    var currentWeeklyMiles: Double = 10
    /// A recent effort used to estimate fitness.
    var recentRunMeters: Double = Units.meters(miles: 3)
    var recentRunSeconds: TimeInterval = 30 * 60

    /// Runs per week.
    var runCount: Int { runDays.isEmpty ? runDaysPerWeek : runDays.count }

    var weeksUntilRace: Int {
        hasRaceDate ? PlanGenerator.weekCount(from: .now, to: raceDate) : PlanGenerator.suggestedWeeks(for: self)
    }

    init() {}

    /// Profiles saved by earlier builds lack the newer fields; fill them in rather than
    /// failing to load (which would look like losing the plan).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        goal = try c.decode(GoalDistance.self, forKey: .goal)
        raceDate = try c.decode(Date.self, forKey: .raceDate)
        hasRaceDate = try c.decodeIfPresent(Bool.self, forKey: .hasRaceDate) ?? true
        runDaysPerWeek = try c.decodeIfPresent(Int.self, forKey: .runDaysPerWeek) ?? 3
        runDays = try c.decodeIfPresent(Set<Weekday>.self, forKey: .runDays) ?? []
        strengthDays = try c.decodeIfPresent(Set<Weekday>.self, forKey: .strengthDays) ?? []
        longRunDay = try c.decodeIfPresent(Weekday.self, forKey: .longRunDay) ?? .saturday
        currentWeeklyMiles = try c.decodeIfPresent(Double.self, forKey: .currentWeeklyMiles) ?? 10
        recentRunMeters = try c.decodeIfPresent(Double.self, forKey: .recentRunMeters) ?? Units.meters(miles: 3)
        recentRunSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .recentRunSeconds) ?? 30 * 60
        includeSpeedWork = try c.decodeIfPresent(Bool.self, forKey: .includeSpeedWork) ?? true
        // The recent run she entered is a distance she has actually covered.
        let fallback = min(6, max(1, (Units.miles(recentRunMeters) * 2).rounded() / 2))
        longestComfortableMiles = try c.decodeIfPresent(Double.self, forKey: .longestComfortableMiles) ?? fallback
    }
}

/// Something that actually happened: a run recorded on the watch, or a lift she logged.
struct ActivityRecord: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var date: Date
    var type: WorkoutType
    var plannedWorkoutID: UUID?
    var durationSeconds: TimeInterval
    var meters: Double
    var averageHeartRate: Double?
    var splits: [Split] = []
    var notes: String = ""
    /// Set when the record was imported from a workout in Apple Health (not recorded by Stride).
    var healthKitID: UUID?

    var averagePace: Pace? {
        guard meters > 0 else { return nil }
        return durationSeconds / Units.miles(meters)
    }

    struct Split: Codable, Hashable, Sendable {
        var mile: Int
        var seconds: TimeInterval
    }
}
