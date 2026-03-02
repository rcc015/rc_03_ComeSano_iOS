import WidgetKit
import SwiftUI
import Foundation

private enum WidgetShared {
    static let appGroupID = "group.rcTools.ComeSano"
    static let consumedKey = "widget.calories.consumed"
    static let goalKey = "widget.calories.goal"
    static let activeKey = "widget.calories.active"
    static let basalKey = "widget.calories.basal"
    static let adjustedBudgetKey = "widget.calories.adjustedBudget"
    static let adjustedDeltaKey = "widget.calories.adjustedDelta"
    static let proteinActualKey = "widget.macros.protein.actual"
    static let proteinTargetKey = "widget.macros.protein.target"
    static let carbsActualKey = "widget.macros.carbs.actual"
    static let carbsTargetKey = "widget.macros.carbs.target"
    static let fatActualKey = "widget.macros.fat.actual"
    static let fatTargetKey = "widget.macros.fat.target"
}

struct CalorieEntry: TimelineEntry {
    let date: Date
    let consumed: Double
    let goal: Double
    let active: Double
    let basal: Double
    let adjustedBudget: Double
    let adjustedDelta: Double
    let proteinActual: Double
    let proteinTarget: Double
    let carbsActual: Double
    let carbsTarget: Double
    let fatActual: Double
    let fatTarget: Double
}

struct CalorieProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalorieEntry {
        CalorieEntry(
            date: .now,
            consumed: 1450,
            goal: 2100,
            active: 420,
            basal: 1600,
            adjustedBudget: 2520,
            adjustedDelta: -1070,
            proteinActual: 95,
            proteinTarget: 160,
            carbsActual: 140,
            carbsTarget: 210,
            fatActual: 50,
            fatTarget: 70
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CalorieEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalorieEntry>) -> Void) {
        let entry = makeEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func makeEntry() -> CalorieEntry {
        let defaults = UserDefaults(suiteName: WidgetShared.appGroupID)
        let consumed = defaults?.double(forKey: WidgetShared.consumedKey) ?? 0
        let goal = max(defaults?.double(forKey: WidgetShared.goalKey) ?? 2100, 1)
        let active = defaults?.double(forKey: WidgetShared.activeKey) ?? 0
        let basal = defaults?.double(forKey: WidgetShared.basalKey) ?? 0
        let adjustedBudget = max(defaults?.double(forKey: WidgetShared.adjustedBudgetKey) ?? (goal + active), 1)
        let adjustedDelta = defaults?.double(forKey: WidgetShared.adjustedDeltaKey) ?? (consumed - adjustedBudget)

        return CalorieEntry(
            date: .now,
            consumed: consumed,
            goal: goal,
            active: active,
            basal: basal,
            adjustedBudget: adjustedBudget,
            adjustedDelta: adjustedDelta,
            proteinActual: defaults?.double(forKey: WidgetShared.proteinActualKey) ?? 0,
            proteinTarget: max(defaults?.double(forKey: WidgetShared.proteinTargetKey) ?? 160, 1),
            carbsActual: defaults?.double(forKey: WidgetShared.carbsActualKey) ?? 0,
            carbsTarget: max(defaults?.double(forKey: WidgetShared.carbsTargetKey) ?? 200, 1),
            fatActual: defaults?.double(forKey: WidgetShared.fatActualKey) ?? 0,
            fatTarget: max(defaults?.double(forKey: WidgetShared.fatTargetKey) ?? 70, 1)
        )
    }
}

#if os(watchOS)
struct CalorieComplicationEntryView: View {
    var entry: CalorieProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: entry.consumed, in: 0...entry.goal) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
            } currentValueLabel: {
                Text("\(Int(entry.consumed.rounded()))")
                    .font(.system(.body, design: .rounded))
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Gradient(colors: [.green, .mint]))

        case .accessoryRectangular:
            VStack(alignment: .leading) {
                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text("Calorías")
                        .font(.headline)
                }
                Gauge(value: entry.consumed, in: 0...entry.goal) {
                    EmptyView()
                } currentValueLabel: {
                    Text("\(Int(entry.consumed.rounded())) / \(Int(entry.goal.rounded()))")
                }
                .gaugeStyle(.accessoryLinear)
                .tint(Gradient(colors: [.green, .mint]))
            }

        case .accessoryCorner:
            Gauge(value: entry.consumed, in: 0...entry.goal) {
                Image(systemName: "flame.fill")
            } currentValueLabel: {
                Text("\(Int(entry.consumed.rounded()))")
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Gradient(colors: [.green, .mint]))

        default:
            Text("\(Int(entry.consumed.rounded()))")
        }
    }
}

@main
struct CalorieWidget: Widget {
    let kind: String = "CalorieWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalorieProvider()) { entry in
            CalorieComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("Progreso de Calorías")
        .description("Mira tus calorías consumidas de un vistazo.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner])
    }
}
#endif

#if os(iOS)
private struct BalanceWidgetView: View {
    let entry: CalorieEntry
    @Environment(\.widgetFamily) var family

    private var progress: Double {
        let safeBudget = max(entry.adjustedBudget, 1)
        return min(max(entry.consumed / safeBudget, 0), 1)
    }

    var body: some View {
        Group {
            if family == .systemSmall {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(lineWidth: 14)
                            .opacity(0.2)
                            .foregroundStyle(entry.adjustedDelta > 0 ? .red : .green)

                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(style: StrokeStyle(lineWidth: 14, lineCap: .round))
                            .foregroundStyle(entry.adjustedDelta > 0 ? .red : .green)
                            .rotationEffect(.degrees(270))

                        VStack(spacing: 1) {
                            Text("\(Int(entry.consumed.rounded()))")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .minimumScaleFactor(0.7)
                            Text("kcal")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("\(entry.adjustedDelta <= 0 ? "" : "+")\(Int(entry.adjustedDelta.rounded())) kcal")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(entry.adjustedDelta > 0 ? .red : .green)
                }
            } else {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(lineWidth: 12)
                            .opacity(0.2)
                            .foregroundStyle(entry.adjustedDelta > 0 ? .red : .green)

                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            .foregroundStyle(entry.adjustedDelta > 0 ? .red : .green)
                            .rotationEffect(.degrees(270))

                        Text("\(Int(entry.consumed.rounded()))")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.7)
                    }
                    .frame(width: 92, height: 92)

                    VStack(alignment: .leading, spacing: 8) {
                        statRow("Meta", value: "\(Int(entry.goal.rounded())) kcal")
                        statRow("Ejercicio", value: "+\(Int(entry.active.rounded())) kcal", color: .orange)
                        statRow("Presupuesto", value: "\(Int(entry.adjustedBudget.rounded())) kcal", color: .green)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func statRow(_ title: String, value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }
}

private struct MacrosWidgetView: View {
    let entry: CalorieEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if family == .systemMedium {
                HStack {
                    Text("Macronutrientes")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Image(systemName: "chart.bar.fill")
                        .foregroundStyle(.secondary)
                }
            }

            macroLine("P", title: "Proteína", actual: entry.proteinActual, target: entry.proteinTarget, color: .blue)
            macroLine("C", title: "Carbohidratos", actual: entry.carbsActual, target: entry.carbsTarget, color: .orange)
            macroLine("G", title: "Grasas", actual: entry.fatActual, target: entry.fatTarget, color: .purple)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func macroLine(_ shortLabel: String, title: String, actual: Double, target: Double, color: Color) -> some View {
        let safeTarget = max(target, 1)
        let progress = min(max(actual / safeTarget, 0), 1)

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(shortLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()

                if family == .systemMedium {
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(actual.rounded()))g / \(Int(target.rounded()))g")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(Int(actual.rounded()))/\(Int(target.rounded()))g")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.2))
                        .frame(height: 6)
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * progress, height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}

private struct QuickLogWidgetView: View {
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            if family == .systemSmall {
                Link(destination: URL(string: "comesano://open?tab=camera")!) {
                    VStack(spacing: 10) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 36, weight: .bold))
                        Text("Escanear Comida")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                    .background(Color.accentColor.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Registro rápido")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(.yellow)
                    }

                    HStack(spacing: 10) {
                        circularAction("Agua", icon: "drop.fill", url: "comesano://quickadd?type=water", color: .cyan)
                        circularAction("Café", icon: "cup.and.saucer.fill", url: "comesano://quickadd?type=coffee", color: .brown)
                        circularAction("Snack", icon: "apple.logo", url: "comesano://quickadd?type=apple", color: .red)
                        circularAction("Escáner", icon: "camera.fill", url: "comesano://open?tab=camera", color: .blue)
                    }
                }
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func circularAction(_ title: String, icon: String, url: String, color: Color) -> some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.20))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

struct DailyBalanceWidget: Widget {
    let kind = "DailyBalanceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalorieProvider()) { entry in
            BalanceWidgetView(entry: entry)
        }
        .configurationDisplayName("Balance Diario")
        .description("Meta, ejercicio y presupuesto ajustado.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MacrosWidget: Widget {
    let kind = "MacrosWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalorieProvider()) { entry in
            MacrosWidgetView(entry: entry)
        }
        .configurationDisplayName("Macros")
        .description("Progreso diario de proteína, carbos y grasas.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct QuickLogWidget: Widget {
    let kind = "QuickLogWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalorieProvider()) { _ in
            QuickLogWidgetView()
        }
        .configurationDisplayName("Registro Rápido")
        .description("Escanea o registra agua, café y snack.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#endif
