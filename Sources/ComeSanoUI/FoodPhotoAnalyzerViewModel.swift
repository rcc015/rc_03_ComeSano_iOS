import Foundation
import ComeSanoCore
import ComeSanoAI

@MainActor
public final class FoodPhotoAnalyzerViewModel: ObservableObject {
    @Published public private(set) var result: NutritionInferenceResult?
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?

    private var aiClient: MultimodalNutritionInference

    public init(aiClient: MultimodalNutritionInference) {
        self.aiClient = aiClient
    }

    public func updateAIClient(_ client: MultimodalNutritionInference) {
        aiClient = client
    }

    public func analyze(imageData: Data, userInstruction: String = "") async {
        isLoading = true
        errorMessage = nil

        do {
            let inference = try await aiClient.inferNutrition(fromImageData: imageData, prompt: userInstruction)
            result = inference
        } catch {
            errorMessage = "No se pudo analizar la imagen: \(error.localizedDescription)"
        }

        isLoading = false
    }
}
