import Foundation
import HealthKit
import CoreLocation
import Observation
import WatchKit

/// Runs a workout on the wrist: keeps the session alive in the background via HealthKit,
/// measures distance with GPS + HealthKit, steps through segments, and taps the wrist
/// when pace drifts outside the target window.
@Observable
@MainActor
final class WorkoutManager: NSObject {
    enum Phase: Equatable { case idle, running, paused, finished }
    enum Coaching: Equatable { case none, speedUp, slowDown, onPace }

    // Live state
    var phase: Phase = .idle
    var workout: Workout?
    var segmentIndex = 0
    var elapsed: TimeInterval = 0
    var segmentElapsed: TimeInterval = 0
    var distance: Double = 0            // meters, whole run
    var segmentDistance: Double = 0     // meters, current segment
    var heartRate: Double?
    var currentPace: Pace?              // sec/mi over the last ~30 s
    var coaching: Coaching = .none
    var completed: ActivityRecord?
    /// Most recent mile split, shown briefly in place of the segment name.
    var lastSplit: ActivityRecord.Split?
    var splitBannerUntil: Date = .distantPast
    /// True while paused because she stopped moving (traffic light, shoelace). Resumes on its own.
    var autoPaused = false
    var autoPauseEnabled = true
    private var movingUpdates = 0
    private var countdownFired: Set<Int> = []

    // HealthKit
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    /// Collects GPS fixes so the run shows a map in Fitness / Health.
    private var routeBuilder: HKWorkoutRouteBuilder?

    // Location — a second, independent distance source that works in more places.
    private let locationManager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var gpsDistance: Double = 0
    private var hkDistance: Double = 0

    // Pace estimation
    private var samples: [(time: Date, distance: Double)] = []
    private var lastAlert: Date = .distantPast
    private var segmentStartDistance: Double = 0
    private var segmentStartElapsed: TimeInterval = 0
    private var splits: [ActivityRecord.Split] = []
    private var startDate: Date?
    private var accumulatedBeforePause: TimeInterval = 0
    private var resumedAt: Date?
    private var timer: Timer?
    private var heartRateSamples: [Double] = []

    var segment: Segment? {
        guard let workout, segmentIndex < workout.segments.count else { return nil }
        return workout.segments[segmentIndex]
    }

    var nextSegment: Segment? {
        guard let workout, segmentIndex + 1 < workout.segments.count else { return nil }
        return workout.segments[segmentIndex + 1]
    }

    /// 0…1 through the current segment, when it has a measurable goal.
    var segmentProgress: Double? {
        guard let segment else { return nil }
        switch segment.goal {
        case .time(let t): return min(1, segmentElapsed / t)
        case .distance(let m): return min(1, segmentDistance / m)
        case .open: return nil
        }
    }

    var segmentRemainingText: String {
        guard let segment else { return "" }
        switch segment.goal {
        case .time(let t): return Formatting.duration(max(0, t - segmentElapsed))
        case .distance(let m): return Formatting.miles(max(0, m - segmentDistance), decimals: 2)
        case .open: return Formatting.miles(distance, decimals: 2)
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType(),
                                        HKSeriesType.workoutRoute(),
                                        HKQuantityType(.distanceWalkingRunning),
                                        HKQuantityType(.activeEnergyBurned)]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate),
                                       HKQuantityType(.distanceWalkingRunning),
                                       HKQuantityType(.activeEnergyBurned)]
        _ = try? await healthStore.requestAuthorization(toShare: share, read: read)
        locationManager.requestWhenInUseAuthorization()
    }

    // MARK: - Lifecycle

    func start(_ workout: Workout) {
        guard phase == .idle || phase == .finished else { return }
        reset()
        self.workout = workout
        phase = .running
        startDate = .now
        resumedAt = .now

        let config = HKWorkoutConfiguration()
        config.activityType = .running
        config.locationType = .outdoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            self.routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
            session.startActivity(with: .now)
            builder.beginCollection(withStart: .now) { _, _ in }
        } catch {
            print("Stride: could not start HK session — \(error)")
        }

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness
        // No allowsBackgroundLocationUpdates here: on watchOS it asserts without a
        // location background mode, and the HK workout session already keeps us alive.
        locationManager.startUpdatingLocation()

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        WKInterfaceDevice.current().play(.start)
    }

    func togglePause() {
        autoPaused = false
        switch phase {
        case .running:
            phase = .paused
            if let resumedAt { accumulatedBeforePause += Date.now.timeIntervalSince(resumedAt) }
            resumedAt = nil
            session?.pause()
            WKInterfaceDevice.current().play(.stop)
        case .paused:
            phase = .running
            resumedAt = .now
            samples.removeAll()
            session?.resume()
            WKInterfaceDevice.current().play(.start)
        default: break
        }
    }

    /// Skip to the next segment (e.g. warm-up felt long enough).
    func advanceSegment() {
        guard let workout else { return }
        if segmentIndex + 1 < workout.segments.count {
            segmentIndex += 1
            segmentStartDistance = distance
            segmentStartElapsed = elapsed
            segmentDistance = 0
            segmentElapsed = 0
            coaching = .none
            countdownFired = []
            lastAlert = .now // grace period before coaching kicks in
            WKInterfaceDevice.current().play(.notification)
        } else {
            end()
        }
    }

    func end() {
        guard phase == .running || phase == .paused else { return }
        if phase == .running, let resumedAt { accumulatedBeforePause += Date.now.timeIntervalSince(resumedAt) }
        timer?.invalidate()
        timer = nil
        locationManager.stopUpdatingLocation()
        phase = .finished

        let record = ActivityRecord(
            date: startDate ?? .now,
            type: workout?.type ?? .easy,
            plannedWorkoutID: workout?.id,
            durationSeconds: accumulatedBeforePause,
            meters: distance,
            averageHeartRate: heartRateSamples.isEmpty ? nil : heartRateSamples.reduce(0, +) / Double(heartRateSamples.count),
            splits: splits
        )
        completed = record

        session?.end()
        let routeBuilder = self.routeBuilder
        builder?.endCollection(withEnd: .now) { [weak self] _, _ in
            self?.builder?.finishWorkout { workout, _ in
                // Attach the route once the workout exists in Health.
                if let workout {
                    routeBuilder?.finishRoute(with: workout, metadata: nil) { _, _ in }
                } else {
                    routeBuilder?.discard()
                }
            }
        }
        WKInterfaceDevice.current().play(.success)
    }

    func discard() {
        reset()
        phase = .idle
    }

    private func reset() {
        workout = nil
        segmentIndex = 0
        elapsed = 0
        segmentElapsed = 0
        distance = 0
        segmentDistance = 0
        gpsDistance = 0
        hkDistance = 0
        heartRate = nil
        currentPace = nil
        coaching = .none
        completed = nil
        lastSplit = nil
        splitBannerUntil = .distantPast
        autoPaused = false
        movingUpdates = 0
        countdownFired = []
        samples = []
        splits = []
        heartRateSamples = []
        lastLocation = nil
        segmentStartDistance = 0
        segmentStartElapsed = 0
        accumulatedBeforePause = 0
        resumedAt = nil
        startDate = nil
        lastAlert = .distantPast
        session = nil
        builder = nil
        routeBuilder = nil
    }

    // MARK: - Every second

    private func tick() {
        guard phase == .running, let resumedAt else { return }
        elapsed = accumulatedBeforePause + Date.now.timeIntervalSince(resumedAt)
        segmentElapsed = elapsed - segmentStartElapsed

        // Prefer whichever source has seen more ground — GPS in open sky, HK indoors/under trees.
        distance = max(gpsDistance, hkDistance)
        segmentDistance = distance - segmentStartDistance

        updatePace()
        recordSplitIfNeeded()
        coach()
        countdownIfNeeded()
        autoAdvanceIfNeeded()
        autoPauseIfStationary()
    }

    /// Three quick taps as a timed segment runs out, one tap 30 m before a distance rep ends.
    private func countdownIfNeeded() {
        guard let segment else { return }
        switch segment.goal {
        case .time(let t):
            let remaining = Int((t - segmentElapsed).rounded(.up))
            if (1...3).contains(remaining), !countdownFired.contains(remaining) {
                countdownFired.insert(remaining)
                WKInterfaceDevice.current().play(.click)
            }
        case .distance(let m) where segment.kind == .work && m <= 1609:
            if m - segmentDistance <= 30, !countdownFired.contains(0) {
                countdownFired.insert(0)
                WKInterfaceDevice.current().play(.click)
            }
        default: break
        }
    }

    /// Under 3 m covered in the last 8 s → pause. Only while a segment expects her to be
    /// running (not during standing warm-up drills or the cool-down stretch), and not in the
    /// first 20 s after a start or resume, when distance sources are still catching up.
    private func autoPauseIfStationary() {
        guard autoPauseEnabled, let segment, segment.kind == .work || segment.kind == .recovery,
              let resumedAt, Date.now.timeIntervalSince(resumedAt) > 20,
              let last = samples.last else { return }
        let cutoff = Date.now.addingTimeInterval(-8)
        guard let ref = samples.first(where: { $0.time >= cutoff }),
              last.time.timeIntervalSince(ref.time) >= 6 else { return }
        if last.distance - ref.distance < 3 {
            movingUpdates = 0
            togglePause()
            autoPaused = true
        }
    }

    private func updatePace() {
        let now = Date.now
        samples.append((now, distance))
        samples.removeAll { now.timeIntervalSince($0.time) > 30 }
        guard let first = samples.first, samples.count >= 5 else { currentPace = nil; return }
        let dt = now.timeIntervalSince(first.time)
        let dd = distance - first.distance
        guard dt > 10, dd > 15 else { currentPace = nil; return }
        let pace = dt / Units.miles(dd)
        // Light smoothing so the number doesn't jitter.
        currentPace = currentPace.map { $0 * 0.6 + pace * 0.4 } ?? pace
    }

    private func recordSplitIfNeeded() {
        let mile = Int(Units.miles(distance))
        if mile > splits.count {
            let previous = splits.last.map { total(of: $0) } ?? 0
            let split = ActivityRecord.Split(mile: mile, seconds: elapsed - previous)
            splits.append(split)
            lastSplit = split
            splitBannerUntil = Date.now.addingTimeInterval(8)
            WKInterfaceDevice.current().play(.notification)
        }
    }

    private func total(of split: ActivityRecord.Split) -> TimeInterval {
        splits.prefix(split.mile).reduce(0) { $0 + $1.seconds }
    }

    /// The core feature: compare rolling pace to the segment's window and nudge.
    private func coach() {
        guard let segment, let target = segment.pace, let pace = currentPace else {
            coaching = .none
            return
        }
        // Give her 20 s after a segment change to settle before judging.
        guard segmentElapsed > 20 else { coaching = .none; return }

        let newCoaching: Coaching
        if pace < target.fast - 3 {
            newCoaching = .slowDown
        } else if pace > target.slow + 3 {
            newCoaching = .speedUp
        } else {
            newCoaching = .onPace
        }
        let changed = newCoaching != coaching
        coaching = newCoaching

        // Haptic: immediately on a change, then every 20 s while still off pace.
        guard newCoaching == .speedUp || newCoaching == .slowDown else { return }
        if changed || Date.now.timeIntervalSince(lastAlert) > 20 {
            lastAlert = .now
            WKInterfaceDevice.current().play(newCoaching == .speedUp ? .directionUp : .directionDown)
        }
    }

    private func autoAdvanceIfNeeded() {
        guard let segment else { return }
        switch segment.goal {
        case .time(let t) where segmentElapsed >= t: advanceSegment()
        case .distance(let m) where segmentDistance >= m: advanceSegment()
        default: break
        }
    }
}

// MARK: - HealthKit delegates

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("Stride: HK session error — \(error)")
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        var hr: Double?
        var dist: Double?
        for type in collectedTypes {
            guard let qt = type as? HKQuantityType, let stats = workoutBuilder.statistics(for: qt) else { continue }
            switch qt {
            case HKQuantityType(.heartRate):
                hr = stats.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            case HKQuantityType(.distanceWalkingRunning):
                dist = stats.sumQuantity()?.doubleValue(for: .meter())
            default: break
            }
        }
        Task { @MainActor in
            if let hr {
                self.heartRate = hr
                self.heartRateSamples.append(hr)
            }
            if let dist { self.hkDistance = dist }
        }
    }
}

// MARK: - Location

extension WorkoutManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            if autoPaused, phase == .paused {
                // Two consecutive fixes above walking speed and we're back.
                if let speed = locations.last?.speed, speed > 1.0 {
                    movingUpdates += 1
                    if movingUpdates >= 2 { togglePause() }
                } else {
                    movingUpdates = 0
                }
                return
            }
            guard phase == .running else { return }
            let good = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy < 30 }
            for loc in good {
                if let last = lastLocation {
                    let d = loc.distance(from: last)
                    if d > 1 { gpsDistance += d }
                }
                lastLocation = loc
            }
            if !good.isEmpty {
                routeBuilder?.insertRouteData(good) { _, _ in }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
