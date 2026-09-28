import SwiftUI

/// Onboarding + "adjust plan". Everything the generator needs on one screen.
struct PlanSetupView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var profile: RunnerProfile
    @State private var recentMiles: Double
    @State private var recentMinutes: Int
    @State private var recentSeconds: Int
    private let isEditing: Bool

    init(existing: RunnerProfile? = nil) {
        let p = existing ?? RunnerProfile()
        _profile = State(initialValue: p)
        _recentMiles = State(initialValue: Units.miles(p.recentRunMeters))
        _recentMinutes = State(initialValue: Int(p.recentRunSeconds) / 60)
        _recentSeconds = State(initialValue: Int(p.recentRunSeconds) % 60)
        isEditing = existing != nil
    }

    private var preview: PaceProfile { PaceCalculator.profile(for: builtProfile) }

    private var builtProfile: RunnerProfile {
        var p = profile
        p.recentRunMeters = Units.meters(miles: recentMiles)
        p.recentRunSeconds = TimeInterval(recentMinutes * 60 + recentSeconds)
        return p
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Goal distance", selection: $profile.goal) {
                        ForEach(GoalDistance.allCases) { Text($0.name).tag($0) }
                    }
                    DatePicker("Race day", selection: $profile.raceDate, in: minRaceDate..., displayedComponents: .date)
                    Text("\(profile.weeksUntilRace) weeks of training")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text("The goal")
                } footer: {
                    Text("No race? Pick the date you'd like to be able to run the distance. \(profile.goal.defaultWeeks) weeks is typical for a \(profile.goal.name).")
                }
                .onChange(of: profile.goal) { _, goal in
                    if !isEditing {
                        profile.raceDate = Calendar.current.date(byAdding: .weekOfYear, value: goal.defaultWeeks, to: .now)!
                    }
                }

                Section("Your week") {
                    Stepper("Run \(profile.runDaysPerWeek) days a week", value: $profile.runDaysPerWeek, in: 3...6)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Lifting days")
                        WeekdayPicker(selection: $profile.strengthDays)
                        Text("Runs get scheduled around these. No hard runs the day after legs.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Picker("Long run day", selection: $profile.longRunDay) {
                        ForEach(Weekday.ordered) { Text($0.shortName).tag($0) }
                    }
                }

                Section {
                    HStack {
                        Text("Weekly miles right now")
                        Spacer()
                        TextField("10", value: $profile.currentWeeklyMiles, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }
                    HStack {
                        Text("A recent run")
                        Spacer()
                        TextField("3", value: $recentMiles, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 50)
                        Text("mi in").foregroundStyle(.secondary)
                        TextField("30", value: $recentMinutes, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 36)
                        Text(":").foregroundStyle(.secondary)
                        TextField("00", value: $recentSeconds, format: .number.precision(.integerLength(2)))
                            .keyboardType(.numberPad)
                            .frame(width: 30)
                    }
                } header: {
                    Text("Current fitness")
                } footer: {
                    Text("Any recent effort works — a hard 5K, a solid 3-miler, a race. The watch uses these paces to tell you when to speed up or slow down.")
                }

                Section {
                    LabeledContent("Easy", value: preview.easy.formatted)
                    LabeledContent("Tempo", value: preview.tempo.formatted)
                    LabeledContent("Intervals", value: preview.interval.formatted)
                    LabeledContent("\(profile.goal.name) goal", value: preview.race.formatted)
                } header: {
                    Text("Your paces")
                } footer: {
                    Text("General training guidance, not medical advice. If you're new to running or have a health condition, check with a doctor first.")
                }
            }
            .navigationTitle(isEditing ? "Adjust Plan" : "Stride")
            .toolbar {
                if isEditing {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Rebuild" : "Build my plan") {
                        store.createPlan(from: builtProfile)
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }

    private var minRaceDate: Date {
        Calendar.current.date(byAdding: .weekOfYear, value: 4, to: .now)!
    }
}

struct WeekdayPicker: View {
    @Binding var selection: Set<Weekday>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.ordered) { day in
                let on = selection.contains(day)
                Button {
                    if on { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(day.letter)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(on ? Color.indigo : Color(.tertiarySystemFill), in: Circle())
                        .foregroundStyle(on ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
