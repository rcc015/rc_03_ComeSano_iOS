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
    private let photoAnalyzerViewModel: FoodPhotoAnalyzerViewModel

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

        let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
        let aiClient: MultimodalNutritionInference
        if apiKey.isEmpty {
            aiClient = EmptyNutritionInference()
        } else {
            aiClient = NutritionAIClientFactory.makeOpenAI(apiKey: apiKey, model: .gpt4point1mini)
        }

        photoAnalyzerViewModel = FoodPhotoAnalyzerViewModel(aiClient: aiClient)
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
        }
    }
}

private struct EmptyNutritionInference: MultimodalNutritionInference {
    func inferNutrition(fromImageData data: Data, prompt: String) async throws -> NutritionInferenceResult {
        _ = data
        _ = prompt
        return NutritionInferenceResult(
            foodItems: [],
            shoppingList: [],
            notes: "Falta OPENAI_API_KEY en el esquema de ejecución."
        )
    }
}
