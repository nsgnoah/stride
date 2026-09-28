import Foundation

enum GoalDistance: String, Codable, CaseIterable, Identifiable, Sendable {
    case fiveK, tenK, half, marathon

    var id: String { rawValue }

    var name: String {
        switch self {
        case .fiveK: "5K"
        case .tenK: "10K"
        case .half: "Half Marathon"
        case .marathon: "Marathon"
        }
    }

    var meters: Double {
        switch self {
        case .fiveK: 5000
        case .tenK: 10000
        case .half: 21_097.5
        case .marathon: 42_195
        }
    }

    var defaultWeeks: Int {
        switch self {
        case .fiveK: 8
        case .tenK: 10
        case .half: 12
        case .marathon: 16
        }
    }

    /// Longest long run the plan will schedule, in miles.
    var longRunCapMiles: Double {
        switch self {
        case .fiveK: 6
        case .tenK: 8
        case .half: 12
        case .marathon: 20
        }
    }
}

enum Weekday: Int, Codable, CaseIterable, Identifiable, Comparable, Sendable {
    case monday = 2, tuesday, wednesday, thursday, friday, saturday, sunday = 1

    var id: Int { rawValue }

    /// Monday-first ordering for UI.
    static var ordered: [Weekday] {
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    }

    var index: Int { Weekday.ordered.firstIndex(of: self)! }

    static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.index < rhs.index }

    var shortName: String {
        switch self {
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        case .sunday: "Sun"
        }
    }

    var letter: String { String(shortName.prefix(1)) }

    init(date: Date, calendar: Calendar = .current) {
        self = Weekday(rawValue: calendar.component(.weekday, from: date))!
    }
}

enum WorkoutType: String, Codable, CaseIterable, Sendable {
    case easy, long, tempo, intervals, race, shakeout, strength, mobility, rest

    var name: String {
        switch self {
        case .easy: "Easy Run"
        case .long: "Long Run"
        case .tempo: "Tempo Run"
        case .intervals: "Intervals"
        case .race: "Race Day"
        case .shakeout: "Shakeout"
        case .strength: "Strength"
        case .mobility: "Mobility"
        case .rest: "Rest"
        }
    }

    var isRun: Bool {
        switch self {
        case .easy, .long, .tempo, .intervals, .race, .shakeout: true
        default: false
        }
    }

    var symbol: String {
        switch self {
        case .easy: "figure.run"
        case .long: "figure.run.circle"
        case .tempo: "gauge.with.needle"
        case .intervals: "timer"
        case .race: "flag.checkered"
        case .shakeout: "wind"
        case .strength: "dumbbell"
        case .mobility: "figure.flexibility"
        case .rest: "bed.double"
        }
    }
}

/// One piece of a run the watch guides you through.
struct Segment: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case warmup, work, recovery, cooldown
    }

    enum Goal: Codable, Hashable, Sendable {
        case time(TimeInterval)
        case distance(Double) // meters
        case open // until the runner ends it (race)
    }

    var id: UUID = UUID()
    var kind: Kind
    var name: String
    var goal: Goal
    var pace: PaceRange?

    var goalDescription: String {
        switch goal {
        case .time(let t): Formatting.minutes(t)
        case .distance(let m): Formatting.miles(m, decimals: m < Units.metersPerMile ? 2 : 1)
        case .open: "Until you stop"
        }
    }
}

struct Workout: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()

    /// A deterministic id for a slot in the plan, so rebuilding the plan (new paces, a
    /// tweaked schedule) keeps completed workouts matched to their records.
    static func stableID(_ key: String) -> UUID {
        // FNV-1a over the key, twice with different seeds, packed into 16 bytes. Not
        // cryptographic — it only has to be stable and collision-free within one plan.
        func fnv(_ s: String, seed: UInt64) -> UInt64 {
            var h: UInt64 = seed
            for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
            return h
        }
        let a = fnv(key, seed: 0xcbf29ce484222325)
        let b = fnv(key, seed: 0x84222325cbf29ce4)
        return UUID(uuid: (
            UInt8(truncatingIfNeeded: a >> 56), UInt8(truncatingIfNeeded: a >> 48), UInt8(truncatingIfNeeded: a >> 40), UInt8(truncatingIfNeeded: a >> 32),
            UInt8(truncatingIfNeeded: a >> 24), UInt8(truncatingIfNeeded: a >> 16), UInt8(truncatingIfNeeded: a >> 8), UInt8(truncatingIfNeeded: a),
            UInt8(truncatingIfNeeded: b >> 56), UInt8(truncatingIfNeeded: b >> 48), UInt8(truncatingIfNeeded: b >> 40), UInt8(truncatingIfNeeded: b >> 32),
            UInt8(truncatingIfNeeded: b >> 24), UInt8(truncatingIfNeeded: b >> 16), UInt8(truncatingIfNeeded: b >> 8), UInt8(truncatingIfNeeded: b)
        ))
    }
    var type: WorkoutType
    var title: String
    var summary: String
    var segments: [Segment] = []
    /// Estimated distance for the run portion (meters), used for weekly totals.
    var plannedMeters: Double = 0
    var preRoutineID: String?
    var postRoutineID: String?
    var standaloneRoutineID: String?

    var estimatedDuration: TimeInterval {
        segments.reduce(0) { total, seg in
            switch seg.goal {
            case .time(let t): total + t
            case .distance(let m):
                total + (seg.pace.map { $0.midpoint * Units.miles(m) } ?? Units.miles(m) * 600)
            case .open: total
            }
        }
    }

    var mainPace: PaceRange? {
        segments.first(where: { $0.kind == .work })?.pace
    }
}

struct PlannedDay: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var date: Date
    var workouts: [Workout]

    var weekday: Weekday { Weekday(date: date) }
    var isRestDay: Bool { workouts.allSatisfy { $0.type == .rest } }
    var plannedMeters: Double { workouts.reduce(0) { $0 + $1.plannedMeters } }
}

struct PlannedWeek: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var number: Int
    var startDate: Date
    var days: [PlannedDay]
    var focus: String

    var plannedMeters: Double { days.reduce(0) { $0 + $1.plannedMeters } }
    var runCount: Int { days.flatMap(\.workouts).filter { $0.type.isRun }.count }
}

struct TrainingPlan: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var createdAt: Date
    var goal: GoalDistance
    var raceDate: Date
    var weeks: [PlannedWeek]
    var paces: PaceProfile
    /// Workouts she chose to skip. Lives on the plan so it syncs to the watch with it.
    var skipped: Set<UUID> = []

    init(id: UUID = UUID(), createdAt: Date, goal: GoalDistance, raceDate: Date, weeks: [PlannedWeek], paces: PaceProfile, skipped: Set<UUID> = []) {
        self.id = id
        self.createdAt = createdAt
        self.goal = goal
        self.raceDate = raceDate
        self.weeks = weeks
        self.paces = paces
        self.skipped = skipped
    }

    private enum CodingKeys: String, CodingKey { case id, createdAt, goal, raceDate, weeks, paces, skipped }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        goal = try c.decode(GoalDistance.self, forKey: .goal)
        raceDate = try c.decode(Date.self, forKey: .raceDate)
        weeks = try c.decode([PlannedWeek].self, forKey: .weeks)
        paces = try c.decode(PaceProfile.self, forKey: .paces)
        skipped = try c.decodeIfPresent(Set<UUID>.self, forKey: .skipped) ?? []
    }

    var allDays: [PlannedDay] { weeks.flatMap(\.days) }

    var startDate: Date? { weeks.first?.startDate }

    func isSkipped(_ workout: Workout) -> Bool { skipped.contains(workout.id) }

    /// Moves a workout to another day inside the plan. A rest placeholder on the target day
    /// gives way; anything else (a lift, another run) shares the day.
    mutating func move(workoutID: UUID, to date: Date, calendar: Calendar = .current) {
        var moved: Workout?
        for w in weeks.indices {
            for d in weeks[w].days.indices {
                if let i = weeks[w].days[d].workouts.firstIndex(where: { $0.id == workoutID }) {
                    moved = weeks[w].days[d].workouts.remove(at: i)
                    if weeks[w].days[d].workouts.isEmpty {
                        weeks[w].days[d].workouts = [Workout(type: .rest, title: "Rest", summary: "Recovery is training. Walk, sleep, eat well.")]
                    }
                }
            }
        }
        guard let moved else { return }
        for w in weeks.indices {
            for d in weeks[w].days.indices where calendar.isDate(weeks[w].days[d].date, inSameDayAs: date) {
                weeks[w].days[d].workouts.removeAll { $0.type == .rest }
                weeks[w].days[d].workouts.append(moved)
                skipped.remove(workoutID)
                return
            }
        }
    }

    func day(on date: Date, calendar: Calendar = .current) -> PlannedDay? {
        allDays.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    func week(containing date: Date, calendar: Calendar = .current) -> PlannedWeek? {
        weeks.first { week in
            week.days.contains { calendar.isDate($0.date, inSameDayAs: date) }
        }
    }

    func workout(id: UUID) -> Workout? {
        allDays.flatMap(\.workouts).first { $0.id == id }
    }
}

/// Training paces derived from the runner's current fitness, seconds per mile.
struct PaceProfile: Codable, Hashable, Sendable {
    var easy: PaceRange
    var long: PaceRange
    var tempo: PaceRange
    var interval: PaceRange
    var race: PaceRange

    func range(for type: WorkoutType) -> PaceRange? {
        switch type {
        case .easy, .shakeout: easy
        case .long: long
        case .tempo: tempo
        case .intervals: interval
        case .race: race
        default: nil
        }
    }
}
