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
    private let startFresh: Bool

    init(existing: RunnerProfile? = nil, startFresh: Bool = false, recentEffort: ActivityRecord? = nil) {
        self.startFresh = startFresh
        var p = existing ?? RunnerProfile()
        if startFresh {
            // A new goal after a finished plan: keep her schedule, reset the date, and
            // anchor fitness to what she just ran rather than the number from months ago.
            p.raceDate = Calendar.current.date(byAdding: .weekOfYear, value: p.goal.defaultWeeks, to: .now)!
            if let recentEffort {
                p.recentRunMeters = recentEffort.meters
                p.recentRunSeconds = recentEffort.durationSeconds
                // She just covered this distance; don't start the next plan below it.
                let covered = (Units.miles(recentEffort.meters) * 2).rounded(.down) / 2
                p.longestComfortableMiles = max(p.longestComfortableMiles, min(covered, p.goal.longRunCapMiles))
            }
        }
        // Plans made before run days could be chosen: start from the days she's been given.
        if p.runDays.isEmpty { p.runDays = PlanGenerator.automaticRunDays(for: p) }
        if !p.runDays.contains(p.longRunDay) { p.longRunDay = Self.defaultLongDay(in: p.runDays) ?? p.longRunDay }
        _profile = State(initialValue: p)
        _recentMiles = State(initialValue: Units.miles(p.recentRunMeters))
        _recentMinutes = State(initialValue: Int(p.recentRunSeconds) / 60)
        _recentSeconds = State(initialValue: Int(p.recentRunSeconds) % 60)
        isEditing = existing != nil && !startFresh
    }

    private var preview: PaceProfile { PaceCalculator.profile(for: builtProfile) }

    /// The weekend day if she runs on one, otherwise her last run day of the week.
    private static func defaultLongDay(in days: Set<Weekday>) -> Weekday? {
        [.saturday, .sunday].first(where: days.contains) ?? days.sorted().last
    }

    private var runSummary: String {
        let count = profile.runDays.count
        let range = PlanGenerator.longRunRange(for: builtProfile)
        let first = Self.miles(range.first), peak = Self.miles(range.peak)
        if count == 0 { return "Pick at least one day." }
        let growth = range.peak > range.first ? "starts at \(first) mi and builds to \(peak) mi" : "holds at \(first) mi"
        if count == 1 {
            return "One run a week. It \(growth) — no weekly mileage to hit."
        }
        return "\(count) runs a week. The longest \(growth); the others are shorter."
    }

    private static func miles(_ x: Double) -> String {
        x == x.rounded() ? String(Int(x)) : String(format: "%.1f", x)
    }

    private var builtProfile: RunnerProfile {
        var p = profile
        p.runDaysPerWeek = max(1, p.runDays.count)
        p.recentRunMeters = Units.meters(miles: recentMiles)
        p.recentRunSeconds = TimeInterval(recentMinutes * 60 + recentSeconds)
        return p
    }

    var body: some View {
        NavigationStack {
            Form {
                if !isEditing && !startFresh && store.plan == nil && !store.freeMode {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Just want to run?").font(.headline)
                            Text("Skip the plan. Open Stride on your watch, tap Free run, and your runs, pace and splits are tracked here. You can build a plan any time.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        Button("Skip the plan — just track my runs") {
                            store.setFreeMode(true)
                            dismiss()
                        }
                    }
                }

                Section {
                    Picker("Goal distance", selection: $profile.goal) {
                        ForEach(GoalDistance.allCases) { Text($0.name).tag($0) }
                    }
                    Toggle("I have a race date", isOn: $profile.hasRaceDate)
                    if profile.hasRaceDate {
                        DatePicker("Race day", selection: $profile.raceDate, in: minRaceDate..., displayedComponents: .date)
                        Text("\(profile.weeksUntilRace) weeks of training")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("About \(builtProfile.weeksUntilRace) weeks to build up to a \(profile.goal.name), a little further each week.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("The goal")
                } footer: {
                    Text(profile.hasRaceDate
                         ? "\(profile.goal.defaultWeeks) weeks is typical for a \(profile.goal.name)."
                         : "No date needed — the plan takes as long as a safe build-up takes from where you are now.")
                }
                .onChange(of: profile.goal) { _, goal in
                    if !isEditing {
                        profile.raceDate = Calendar.current.date(byAdding: .weekOfYear, value: goal.defaultWeeks, to: .now)!
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Run days")
                        WeekdayPicker(selection: $profile.runDays, tint: .green)
                        Text(runSummary)
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if profile.runDays.count > 1 {
                        Picker("Longest run on", selection: $profile.longRunDay) {
                            ForEach(profile.runDays.sorted()) { Text($0.shortName).tag($0) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Lifting days")
                        WeekdayPicker(selection: $profile.strengthDays)
                        Text("Shown alongside your runs. Faster runs steer clear of them when your run days allow.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if profile.runDays.count > 1 {
                        Toggle("Include faster workouts", isOn: $profile.includeSpeedWork)
                    }
                } header: {
                    Text("Your week")
                } footer: {
                    Text("These are your regular days. When life gets in the way, any run can be pushed to tomorrow or another day with one tap.")
                }
                .onChange(of: profile.runDays) { _, days in
                    if !days.contains(profile.longRunDay), let day = Self.defaultLongDay(in: days) {
                        profile.longRunDay = day
                    }
                }

                Section {
                    Stepper(value: $profile.longestComfortableMiles, in: 1...20, step: 0.5) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Longest comfortable run")
                            Text("\(Self.miles(profile.longestComfortableMiles)) mi").font(.subheadline).foregroundStyle(.secondary)
                        }
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
                    Text("Longest comfortable run is how far you could go today without it being a struggle — your first week starts there. For the recent run, any effort works: a hard 5K, a solid 3-miler, a race. The watch uses it to tell you when to speed up or slow down.")
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
                if isEditing || startFresh || store.freeMode {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Rebuild" : "Build my plan") {
                        store.createPlan(from: builtProfile, fresh: startFresh)
                        dismiss()
                    }
                    .bold()
                    .disabled(profile.runDays.isEmpty)
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
    var tint: Color = .indigo

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
                        .background(on ? tint : Color(.tertiarySystemFill), in: Circle())
                        .foregroundStyle(on ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
