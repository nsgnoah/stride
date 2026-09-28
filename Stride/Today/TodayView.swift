import SwiftUI

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @State private var loggingLift = false
    @State private var buildingNext = false

    var body: some View {
        NavigationStack {
            List {
                if let week = displayWeek {
                    Section {
                        WeekStrip(week: week)
                        Text(week.focus).font(.subheadline).foregroundStyle(.secondary)
                    } header: {
                        if store.thisWeek == nil {
                            Text("Week 1 starts \(week.startDate.formatted(.dateTime.weekday(.wide)))")
                        } else {
                            Text("Week \(week.number) of \(store.plan?.weeks.count ?? 0)")
                        }
                    }
                }

                if store.activities.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Getting started", systemImage: "applewatch").font(.headline)
                            Text("Your plan is on your Apple Watch too — open Stride there and tap Start on run day. It walks you through the warm-up, coaches your pace, and sends the run back here.")
                            Text("Lifts and mobility can be checked off from the watch or from the day's screen here.")
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                        .padding(.vertical, 4)
                    }
                }

                if let today = store.today {
                    Section("Today") {
                        ForEach(today.workouts) { workout in
                            NavigationLink(value: workout) { WorkoutRow(workout: workout) }
                        }
                    }
                } else if let plan = store.plan, plan.raceDate < .now {
                    Section {
                        Text("Plan complete — nice work.")
                        Button("Build the next plan…") { buildingNext = true }
                    }
                }

                let missed = store.missedRuns
                if !missed.isEmpty {
                    Section {
                        ForEach(missed, id: \.workout.id) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                NavigationLink(value: item.workout) { WorkoutRow(workout: item.workout) }
                                HStack {
                                    Button("Do it today") { store.move(item.workout, to: .now) }
                                        .buttonStyle(.borderedProminent).controlSize(.small)
                                    Button("Skip") { store.skip(item.workout) }
                                        .buttonStyle(.bordered).controlSize(.small)
                                    Spacer()
                                    Text(item.day.date.formatted(.dateTime.weekday(.abbreviated)))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Missed")
                    } footer: {
                        Text("Skipping is fine — one missed run never broke a plan. Don't try to make up more than one.")
                    }
                }

                if let next = store.nextRun, !Calendar.current.isDateInToday(next.day.date) {
                    Section("Next run · \(next.day.date.formatted(.dateTime.weekday(.wide)))") {
                        NavigationLink(value: next.workout) { WorkoutRow(workout: next.workout) }
                    }
                }

                Section {
                    Button { loggingLift = true } label: {
                        Label("Log a lift or cross-training", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle("Today")
            .navigationDestination(for: Workout.self) { WorkoutDetailView(workout: $0) }
            .sheet(isPresented: $loggingLift) { LogActivityView() }
            .sheet(isPresented: $buildingNext) {
                NavigationStack {
                    PlanSetupView(existing: store.profile, startFresh: true,
                                  recentEffort: PaceCalculator.bestRecentEffort(in: store.activities))
                }
            }
        }
    }

    /// This week, or the first week if the plan hasn't started yet.
    private var displayWeek: PlannedWeek? {
        store.thisWeek ?? store.plan?.weeks.first { $0.startDate > .now }
    }
}

/// Seven dots across the top showing the shape of the week.
struct WeekStrip: View {
    @Environment(AppStore.self) private var store
    let week: PlannedWeek

    var body: some View {
        HStack(spacing: 4) {
            ForEach(week.days) { day in
                let isToday = Calendar.current.isDateInToday(day.date)
                let done = day.workouts.contains { store.isCompleted($0) }
                let main = day.workouts.first { $0.type.isRun } ?? day.workouts.first!
                VStack(spacing: 6) {
                    Text(day.weekday.letter)
                        .font(.caption2.weight(isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? .primary : .secondary)
                    ZStack {
                        Circle()
                            .fill(main.type == .rest ? Color(.tertiarySystemFill) : main.type.tint.opacity(done ? 1 : 0.25))
                        if day.workouts.count > 1 {
                            Circle().strokeBorder(Color.indigo, lineWidth: 2)
                        }
                        Image(systemName: done ? "checkmark" : main.type.symbol)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(done ? .white : main.type.tint)
                    }
                    .frame(width: 34, height: 34)
                    .overlay {
                        if isToday { Circle().strokeBorder(.primary, lineWidth: 1.5).padding(-3) }
                    }
                    Text(main.plannedMeters > 0 ? Units.miles(main.plannedMeters).formatted(.number.precision(.fractionLength(0...1))) : " ")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
    }
}

struct WorkoutDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let workout: Workout
    @State private var moving = false
    @State private var moveDate = Date.now
    @State private var loggingManually = false

    private var isSkipped: Bool { store.plan?.isSkipped(workout) == true }
    private var isDone: Bool { store.isCompleted(workout) }

    var body: some View {
        List {
            if isSkipped {
                Section {
                    Label("Skipped", systemImage: "forward.end")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(workout.type.name, systemImage: workout.type.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(workout.type.tint)
                    if !workout.summary.isEmpty {
                        Text(workout.summary)
                    }
                    if workout.type.isRun {
                        HStack(spacing: 16) {
                            stat("Distance", Formatting.miles(workout.plannedMeters))
                            stat("Time", "~" + Formatting.minutes(workout.estimatedDuration))
                            if let pace = workout.mainPace { stat("Pace", pace.formatted) }
                        }
                        .padding(.top, 4)
                    }
                }
            }

            if let activity = store.activity(for: workout) {
                Section("Done") {
                    LabeledContent("Distance", value: Formatting.miles(activity.meters, decimals: 2))
                    LabeledContent("Time", value: Formatting.duration(activity.durationSeconds))
                    if let pace = activity.averagePace { LabeledContent("Avg pace", value: pace.formattedPerMile) }
                    if let hr = activity.averageHeartRate { LabeledContent("Avg heart rate", value: "\(Int(hr)) bpm") }
                }
            }

            if let routine = RoutineLibrary.routine(workout.preRoutineID) {
                routineSection("Before", routine)
            }

            if !workout.segments.isEmpty {
                Section("On the watch") {
                    ForEach(workout.segments) { seg in
                        HStack {
                            Circle().fill(seg.kind.tint).frame(width: 8, height: 8)
                            Text(seg.name)
                            Spacer()
                            Text(seg.goalDescription).foregroundStyle(.secondary)
                            if let pace = seg.pace {
                                Text(pace.formatted).font(.caption).foregroundStyle(.secondary)
                                    .frame(width: 96, alignment: .trailing)
                            }
                        }
                        .font(.subheadline)
                    }
                }
            }

            if let routine = RoutineLibrary.routine(workout.postRoutineID) {
                routineSection("After", routine)
            }

            if let routine = RoutineLibrary.routine(workout.standaloneRoutineID) {
                routineSection(nil, routine)
            }

            if workout.type == .strength || workout.type == .mobility, !isDone {
                Section {
                    Button("Mark done") {
                        store.record(ActivityRecord(date: .now, type: workout.type, plannedWorkoutID: workout.id, durationSeconds: 0, meters: 0))
                    }
                }
            } else if workout.type.isRun, !isDone {
                Section {
                    Button("Log this run manually…") { loggingManually = true }
                } footer: {
                    Text("For runs done without the watch — a treadmill, a borrowed tracker, a dead battery.")
                }
            }
        }
        .navigationTitle(workout.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if workout.type != .rest, workout.type != .strength, !isDone {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Move to another day…", systemImage: "calendar") {
                            let current = store.plan?.date(of: workout.id) ?? .now
                            moveDate = planDateRange.map { min(max(current, $0.lowerBound), $0.upperBound) } ?? current
                            moving = true
                        }
                        if isSkipped {
                            Button("Put it back", systemImage: "arrow.uturn.backward") { store.unskip(workout) }
                        } else {
                            Button("Skip this one", systemImage: "forward.end", role: .destructive) { store.skip(workout) }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $loggingManually) {
            LogActivityView(prefill: workout, date: store.plan?.date(of: workout.id))
        }
        .sheet(isPresented: $moving) {
            NavigationStack {
                Form {
                    if let range = planDateRange {
                        DatePicker("New day", selection: $moveDate, in: range, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                    }
                    if let target = store.plan?.day(on: moveDate) {
                        Section("Already that day") {
                            ForEach(target.workouts) { w in
                                Label(w.title, systemImage: w.type.symbol).foregroundStyle(w.type.tint)
                            }
                        }
                    }
                }
                .navigationTitle("Move \(workout.type.name.lowercased())")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { moving = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Move") {
                            store.move(workout, to: moveDate)
                            moving = false
                            dismiss()
                        }
                        .bold()
                    }
                }
            }
            .presentationDetents([.large])
        }
    }

    private var planDateRange: ClosedRange<Date>? {
        guard let first = store.plan?.allDays.first?.date, let last = store.plan?.allDays.last?.date else { return nil }
        let today = Calendar.current.startOfDay(for: .now)
        return max(first, today)...last
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline)
        }
    }

    @ViewBuilder
    private func routineSection(_ heading: String?, _ routine: Routine) -> some View {
        Section {
            NavigationLink {
                RoutineView(routine: routine)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(routine.title).font(.headline)
                    Text("\(routine.minutes) min · \(routine.exercises.count) moves").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        } header: {
            if let heading { Text(heading) }
        }
    }
}


struct RoutineView: View {
    let routine: Routine

    var body: some View {
        List {
            Section {
                Text(routine.purpose).foregroundStyle(.secondary)
            }
            Section("\(routine.minutes) minutes") {
                ForEach(routine.exercises) { ex in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(ex.name).font(.headline)
                            Spacer()
                            Text(ex.dose).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Text(ex.detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle(routine.title)
    }
}

/// Manual entry for lifts and anything the watch didn't record.
struct LogActivityView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var type: WorkoutType
    @State private var minutes: Int
    @State private var miles: Double
    @State private var notes = ""
    /// When opened from a planned workout, the record is tied to that workout.
    private let prefill: Workout?

    init(prefill: Workout? = nil, date: Date? = nil) {
        self.prefill = prefill
        _date = State(initialValue: min(date ?? .now, .now))
        _type = State(initialValue: prefill?.type ?? .strength)
        _minutes = State(initialValue: prefill.map { max(5, Int($0.estimatedDuration / 60 / 5) * 5) } ?? 45)
        _miles = State(initialValue: prefill.map { (Units.miles($0.plannedMeters) * 10).rounded() / 10 } ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let prefill {
                    LabeledContent("Workout", value: prefill.title)
                } else {
                    Picker("Type", selection: $type) {
                        Text("Strength").tag(WorkoutType.strength)
                        Text("Mobility").tag(WorkoutType.mobility)
                        Text("Easy run").tag(WorkoutType.easy)
                    }
                }
                DatePicker("When", selection: $date, in: ...Date.now, displayedComponents: [.date])
                Stepper("\(minutes) minutes", value: $minutes, in: 5...240, step: 5)
                if type.isRun {
                    HStack {
                        Text("Distance")
                        Spacer()
                        TextField("0", value: $miles, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 60)
                        Text("mi")
                    }
                }
                TextField("Notes", text: $notes, axis: .vertical)
            }
            .navigationTitle("Log activity")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let planned = prefill ?? store.plan?.day(on: date)?.workouts.first { $0.type == type && !store.isCompleted($0) }
                        store.record(ActivityRecord(date: date, type: type, plannedWorkoutID: planned?.id, durationSeconds: TimeInterval(minutes * 60), meters: Units.meters(miles: miles), notes: notes))
                        dismiss()
                    }
                }
            }
        }
    }
}
