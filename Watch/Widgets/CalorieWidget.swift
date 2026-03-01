import WidgetKit
import SwiftUI
import Foundation

struct CalorieEntry: TimelineEntry {
    let date: Date
    let caloriasConsumidas: Double
    let metaCalorias: Double
}

struct CalorieProvider: TimelineProvider {
    private enum Shared {
        static let appGroupID = "group.rcTools.ComeSano"
        static let consumedKey = "widget.calories.consumed"
        static let goalKey = "widget.calories.goal"
    }

    func placeholder(in context: Context) -> CalorieEntry {
        CalorieEntry(date: .now, caloriasConsumidas: 1450, metaCalorias: 2000)
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
        let defaults = UserDefaults(suiteName: Shared.appGroupID)
        let consumed = defaults?.double(forKey: Shared.consumedKey) ?? 0
        let goal = defaults?.double(forKey: Shared.goalKey) ?? 2000
        return CalorieEntry(
            date: .now,
            caloriasConsumidas: consumed,
            metaCalorias: max(goal, 1)
        )
    }
}

struct CalorieComplicationEntryView: View {
    var entry: CalorieProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: entry.caloriasConsumidas, in: 0...entry.metaCalorias) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
            } currentValueLabel: {
                Text("\(Int(entry.caloriasConsumidas.rounded()))")
                    .font(.system(.body, design: .rounded))
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Gradient(colors: [.green, .mint]))

        case .accessoryRectangular:
            VStack(alignment: .leading) {
                HStack {
                    Image(systemName: "flame.fill").foregroundStyle(.orange)
                    Text("Calorías")
                        .font(.headline)
                }
                Gauge(value: entry.caloriasConsumidas, in: 0...entry.metaCalorias) {
                    EmptyView()
                } currentValueLabel: {
                    Text("\(Int(entry.caloriasConsumidas.rounded())) / \(Int(entry.metaCalorias.rounded()))")
                }
                .gaugeStyle(.accessoryLinear)
                .tint(Gradient(colors: [.green, .mint]))
            }

        case .accessoryCorner:
            Gauge(value: entry.caloriasConsumidas, in: 0...entry.metaCalorias) {
                Image(systemName: "flame.fill")
            } currentValueLabel: {
                Text("\(Int(entry.caloriasConsumidas.rounded()))")
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Gradient(colors: [.green, .mint]))

        default:
            Text("\(Int(entry.caloriasConsumidas.rounded()))")
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
