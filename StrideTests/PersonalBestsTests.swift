import Testing
import Foundation
@testable import Stride

struct PersonalBestsTests {
    static let calendar = PlanGeneratorTests.calendar
    static func date(_ y: Int, _ m: Int, _ d: Int) -> Date { PlanGeneratorTests.date(y, m, d) }

    static func run(_ miles: Double, pace: Pace, on date: Date, splits: [TimeInterval] = [], type: WorkoutType = .easy) -> ActivityRecord {
        ActivityRecord(
            date: date, type: type, durationSeconds: miles * pace, meters: Units.meters(miles: miles),
            splits: splits.enumerated().map { ActivityRecord.Split(mile: $0.offset + 1, seconds: $0.element) }
        )
    }

    @Test func noRunsMeansNoBests() {
        let lift = ActivityRecord(date: Self.date(2026, 10, 1), type: .strength, durationSeconds: 1800, meters: 0)
        let bests = PersonalBests(activities: [lift], calendar: Self.calendar)
        #expect(bests.isEmpty)
        #expect(bests.biggestWeek == nil)
        #expect(bests.fastestPace.isEmpty)
    }

    @Test func longestRunAndFastestMile() {
        let short = Self.run(3, pace: 540, on: Self.date(2026, 10, 1), splits: [530, 540, 550])
        let long = Self.run(8, pace: 600, on: Self.date(2026, 10, 4), splits: [600, 590, 600])
        let bests = PersonalBests(activities: [long, short], calendar: Self.calendar)
        #expect(bests.longestRun?.activityID == long.id)
        #expect(bests.longestRun?.value == long.meters)
        #expect(bests.fastestMile?.activityID == short.id)
        #expect(bests.fastestMile?.value == 530)
    }

    @Test func gpsJumpIsNotAMile() {
        let glitchy = Self.run(3, pace: 540, on: Self.date(2026, 10, 1), splits: [95, 540, 545])
        let bests = PersonalBests(activities: [glitchy], calendar: Self.calendar)
        #expect(bests.fastestMile?.value == 540)
    }

    @Test func fastestPaceCountsOnlyRunsLongEnough() {
        let quickTwo = Self.run(2, pace: 480, on: Self.date(2026, 10, 1))
        let fiveK = Self.run(Units.miles(5000) * 0.99, pace: 520, on: Self.date(2026, 10, 3)) // GPS a little short
        let tenK = Self.run(6.3, pace: 560, on: Self.date(2026, 10, 5))
        let bests = PersonalBests(activities: [quickTwo, fiveK, tenK], calendar: Self.calendar)
        #expect(bests.fastestPace[.fiveK]?.activityID == fiveK.id)
        #expect(bests.fastestPace[.tenK]?.activityID == tenK.id)
        #expect(bests.fastestPace[.half] == nil)
        #expect(abs((bests.fastestPace[.fiveK]?.value ?? 0) - 520) < 0.001)
    }

    @Test func earlierRunKeepsATiedRecord() {
        let first = Self.run(5, pace: 600, on: Self.date(2026, 10, 1))
        let second = Self.run(5, pace: 600, on: Self.date(2026, 10, 8))
        let bests = PersonalBests(activities: [second, first], calendar: Self.calendar)
        #expect(bests.longestRun?.activityID == first.id)
        #expect(bests.fastestPace[.fiveK]?.activityID == first.id)
    }

    @Test func biggestWeekAddsUpMondayToSunday() throws {
        // Mon 5 Oct – Sun 11 Oct 2026: 3 + 4 + 6 = 13 mi. The week before: one 10-miler.
        let acts = [
            Self.run(10, pace: 600, on: Self.date(2026, 9, 30)),
            Self.run(3, pace: 600, on: Self.date(2026, 10, 5)),
            Self.run(4, pace: 600, on: Self.date(2026, 10, 7)),
            Self.run(6, pace: 600, on: Self.date(2026, 10, 11)),
            Self.run(5, pace: 600, on: Self.date(2026, 10, 12)), // next Monday
        ]
        let bests = PersonalBests(activities: acts, calendar: Self.calendar)
        let week = try #require(bests.biggestWeek)
        #expect(abs(Units.miles(week.value) - 13) < 0.001)
        #expect(Self.calendar.isDate(week.date, inSameDayAs: Self.date(2026, 10, 5)))
        #expect(week.activityID == nil)
    }

    @Test func titlesNameEveryRecordARunHolds() {
        let star = Self.run(6.3, pace: 500, on: Self.date(2026, 10, 1), splits: [490, 500, 505, 500, 500, 505])
        let slow = Self.run(2, pace: 620, on: Self.date(2026, 10, 3), splits: [620, 620])
        let bests = PersonalBests(activities: [star, slow], calendar: Self.calendar)
        #expect(bests.titles(for: star.id) == ["Longest run", "Fastest mile", "Fastest 5K or longer", "Fastest 10K or longer"])
        #expect(bests.titles(for: slow.id).isEmpty)
    }
}
