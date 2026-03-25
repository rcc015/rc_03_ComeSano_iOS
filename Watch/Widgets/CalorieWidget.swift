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
    static let fiberActualKey = "widget.macros.fiber.actual"
    static let fiberTargetKey = "widget.macros.fiber.target"
    static let suggestionKey = "widget.smart.suggestion"
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
    let fiberActual: Double
    let fiberTarget: Double
    let smartSuggestion: String
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
            fatTarget: 70,
            fiberActual: 24,
            fiberTarget: 30,
            smartSuggestion: "Buen ritmo. Mantén una cena ligera con proteína y fibra."
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
            fatTarget: max(defaults?.double(forKey: WidgetShared.fatTargetKey) ?? 70, 1),
            fiberActual: defaults?.double(forKey: WidgetShared.fiberActualKey) ?? 0,
            fiberTarget: max(defaults?.double(forKey: WidgetShared.fiberTargetKey) ?? 30, 1),
            smartSuggestion: defaults?.string(forKey: WidgetShared.suggestionKey) ?? "Mantén porciones estables y alimentos poco procesados."
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

private struct RingsWidgetView: View {
    let entry: CalorieEntry
    @Environment(\.widgetFamily) var family

    private var ringSizes: (fiber: CGFloat, fat: CGFloat, carbs: CGFloat, protein: CGFloat) {
        if family == .systemSmall {
            return (92, 74, 56, 38)
        }
        return (118, 94, 70, 46)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 10) {
            HStack {
                Text("Anillos")
                    .font(.caption.weight(.semibold))
                Spacer()
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(.secondary)
            }

            ZStack {
                ring(progress: progress(entry.fiberActual, entry.fiberTarget), size: ringSizes.fiber, color: .green)
                ring(progress: progress(entry.fatActual, entry.fatTarget), size: ringSizes.fat, color: .purple)
                ring(progress: progress(entry.carbsActual, entry.carbsTarget), size: ringSizes.carbs, color: .orange)
                ring(progress: progress(entry.proteinActual, entry.proteinTarget), size: ringSizes.protein, color: .blue)

                VStack(spacing: 2) {
                    Text("P C G F")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text("\(Int(entry.proteinActual.rounded())) \(Int(entry.carbsActual.rounded())) \(Int(entry.fatActual.rounded())) \(Int(entry.fiberActual.rounded()))")
                        .font(.system(size: family == .systemSmall ? 10 : 12, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.65)
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: family == .systemSmall ? 0 : 4) {
                legend("P", actual: entry.proteinActual, target: entry.proteinTarget, color: .blue)
                legend("C", actual: entry.carbsActual, target: entry.carbsTarget, color: .orange)
                legend("G", actual: entry.fatActual, target: entry.fatTarget, color: .purple)
                legend("F", actual: entry.fiberActual, target: entry.fiberTarget, color: .green)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func progress(_ actual: Double, _ target: Double) -> Double {
        let safe = max(target, 1)
        return min(max(actual / safe, 0), 1)
    }

    private func ring(progress: Double, size: CGFloat, color: Color) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: family == .systemSmall ? 8 : 10)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: family == .systemSmall ? 8 : 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }

    private func legend(_ label: String, actual: Double, target: Double, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
            Text("\(Int(actual.rounded()))/\(Int(target.rounded()))")
                .font(.system(size: family == .systemSmall ? 9 : 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SuggestionWidgetView: View {
    let entry: CalorieEntry
    let includeRings: Bool
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: includeRings ? 18 : 14) {
                balanceRing(size: includeRings ? 90 : 78)
                Spacer(minLength: 0)
                if includeRings { compactRings }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Sugerencia Inteligente")
                    .font(.caption.weight(.semibold))
                Text(entry.smartSuggestion)
                    .font(includeRings ? .subheadline.weight(.medium) : .footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(includeRings ? 5 : 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if includeRings {
                Text("Balance ajustado \(entry.adjustedDelta <= 0 ? "" : "+")\(Int(entry.adjustedDelta.rounded())) kcal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(entry.adjustedDelta > 0 ? .red : .green)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var balanceProgress: Double {
        let safeBudget = max(entry.adjustedBudget, 1)
        return min(max(entry.consumed / safeBudget, 0), 1)
    }

    private func balanceRing(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 12)
                .opacity(0.2)
                .foregroundStyle(entry.adjustedDelta > 0 ? .red : .green)

            Circle()
                .trim(from: 0, to: balanceProgress)
                .stroke(style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .foregroundStyle(entry.adjustedDelta > 0 ? .red : .green)
                .rotationEffect(.degrees(270))

            VStack(spacing: 4) {
                Text("\(Int(entry.consumed.rounded()))")
                    .font(.system(size: size > 80 ? 22 : 18, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.7)
                Text("kcal")
                    .font(.caption2)
            }
        }
        .frame(width: size, height: size)
    }

    private func progress(_ actual: Double, _ target: Double) -> Double {
        let safe = max(target, 1)
        return min(max(actual / safe, 0), 1)
    }

    private func compactRing(progress: Double, size: CGFloat, color: Color) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: 7)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }

    private var compactRings: some View {
        ZStack {
            compactRing(progress: progress(entry.fiberActual, entry.fiberTarget), size: 84, color: .green)
            compactRing(progress: progress(entry.fatActual, entry.fatTarget), size: 66, color: .purple)
            compactRing(progress: progress(entry.carbsActual, entry.carbsTarget), size: 48, color: .orange)
            compactRing(progress: progress(entry.proteinActual, entry.proteinTarget), size: 30, color: .blue)
        }
        .frame(width: 96, height: 96)
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
            SuggestionWidgetView(entry: entry, includeRings: false)
        }
        .configurationDisplayName("Balance + Sugerencia")
        .description("Balance diario con sugerencia inteligente.")
        .supportedFamilies([.systemMedium])
    }
}

struct ClassicBalanceWidget: Widget {
    let kind = "ClassicBalanceWidget"

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
            RingsWidgetView(entry: entry)
        }
        .configurationDisplayName("Anillos de Macros")
        .description("Anillos pequeños de proteína, carbos, grasas y fibra.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SmartDashboardWidget: Widget {
    let kind = "SmartDashboardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalorieProvider()) { entry in
            SuggestionWidgetView(entry: entry, includeRings: true)
        }
        .configurationDisplayName("Balance Smart")
        .description("Balance diario, anillos y sugerencia inteligente.")
        .supportedFamilies([.systemLarge])
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
