import SwiftUI

/// What's on tap today, with a big start button. Falls back to a free run if there's no plan.
struct WatchHomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(WorkoutManager.self) private var manager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let next = store.nextRun {
                        let isToday = Calendar.current.isDateInToday(next.day.date)
                        Text(isToday ? "Today" : next.day.date.formatted(.dateTime.weekday(.wide)))
                            .font(.footnote).foregroundStyle(.secondary)
                        WorkoutCard(workout: next.workout)
                        Button {
                            manager.voiceEnabled = store.voiceCues
                            manager.start(next.workout)
                        } label: {
                            Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)

                        if let pre = RoutineLibrary.routine(next.workout.preRoutineID) {
                            NavigationLink {
                                WatchRoutineView(routine: pre)
                            } label: {
                                Label(pre.title, systemImage: "figure.flexibility")
                            }
                        }
                    } else if store.plan == nil {
                        Text("No plan — just run. Free run tracks pace, distance and mile splits.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("All planned runs done. Nice.").foregroundStyle(.secondary)
                    }

                    Button {
                        manager.voiceEnabled = store.voiceCues
                        manager.start(freeRun)
                    } label: {
                        Label("Free run", systemImage: "figure.run").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Toggle(isOn: Binding(get: { store.voiceCues }, set: { store.setVoiceCues($0) })) {
                        Label("Voice cues", systemImage: "airpods")
                    }
                    .font(.footnote)
                    .tint(.green)

                    // Lifts and mobility for today, checked off from the wrist.
                    let extras = (store.today?.workouts ?? []).filter { !$0.type.isRun && $0.type != .rest }
                    if !extras.isEmpty {
                        Divider()
                        Text("Also today").font(.footnote).foregroundStyle(.secondary)
                        ForEach(extras) { workout in
                            let done = store.isCompleted(workout)
                            HStack {
                                if let routine = RoutineLibrary.routine(workout.standaloneRoutineID) {
                                    NavigationLink { WatchRoutineView(routine: routine) } label: {
                                        Label(workout.title, systemImage: workout.type.symbol).foregroundStyle(workout.type.tint)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Label(workout.title, systemImage: workout.type.symbol).foregroundStyle(workout.type.tint)
                                }
                                Spacer()
                                Button {
                                    let record = ActivityRecord(date: .now, type: workout.type, plannedWorkoutID: workout.id, durationSeconds: 0, meters: 0)
                                    store.record(record)
                                    Connectivity.shared.send(activity: record)
                                } label: {
                                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(done ? .green : .secondary)
                                }
                                .buttonStyle(.plain)
                                .disabled(done)
                            }
                            .font(.footnote)
                        }
                    }

                    if let week = store.thisWeek {
                        Divider()
                        Text("This week").font(.footnote).foregroundStyle(.secondary)
                        ForEach(week.days) { day in
                            let main = day.workouts.first { $0.type.isRun } ?? day.workouts.first!
                            HStack {
                                Text(day.weekday.shortName).frame(width: 34, alignment: .leading)
                                    .fontWeight(Calendar.current.isDateInToday(day.date) ? .bold : .regular)
                                Image(systemName: main.type.symbol).foregroundStyle(main.type.tint)
                                Text(main.title).lineLimit(1)
                                Spacer()
                                if day.workouts.contains(where: { store.isCompleted($0) }) {
                                    Image(systemName: "checkmark").foregroundStyle(.green)
                                }
                            }
                            .font(.footnote)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .navigationTitle("Stride")
        }
    }

    private var freeRun: Workout {
        Workout(
            type: .easy,
            title: "Free run",
            summary: "",
            segments: [Segment(kind: .work, name: "Run", goal: .open, pace: store.plan?.paces.easy)],
            plannedMeters: 0
        )
    }
}

struct WorkoutCard: View {
    let workout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(workout.title, systemImage: workout.type.symbol)
                .font(.headline)
                .foregroundStyle(workout.type.tint)
            if let pace = workout.mainPace {
                Text(pace.formatted).font(.footnote).foregroundStyle(.secondary)
            }
            Text("~" + Formatting.minutes(workout.estimatedDuration) + " · \(workout.segments.count) parts")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct WatchRoutineView: View {
    let routine: Routine

    var body: some View {
        List(routine.exercises) { ex in
            VStack(alignment: .leading, spacing: 2) {
                Text(ex.name).font(.headline)
                Text(ex.dose).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(routine.title)
    }
}

