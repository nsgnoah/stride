import WidgetKit
import SwiftUI

/// "What's today?" on the Home Screen and Lock Screen. Reads the same JSON the app writes
/// (via the app group), so it updates the moment a run is saved or moved.
@main
struct StrideWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
    }
}

struct TodayEntry: TimelineEntry {
    var date: Date
    var workouts: [Workout]
    var week: PlannedWeek?
    var weekCount: Int
    var done: Set<UUID>
    var skipped: Set<UUID>
    var hasPlan: Bool

    static let placeholder = TodayEntry(
        date: .now,
        workouts: [Workout(type: .easy, title: "Easy 3 mi", summary: "", plannedMeters: Units.meters(miles: 3))],
        week: nil, weekCount: 10, done: [], skipped: [], hasPlan: true
    )
}

struct TodayProvider: TimelineProvider {
    /// WidgetKit's completion closures aren't Sendable; they're safe to call from any thread.
    private struct Callback<T>: @unchecked Sendable { let call: (T) -> Void }

    func placeholder(in context: Context) -> TodayEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        if context.isPreview { completion(.placeholder); return }
        let done = Callback(call: completion)
        Task { @MainActor in done.call(load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let done = Callback(call: completion)
        Task { @MainActor in
            let entry = load()
            let cal = Calendar.current
            let midnight = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: .now)!)
            done.call(Timeline(entries: [entry], policy: .after(midnight)))
        }
    }

    @MainActor
    private func load() -> TodayEntry {
        #if os(watchOS)
        let store = AppStore(filename: "stride-watch.json")
        #else
        let store = AppStore()
        #endif
        guard let plan = store.plan else {
            return TodayEntry(date: .now, workouts: [], week: nil, weekCount: 0, done: [], skipped: [], hasPlan: false)
        }
        return TodayEntry(
            date: .now,
            workouts: store.today?.workouts ?? [],
            week: store.thisWeek,
            weekCount: plan.weeks.count,
            done: Set(store.activities.compactMap(\.plannedWorkoutID)),
            skipped: plan.skipped,
            hasPlan: true
        )
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "co.nsgsolutions.Stride.today", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today's run")
        .description("What's on the plan today, and how the week looks.")
        #if os(watchOS)
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular, .accessoryCorner])
        #else
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
        #endif
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    /// The headline item: the run if there is one, else the lift/mobility, else rest.
    private var main: Workout? {
        entry.workouts.first { $0.type.isRun && !entry.skipped.contains($0.id) } ?? entry.workouts.first
    }

    private var isDone: Bool { main.map { entry.done.contains($0.id) } ?? false }

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryRectangular: rectangular
        case .accessoryCircular, .accessoryCorner: circular
        #if os(iOS)
        case .systemMedium: medium
        default: small
        #else
        default: rectangular
        #endif
        }
    }

    /// Icon plus the distance, for the corner and circular slots on the watch face.
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: isDone ? "checkmark" : (main?.type.symbol ?? "figure.run"))
                    .font(.system(size: 16, weight: .semibold))
                if let main, main.plannedMeters > 0 {
                    Text(Units.miles(main.plannedMeters).formatted(.number.precision(.fractionLength(0...1))))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                } else {
                    Text(main == nil ? "rest" : "").font(.system(size: 9))
                }
            }
        }
    }

    // MARK: - Families

    private var inline: some View {
        if let main {
            Text("\(Image(systemName: main.type.symbol)) \(main.title)\(main.mainPace.map { " · \($0.formatted)" } ?? "")")
        } else {
            Text(entry.hasPlan ? "Rest day" : "Open Stride to build a plan")
        }
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            if let main {
                Image(systemName: isDone ? "checkmark.circle.fill" : main.type.symbol)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(main.title).font(.headline).lineLimit(1)
                    if let pace = main.mainPace {
                        Text(pace.formatted).font(.caption2).foregroundStyle(.secondary)
                    } else if !main.summary.isEmpty {
                        Text(main.summary).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } else {
                Image(systemName: "figure.run")
                Text(entry.hasPlan ? "Rest day" : "Build a plan").font(.headline)
            }
            Spacer(minLength: 0)
        }
    }

    #if os(iOS)
    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.date.formatted(.dateTime.weekday(.wide)).uppercased())
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if let week = entry.week {
                    Text("W\(week.number)/\(entry.weekCount)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let main {
                Image(systemName: main.type.symbol)
                    .font(.title)
                    .foregroundStyle(main.type.tint)
                Text(main.title).font(.headline).lineLimit(2).minimumScaleFactor(0.8)
                if isDone {
                    Label("Done", systemImage: "checkmark").font(.caption).foregroundStyle(Color.jade)
                } else if let pace = main.mainPace {
                    Text(pace.formatted).font(.caption).foregroundStyle(.secondary)
                } else if let second = entry.workouts.dropFirst().first, entry.workouts.count > 1 {
                    Text("+ \(second.title)").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "figure.run").font(.title).foregroundStyle(.secondary)
                Text(entry.hasPlan ? "Rest day" : "Build a plan in Stride").font(.headline)
            }
        }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            small.frame(maxWidth: .infinity, alignment: .leading)
            if let week = entry.week {
                VStack(alignment: .leading, spacing: 6) {
                    Text(week.focus).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        ForEach(week.days) { day in
                            let dayMain = day.workouts.first { $0.type.isRun } ?? day.workouts.first!
                            let done = day.workouts.contains { entry.done.contains($0.id) }
                            let isToday = Calendar.current.isDate(day.date, inSameDayAs: entry.date)
                            VStack(spacing: 3) {
                                Text(day.weekday.letter).font(.system(size: 9, weight: isToday ? .bold : .regular))
                                    .foregroundStyle(isToday ? .primary : .secondary)
                                ZStack {
                                    Circle().fill(dayMain.type == .rest ? Color.secondary.opacity(0.15) : dayMain.type.tint.opacity(done ? 1 : 0.25))
                                    Image(systemName: done ? "checkmark" : dayMain.type.symbol)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(done ? .white : dayMain.type.tint)
                                }
                                .frame(width: 22, height: 22)
                                .overlay { if isToday { Circle().strokeBorder(.primary, lineWidth: 1).padding(-2) } }
                            }
                        }
                    }
                    Text("\(Formatting.miles(week.plannedMeters, decimals: 0)) planned")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    #endif
}

#if os(iOS)
#Preview(as: .systemSmall) {
    TodayWidget()
} timeline: {
    TodayEntry.placeholder
}
#endif
