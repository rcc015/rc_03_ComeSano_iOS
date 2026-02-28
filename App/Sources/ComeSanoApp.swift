import SwiftUI
import ComeSanoCore
import ComeSanoUI
import ComeSanoAI

@main
struct ComeSanoApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

private struct RootView: View {
    private let dashboardViewModel: DashboardViewModel
    @StateObject private var photoAnalyzerViewModel: FoodPhotoAnalyzerViewModel
    @StateObject private var keychainStore: OpenAIKeychainStore

    init() {
        let profile = UserProfile(
            name: "Usuario",
            age: 30,
            heightCM: 170,
            weightKG: 75,
            primaryGoal: .loseFat,
            dailyCalorieTarget: 2100
        )

        dashboardViewModel = DashboardViewModel(
            profile: profile,
            burnProvider: MockBurnProvider(),
            intakeProvider: MockIntakeProvider()
        )

        let keyStore = OpenAIKeychainStore()
        let key = keyStore.currentKey() ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        _photoAnalyzerViewModel = StateObject(
            wrappedValue: FoodPhotoAnalyzerViewModel(aiClient: Self.makeAIClient(apiKey: key))
        )
        _keychainStore = StateObject(wrappedValue: keyStore)
    }

    var body: some View {
        TabView {
            DashboardView(viewModel: dashboardViewModel)
                .tabItem {
                    Label("Progreso", systemImage: "chart.line.uptrend.xyaxis")
                }

            FoodPhotoAnalyzerView(viewModel: photoAnalyzerViewModel)
                .tabItem {
                    Label("Foto", systemImage: "camera")
                }

            OpenAISettingsView(keychainStore: keychainStore) { updatedKey in
                photoAnalyzerViewModel.updateAIClient(Self.makeAIClient(apiKey: updatedKey))
            }
            .tabItem {
                Label("IA", systemImage: "key")
            }
        }
    }

    private static func makeAIClient(apiKey: String?) -> MultimodalNutritionInference {
        guard let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return EmptyNutritionInference()
        }
        return NutritionAIClientFactory.makeOpenAI(apiKey: apiKey, model: .gpt4point1mini)
    }
}

private struct EmptyNutritionInference: MultimodalNutritionInference {
    func inferNutrition(fromImageData data: Data, prompt: String) async throws -> NutritionInferenceResult {
        _ = data
        _ = prompt
        return NutritionInferenceResult(
            foodItems: [],
            shoppingList: [],
            notes: "Configura OPENAI_API_KEY en Keychain (tab IA) o variable de entorno."
        )
    }
}
