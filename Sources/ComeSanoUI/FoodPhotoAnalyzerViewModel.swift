import Foundation
import ComeSanoCore
import ComeSanoAI

@MainActor
public final class FoodPhotoAnalyzerViewModel: ObservableObject {
    @Published public private(set) var result: NutritionInferenceResult?
    @Published public private(set) var isLoading = false
    @Published public private(set) var isSaving = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var saveMessage: String?
    @Published public private(set) var saveErrorMessage: String?
    @Published public private(set) var shoppingSaveMessage: String?
    @Published public private(set) var shoppingSaveErrorMessage: String?
    @Published public private(set) var retryAfterSeconds: Int?

    private var aiClient: MultimodalNutritionInference
    private let foodStore: FoodCatalogStore?
    private let shoppingStore: ShoppingListStore?
    private let dietaryWriter: DietaryEnergyWriter?
    private var lastImageData: Data?
    private var lastUserInstruction = ""
    private var retryCountdownTask: Task<Void, Never>?

    public init(
        aiClient: MultimodalNutritionInference,
        foodStore: FoodCatalogStore? = nil,
        shoppingStore: ShoppingListStore? = nil,
        dietaryWriter: DietaryEnergyWriter? = nil
    ) {
        self.aiClient = aiClient
        self.foodStore = foodStore
        self.shoppingStore = shoppingStore
        self.dietaryWriter = dietaryWriter
    }

    public func updateAIClient(_ client: MultimodalNutritionInference) {
        aiClient = client
    }

    public func analyze(imageData: Data, userInstruction: String = "") async {
        isLoading = true
        errorMessage = nil
        saveMessage = nil
        saveErrorMessage = nil
        shoppingSaveMessage = nil
        shoppingSaveErrorMessage = nil
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

    public func saveCurrentFoodItems() async {
        guard let foodStore else {
            saveErrorMessage = "No hay almacenamiento configurado para guardar alimentos."
            return
        }

        guard let result, !result.foodItems.isEmpty else {
            saveErrorMessage = "No hay alimentos detectados para guardar."
            return
        }

        isSaving = true
        saveMessage = nil
        saveErrorMessage = nil

        do {
            let existingItems = try await foodStore.fetchFoodItems()
            let mergedItems = existingItems + result.foodItems
            try await foodStore.save(foodItems: mergedItems)

            if let dietaryWriter {
                for item in result.foodItems {
                    let loggedAt = item.loggedAt ?? .now
                    try await dietaryWriter.saveDietaryEnergy(kilocalories: item.nutrition.calories, at: loggedAt)
                }
            }

            saveMessage = "Comida guardada correctamente."
        } catch {
            saveErrorMessage = "No se pudo guardar la comida: \(error.localizedDescription)"
        }

        isSaving = false
    }

    public func saveCurrentShoppingList() async {
        guard let shoppingStore else {
            shoppingSaveErrorMessage = "No hay almacenamiento configurado para la lista del súper."
            return
        }

        guard let result, !result.shoppingList.isEmpty else {
            shoppingSaveErrorMessage = "No hay productos sugeridos para guardar."
            return
        }

        isSaving = true
        shoppingSaveMessage = nil
        shoppingSaveErrorMessage = nil

        do {
            let existing = try await shoppingStore.fetchShoppingItems()
            let merged = mergeShoppingItems(existing: existing, incoming: result.shoppingList)
            try await shoppingStore.save(shoppingItems: merged)
            shoppingSaveMessage = "Lista del súper guardada correctamente."
        } catch {
            shoppingSaveErrorMessage = "No se pudo guardar la lista del súper: \(error.localizedDescription)"
        }

        isSaving = false
    }

    public func retryLastAnalysis() async {
        guard let lastImageData else { return }
        await analyze(imageData: lastImageData, userInstruction: lastUserInstruction)
    }

    public func resetAnalysisState() {
        result = nil
        errorMessage = nil
        saveMessage = nil
        saveErrorMessage = nil
        shoppingSaveMessage = nil
        shoppingSaveErrorMessage = nil
        retryAfterSeconds = nil
        isLoading = false
        isSaving = false
        lastImageData = nil
        lastUserInstruction = ""
        retryCountdownTask?.cancel()
        retryCountdownTask = nil
    }

    deinit {
        retryCountdownTask?.cancel()
    }

    private func buildUserFacingError(from error: Error) -> String {
        guard case let AIClientError.invalidResponse(provider, statusCode, message) = error else {
            return "No se pudo analizar la imagen: \(error.localizedDescription)"
        }

        guard statusCode == 429 else {
            if provider == "Gemini", statusCode == 404, message.lowercased().contains("no longer available") {
                return "El modelo de Gemini configurado ya no está disponible para tu cuenta. Actualiza la app y vuelve a intentar."
            }
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

    private func mergeShoppingItems(existing: [ShoppingListItem], incoming: [ShoppingListItem]) -> [ShoppingListItem] {
        var merged = existing
        for item in incoming {
            if merged.contains(where: { $0.name.compare(item.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
                continue
            }
            merged.append(item)
        }
        return merged
    }
}
