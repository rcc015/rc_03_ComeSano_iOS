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
    @StateObject private var keychainStore: AIKeychainStore

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

        let keyStore = AIKeychainStore()
        _photoAnalyzerViewModel = StateObject(
            wrappedValue: FoodPhotoAnalyzerViewModel(aiClient: Self.makeAIClient(from: keyStore))
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

            AISettingsView(keychainStore: keychainStore) {
                photoAnalyzerViewModel.updateAIClient(Self.makeAIClient(from: keychainStore))
            }
            .tabItem {
                Label("IA", systemImage: "key")
            }
        }
    }

    private static func makeAIClient(from store: AIKeychainStore) -> MultimodalNutritionInference {
        let openAIKey = store.key(for: .openAI) ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        let geminiKey = store.key(for: .gemini) ?? ProcessInfo.processInfo.environment["GEMINI_API_KEY"]

        let openAIClient = openAIKey.flatMap { key -> MultimodalNutritionInference? in
            guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return NutritionAIClientFactory.makeOpenAI(apiKey: key, model: .gpt4point1mini)
        }

        let geminiClient = geminiKey.flatMap { key -> MultimodalNutritionInference? in
            guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return NutritionAIClientFactory.makeGemini(apiKey: key, model: .gemini2Flash)
        }

        switch store.primaryProvider {
        case .openAI:
            if let openAIClient {
                return NutritionAIClientFactory.makeWithFallback(primary: openAIClient, secondary: geminiClient)
            }
            if let geminiClient {
                return geminiClient
            }
        case .gemini:
            if let geminiClient {
                return NutritionAIClientFactory.makeWithFallback(primary: geminiClient, secondary: openAIClient)
            }
            if let openAIClient {
                return openAIClient
            }
        }

        return EmptyNutritionInference()
    }
}

private struct EmptyNutritionInference: MultimodalNutritionInference {
    func inferNutrition(fromImageData data: Data, prompt: String) async throws -> NutritionInferenceResult {
        _ = data
        _ = prompt
        return NutritionInferenceResult(
            foodItems: [],
            shoppingList: [],
            notes: "Configura OPENAI_API_KEY o GEMINI_API_KEY en la pestaña IA."
        )
    }
}
