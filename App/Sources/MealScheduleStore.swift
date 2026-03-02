import Foundation

@MainActor
final class MealScheduleStore: ObservableObject {
    @Published var breakfastHour: Int
    @Published var breakfastMinute: Int
    @Published var snack1Hour: Int
    @Published var snack1Minute: Int
    @Published var lunchHour: Int
    @Published var lunchMinute: Int
    @Published var snack2Hour: Int
    @Published var snack2Minute: Int
    @Published var dinnerHour: Int
    @Published var dinnerMinute: Int

    private let defaults: UserDefaults

    private enum Keys {
        static let breakfastHour = "meal.schedule.breakfast.hour"
        static let breakfastMinute = "meal.schedule.breakfast.minute"
        static let snack1Hour = "meal.schedule.snack1.hour"
        static let snack1Minute = "meal.schedule.snack1.minute"
        static let lunchHour = "meal.schedule.lunch.hour"
        static let lunchMinute = "meal.schedule.lunch.minute"
        static let snack2Hour = "meal.schedule.snack2.hour"
        static let snack2Minute = "meal.schedule.snack2.minute"
        static let dinnerHour = "meal.schedule.dinner.hour"
        static let dinnerMinute = "meal.schedule.dinner.minute"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        breakfastHour = Self.readInt(defaults, Keys.breakfastHour, fallback: 10)
        breakfastMinute = Self.readInt(defaults, Keys.breakfastMinute, fallback: 30)
        snack1Hour = Self.readInt(defaults, Keys.snack1Hour, fallback: 13)
        snack1Minute = Self.readInt(defaults, Keys.snack1Minute, fallback: 0)
        lunchHour = Self.readInt(defaults, Keys.lunchHour, fallback: 15)
        lunchMinute = Self.readInt(defaults, Keys.lunchMinute, fallback: 30)
        snack2Hour = Self.readInt(defaults, Keys.snack2Hour, fallback: 18)
        snack2Minute = Self.readInt(defaults, Keys.snack2Minute, fallback: 30)
        dinnerHour = Self.readInt(defaults, Keys.dinnerHour, fallback: 21)
        dinnerMinute = Self.readInt(defaults, Keys.dinnerMinute, fallback: 0)
    }

    func save() {
        defaults.set(breakfastHour, forKey: Keys.breakfastHour)
        defaults.set(breakfastMinute, forKey: Keys.breakfastMinute)
        defaults.set(snack1Hour, forKey: Keys.snack1Hour)
        defaults.set(snack1Minute, forKey: Keys.snack1Minute)
        defaults.set(lunchHour, forKey: Keys.lunchHour)
        defaults.set(lunchMinute, forKey: Keys.lunchMinute)
        defaults.set(snack2Hour, forKey: Keys.snack2Hour)
        defaults.set(snack2Minute, forKey: Keys.snack2Minute)
        defaults.set(dinnerHour, forKey: Keys.dinnerHour)
        defaults.set(dinnerMinute, forKey: Keys.dinnerMinute)
    }

    func resetDefaults() {
        breakfastHour = 10
        breakfastMinute = 30
        snack1Hour = 13
        snack1Minute = 0
        lunchHour = 15
        lunchMinute = 30
        snack2Hour = 18
        snack2Minute = 30
        dinnerHour = 21
        dinnerMinute = 0
        save()
    }

    func timeString(hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    var breakfastTime: String { timeString(hour: breakfastHour, minute: breakfastMinute) }
    var snack1Time: String { timeString(hour: snack1Hour, minute: snack1Minute) }
    var lunchTime: String { timeString(hour: lunchHour, minute: lunchMinute) }
    var snack2Time: String { timeString(hour: snack2Hour, minute: snack2Minute) }
    var dinnerTime: String { timeString(hour: dinnerHour, minute: dinnerMinute) }

    private static func readInt(_ defaults: UserDefaults, _ key: String, fallback: Int) -> Int {
        if defaults.object(forKey: key) == nil {
            return fallback
        }
        return defaults.integer(forKey: key)
    }
}
