import SwiftUI

/// The whole plan, week by week. Tapping a week expands its days.
struct PlanView: View {
    @Environment(AppStore.self) private var store
    @State private var expanded: Set<UUID> = []
    @State private var buildingPlan = false

    var body: some View {
        NavigationStack {
            List {
                if store.plan == nil {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No plan yet").font(.headline)
                            Text("You're tracking runs without a schedule. A plan lays out each week around your goal and lifting days, with warm-ups, cool-downs and pace targets on the watch.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        Button("Build a training plan…") { buildingPlan = true }
                    }
                }
                if let plan = store.plan {
                    Section {
                        HStack(alignment: .lastTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("THE GOAL").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(.stride)
                                Text(plan.goal.name).font(.system(size: 34, weight: .bold, design: .rounded))
                                Text(plan.raceDate.formatted(.dateTime.weekday(.wide).month().day()))
                                    .font(.subheadline).foregroundStyle(.white.opacity(0.6))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 0) {
                                Text("\(daysToRace)").font(.system(size: 44, weight: .bold, design: .rounded))
                                Text("days to go").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(20)
                        .background {
                            ZStack {
                                LinearGradient(colors: [.ink, .inkDeep], startPoint: .top, endPoint: .bottom)
                                RadialGradient(colors: [Color.ember.opacity(0.4), .clear], center: .topTrailing, startRadius: 0, endRadius: 240)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }

                    ForEach(plan.weeks) { week in
                        let isCurrent = week.id == store.thisWeek?.id
                        Section {
                            Button {
                                withAnimation { toggle(week.id) }
                            } label: {
                                WeekHeader(week: week, isCurrent: isCurrent, expanded: expanded.contains(week.id))
                            }
                            .buttonStyle(.plain)

                            if expanded.contains(week.id) {
                                ForEach(week.days) { day in
                                    DayRow(day: day)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Plan")
            .sheet(isPresented: $buildingPlan) { PlanSetupView() }
            .navigationDestination(for: Workout.self) { WorkoutDetailView(workout: $0) }
            .onAppear {
                if let current = store.thisWeek { expanded.insert(current.id) }
            }
        }
    }

    private var daysToRace: Int {
        guard let plan = store.plan else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: .now, to: plan.raceDate).day ?? 0)
    }

    private func toggle(_ id: UUID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }
}

struct WeekHeader: View {
    @Environment(AppStore.self) private var store
    let week: PlannedWeek
    let isCurrent: Bool
    let expanded: Bool

    var body: some View {
        let actual = store.activities(in: week).reduce(0) { $0 + $1.meters }
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Week \(week.number)").font(.headline)
                    if isCurrent {
                        Text("NOW").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.stride, in: Capsule()).foregroundStyle(.white)
                    }
                }
                Text(week.focus).font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 3) {
                    ForEach(week.days) { day in
                        let main = day.workouts.first { $0.type.isRun } ?? day.workouts.first!
                        RoundedRectangle(cornerRadius: 2)
                            .fill(main.type == .rest ? Color(.tertiarySystemFill) : main.type.tint)
                            .frame(height: 6)
                    }
                }
                .padding(.top, 2)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(Formatting.miles(week.plannedMeters, decimals: 0)).font(.headline)
                if actual > 0 {
                    Text("\(Formatting.miles(actual, decimals: 1)) done").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("\(week.runCount) runs").font(.caption).foregroundStyle(.secondary)
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
        }
        .contentShape(Rectangle())
    }
}

struct DayRow: View {
    @Environment(AppStore.self) private var store
    let day: PlannedDay

    var body: some View {
        let isToday = Calendar.current.isDateInToday(day.date)
        HStack(alignment: .top, spacing: 12) {
            VStack {
                Text(day.weekday.shortName).font(.caption.weight(isToday ? .bold : .regular))
                Text(day.date.formatted(.dateTime.day())).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 36)
            .padding(.top, 2)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(day.workouts) { workout in
                    if workout.type == .rest {
                        Text("Rest").foregroundStyle(.secondary)
                    } else {
                        NavigationLink(value: workout) {
                            HStack(spacing: 8) {
                                Image(systemName: workout.type.symbol).foregroundStyle(workout.type.tint).frame(width: 20)
                                Text(workout.title)
                                Spacer()
                                if store.isCompleted(workout) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.jade)
                                } else if let pace = workout.mainPace {
                                    Text(pace.fast.formatted + "–" + pace.slow.formatted).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
