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
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.title).font(.headline)
                if let pace = workout.mainPace {
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

extension WorkoutType {
    var tint: Color {
        switch self {
        case .easy, .shakeout: .green
        case .long: .blue
        case .tempo: .orange
        case .intervals: .red
        case .race: .purple
        case .strength: .indigo
        case .mobility: .teal
        case .rest: .secondary
        }
    }
}

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var showReset = false
    @State private var editing = false

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
                    Section("Training paces") {
                        LabeledContent("Easy", value: plan.paces.easy.formatted)
                        LabeledContent("Long run", value: plan.paces.long.formatted)
                        LabeledContent("Tempo", value: plan.paces.tempo.formatted)
                        LabeledContent("Intervals", value: plan.paces.interval.formatted)
                        LabeledContent("Race", value: plan.paces.race.formatted)
                    }
                }
                Section {
                    Button("Sync plan to watch") { Connectivity.shared.send(plan: store.plan) }
                    Button("Start over", role: .destructive) { showReset = true }
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete the plan and all logged runs?", isPresented: $showReset, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { store.reset() }
            }
            .sheet(isPresented: $editing) {
                NavigationStack { PlanSetupView(existing: store.profile) }
            }
        }
    }
}
