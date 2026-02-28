import Foundation
import ComeSanoCore
import ComeSanoAI

@MainActor
public final class FoodPhotoAnalyzerViewModel: ObservableObject {
    @Published public private(set) var result: NutritionInferenceResult?
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var retryAfterSeconds: Int?

    private var aiClient: MultimodalNutritionInference
    private var lastImageData: Data?
    private var lastUserInstruction = ""
    private var retryCountdownTask: Task<Void, Never>?

    public init(aiClient: MultimodalNutritionInference) {
        self.aiClient = aiClient
    }

    public func updateAIClient(_ client: MultimodalNutritionInference) {
        aiClient = client
    }

    public func analyze(imageData: Data, userInstruction: String = "") async {
        isLoading = true
        errorMessage = nil
        retryAfterSeconds = nil
        retryCountdownTask?.cancel()
        lastImageData = imageData
        lastUserInstruction = userInstruction

        do {
            let inference = try await aiClient.inferNutrition(fromImageData: imageData, prompt: userInstruction)
            result = inference
        } catch {
            errorMessage = buildUserFacingError(from: error)
        }

        isLoading = false
    }

    public func retryLastAnalysis() async {
        guard let lastImageData else { return }
        await analyze(imageData: lastImageData, userInstruction: lastUserInstruction)
    }

    deinit {
        retryCountdownTask?.cancel()
    }

    private func buildUserFacingError(from error: Error) -> String {
        guard case let AIClientError.invalidResponse(provider, statusCode, message) = error else {
            return "No se pudo analizar la imagen: \(error.localizedDescription)"
        }

        guard statusCode == 429 else {
            return "No se pudo analizar la imagen: \(error.localizedDescription)"
        }

        if let seconds = Self.extractRetryAfterSeconds(from: message) {
            startRetryCountdown(from: seconds)
            return "\(provider) sin cuota disponible en este momento. Reintenta en \(seconds)s o revisa límites/facturación."
        }

        return "\(provider) sin cuota disponible. Revisa límites/facturación y vuelve a intentar."
    }

    private func startRetryCountdown(from seconds: Int) {
        let safeSeconds = max(0, seconds)
        retryAfterSeconds = safeSeconds

        retryCountdownTask = Task { @MainActor in
            var remaining = safeSeconds
            while remaining > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                remaining -= 1
                retryAfterSeconds = remaining
            }
        }
    }

    private static func extractRetryAfterSeconds(from message: String) -> Int? {
        let lowercased = message.lowercased()
        guard let range = lowercased.range(of: "retry in ") else { return nil }
        let start = lowercased[range.upperBound...]
        guard let endIndex = start.firstIndex(of: "s") else { return nil }
        let numberText = start[..<endIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(numberText), value.isFinite else { return nil }
        return Int(ceil(value))
    }
}
