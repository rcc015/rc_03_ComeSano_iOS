import Foundation
import ComeSanoCore

@MainActor
final class UserProfileStore: ObservableObject {
    @Published private(set) var profile: UserProfile
    @Published private(set) var hasCompletedOnboarding: Bool

    private let defaults: UserDefaults

    private enum Keys {
        static let name = "profile.name"
        static let age = "profile.age"
        static let heightCM = "profile.heightCM"
        static let weightKG = "profile.weightKG"
        static let goal = "profile.goal"
        static let dailyCalories = "profile.dailyCalories"
        static let hydrationML = "profile.hydrationML"
        static let hasCompletedOnboarding = "profile.onboarding.completed"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.profile = Self.loadProfile(from: defaults)
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
    }

    func save(profile: UserProfile, markOnboardingDone: Bool = true) {
        self.profile = profile
        defaults.set(profile.name, forKey: Keys.name)
        defaults.set(profile.age, forKey: Keys.age)
        defaults.set(profile.heightCM, forKey: Keys.heightCM)
        defaults.set(profile.weightKG, forKey: Keys.weightKG)
        defaults.set(profile.primaryGoal.rawValue, forKey: Keys.goal)
        defaults.set(profile.dailyCalorieTarget, forKey: Keys.dailyCalories)
        defaults.set(profile.hydrationTargetML, forKey: Keys.hydrationML)
        if markOnboardingDone {
            hasCompletedOnboarding = true
            defaults.set(true, forKey: Keys.hasCompletedOnboarding)
        }
    }

    private static func loadProfile(from defaults: UserDefaults) -> UserProfile {
        let name = defaults.string(forKey: Keys.name) ?? "Usuario"
        let age = defaults.object(forKey: Keys.age) as? Int ?? 30
        let heightCM = defaults.object(forKey: Keys.heightCM) as? Double ?? 170
        let weightKG = defaults.object(forKey: Keys.weightKG) as? Double ?? 75
        let dailyCalories = defaults.object(forKey: Keys.dailyCalories) as? Double ?? 2100
        let hydrationML = defaults.object(forKey: Keys.hydrationML) as? Int ?? 2500
        let goalRaw = defaults.string(forKey: Keys.goal) ?? PrimaryGoal.loseFat.rawValue
        let goal = PrimaryGoal(rawValue: goalRaw) ?? .loseFat

        return UserProfile(
            name: name,
            age: age,
            heightCM: heightCM,
            weightKG: weightKG,
            primaryGoal: goal,
            dailyCalorieTarget: dailyCalories,
            hydrationTargetML: hydrationML
        )
    }
}
