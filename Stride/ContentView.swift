import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if store.plan == nil {
            PlanSetupView()
        } else {
            TabView {
                Tab("Today", systemImage: "sun.max") { TodayView() }
                Tab("Plan", systemImage: "calendar") { PlanView() }
                Tab("Progress", systemImage: "chart.line.uptrend.xyaxis") { ProgressTabView() }
                Tab("Settings", systemImage: "gearshape") { SettingsView() }
            }
        }
    }
}

// MARK: - Shared bits

struct WorkoutRow: View {
    @Environment(AppStore.self) private var store
    let workout: Workout

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workout.type.symbol)
                .font(.title3)
                .foregroundStyle(workout.type.tint)
                .frame(width: 28)
            let skipped = store.plan?.isSkipped(workout) == true
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.title).font(.headline)
                    .strikethrough(skipped)
                    .foregroundStyle(skipped ? .secondary : .primary)
                if skipped {
                    Text("Skipped").font(.subheadline).foregroundStyle(.secondary)
                } else if let pace = workout.mainPace {
                    Text(pace.formatted).font(.subheadline).foregroundStyle(.secondary)
                } else if !workout.summary.isEmpty {
                    Text(workout.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if store.isCompleted(workout) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
    }
}


struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var showReset = false
    @State private var editing = false
    @State private var recalibrating: ActivityRecord?
    @State private var remindersDenied = false

    var body: some View {
        NavigationStack {
            List {
                if let profile = store.profile, let plan = store.plan {
                    Section("Plan") {
                        LabeledContent("Goal", value: plan.goal.name)
                        LabeledContent("Race", value: plan.raceDate.formatted(date: .abbreviated, time: .omitted))
                        LabeledContent("Runs per week", value: "\(profile.runDaysPerWeek)")
                        LabeledContent("Lifting days", value: profile.strengthDays.isEmpty ? "None" : profile.strengthDays.sorted().map(\.shortName).joined(separator: ", "))
                        Button("Adjust plan…") { editing = true }
                    }
                    Section {
                        LabeledContent("Easy", value: plan.paces.easy.formatted)
                        LabeledContent("Long run", value: plan.paces.long.formatted)
                        LabeledContent("Tempo", value: plan.paces.tempo.formatted)
                        LabeledContent("Intervals", value: plan.paces.interval.formatted)
                        LabeledContent("Race", value: plan.paces.race.formatted)
                        if let effort = PaceCalculator.bestRecentEffort(in: store.activities) {
                            Button("Update paces from my \(effort.type.name.lowercased())…") { recalibrating = effort }
                        }
                    } header: {
                        Text("Training paces")
                    } footer: {
                        Text("Paces come from the recent run you entered at setup. After a tempo run or race on the watch, you can update them from that effort.")
                    }
                }
                Section {
                    Toggle("Morning reminder on run days", isOn: Binding(
                        get: { store.reminderHour != nil },
                        set: { on in
                            if on {
                                Task {
                                    if await Reminders.requestPermission() {
                                        store.setReminderHour(7)
                                        await Reminders.reschedule(plan: store.plan, hour: 7, skippedOrDone: store.settledWorkoutIDs)
                                    } else {
                                        remindersDenied = true
                                    }
                                }
                            } else {
                                store.setReminderHour(nil)
                                Task { await Reminders.reschedule(plan: nil, hour: nil, skippedOrDone: []) }
                            }
                        }
                    ))
                    if let hour = store.reminderHour {
                        Picker("Time", selection: Binding(
                            get: { hour },
                            set: { h in
                                store.setReminderHour(h)
                                Task { await Reminders.reschedule(plan: store.plan, hour: h, skippedOrDone: store.settledWorkoutIDs) }
                            }
                        )) {
                            ForEach(5..<12, id: \.self) { h in
                                Text(Calendar.current.date(from: DateComponents(hour: h))!.formatted(.dateTime.hour())).tag(h)
                            }
                        }
                    }
                } footer: {
                    if remindersDenied {
                        Text("Notifications are off for Stride in iOS Settings. Turn them on there to get reminders.")
                    }
                }

                Section {
                    ForEach(RoutineLibrary.all) { routine in
                        NavigationLink {
                            RoutineView(routine: routine)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(routine.title)
                                Text("\(routine.minutes) min · \(routine.exercises.count) moves").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Warm-ups, cool-downs & mobility")
                } footer: {
                    Text("Every run links to the right ones automatically; this is the whole library for rest days.")
                }

                Section {
                    Button("Sync plan to watch") { Connectivity.shared.send(plan: store.plan) }
                    Button("Start over", role: .destructive) { showReset = true }
                }
                Section("About") {
                    Text("Your plan and runs are stored only on your iPhone and Apple Watch. Runs you save are written to Apple Health on your device. Stride has no account, no server, and no analytics.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Stride offers general training guidance and is not medical advice. Check with a doctor before starting a new training program, and stop if you feel pain.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete the plan and all logged runs?", isPresented: $showReset, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { store.reset() }
            }
            .sheet(isPresented: $editing) {
                NavigationStack { PlanSetupView(existing: store.profile) }
            }
            .sheet(item: $recalibrating) { effort in
                RecalibrateView(effort: effort)
            }
        }
    }
}

/// Shows what the paces would become if we anchored fitness to a recorded effort.
struct RecalibrateView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let effort: ActivityRecord

    private var proposed: PaceProfile? {
        guard var p = store.profile else { return nil }
        p.recentRunMeters = effort.meters
        p.recentRunSeconds = effort.durationSeconds
        return PaceCalculator.profile(for: p)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent(effort.type.name, value: effort.date.formatted(date: .abbreviated, time: .omitted))
                    LabeledContent("Distance", value: Formatting.miles(effort.meters, decimals: 2))
                    LabeledContent("Time", value: Formatting.duration(effort.durationSeconds))
                } header: {
                    Text("Based on")
                }
                if let current = store.plan?.paces, let proposed {
                    Section("New paces") {
                        row("Easy", current.easy, proposed.easy)
                        row("Tempo", current.tempo, proposed.tempo)
                        row("Intervals", current.interval, proposed.interval)
                        row("Race", current.race, proposed.race)
                    }
                }
                Section {
                    Text("Future runs get the new pace windows. Finished runs and your week numbers stay as they are.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Update paces")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        guard var p = store.profile else { return }
                        p.recentRunMeters = effort.meters
                        p.recentRunSeconds = effort.durationSeconds
                        store.createPlan(from: p)
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }

    private func row(_ label: String, _ old: PaceRange, _ new: PaceRange) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(old.midpoint.formatted).foregroundStyle(.secondary).strikethrough()
            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
            Text(new.formatted).monospacedDigit()
        }
    }
}
