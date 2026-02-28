import Foundation

public enum PrimaryGoal: String, Codable, Sendable {
    case loseFat
    case maintain
    case gainMuscle
}

public struct UserProfile: Codable, Sendable {
    public var name: String
    public var age: Int
    public var heightCM: Double
    public var weightKG: Double
    public var primaryGoal: PrimaryGoal
    public var dailyCalorieTarget: Double
    public var hydrationTargetML: Int

    public init(
        name: String,
        age: Int,
        heightCM: Double,
        weightKG: Double,
        primaryGoal: PrimaryGoal,
        dailyCalorieTarget: Double,
        hydrationTargetML: Int = 2500
    ) {
        self.name = name
        self.age = age
        self.heightCM = heightCM
        self.weightKG = weightKG
        self.primaryGoal = primaryGoal
        self.dailyCalorieTarget = dailyCalorieTarget
        self.hydrationTargetML = hydrationTargetML
    }
}
