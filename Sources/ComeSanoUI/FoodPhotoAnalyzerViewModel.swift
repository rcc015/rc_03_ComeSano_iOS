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
    @Published public private(set) var limitStatusMessage: String?

    private var aiClient: MultimodalNutritionInference
    private let foodStore: FoodCatalogStore?
    private let shoppingStore: ShoppingListStore?
    private let dietaryWriter: DietaryEnergyWriter?
    private var lastImageData: Data?
    private var lastUserInstruction = ""
    private var retryCountdownTask: Task<Void, Never>?
    private let limitKeyPrefix = "ai.limit.photo"

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
        refreshLimitStatus()
    }

    public func updateAIClient(_ client: MultimodalNutritionInference) {
        aiClient = client
    }

    public func analyze(imageData: Data, userInstruction: String = "") async {
        switch evaluateRateLimit() {
        case .allowed:
            break
        case .cooldown(let seconds):
            errorMessage = "Espera \(seconds)s antes de volver a analizar."
            refreshLimitStatus()
            return
        case .dailyLimitReached(let max):
            errorMessage = "Límite diario alcanzado (\(max) análisis)."
            refreshLimitStatus()
            return
        }

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
        refreshLimitStatus()
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

    public func clearCurrentAnalysis() {
        result = nil
        errorMessage = nil
        saveMessage = nil
        saveErrorMessage = nil
        shoppingSaveMessage = nil
        shoppingSaveErrorMessage = nil
        retryAfterSeconds = nil
        retryCountdownTask?.cancel()
        refreshLimitStatus()
    }

    public func refreshLimitStatus() {
        let status = currentLimitStatus()
        let cooldownPart = status.cooldownRemaining > 0 ? " · espera \(status.cooldownRemaining)s" : ""
        limitStatusMessage = "Te quedan \(status.remainingToday) análisis hoy\(cooldownPart)."
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

    private enum LimitDecision {
        case allowed
        case cooldown(Int)
        case dailyLimitReached(Int)
    }

    private func evaluateRateLimit(now: Date = .now) -> LimitDecision {
        let defaults = UserDefaults.standard
        let cooldown = max(defaults.integer(forKey: "ai.shared.cooldown_seconds"), 1)
        let dailyLimit = max(defaults.integer(forKey: "ai.shared.daily_limit"), 1)

        if let last = defaults.object(forKey: "\(limitKeyPrefix).lastAttempt") as? Date {
            let elapsed = Int(now.timeIntervalSince(last))
            if elapsed < cooldown {
                return .cooldown(max(1, cooldown - elapsed))
            }
        }

        let dayKey = Self.dayStamp(from: now)
        let storedDay = defaults.string(forKey: "\(limitKeyPrefix).day") ?? ""
        var count = defaults.integer(forKey: "\(limitKeyPrefix).count")
        if storedDay != dayKey {
            count = 0
        }

        if count >= dailyLimit {
            return .dailyLimitReached(dailyLimit)
        }

        defaults.set(now, forKey: "\(limitKeyPrefix).lastAttempt")
        defaults.set(dayKey, forKey: "\(limitKeyPrefix).day")
        defaults.set(count + 1, forKey: "\(limitKeyPrefix).count")
        return .allowed
    }

    private func currentLimitStatus(now: Date = .now) -> (remainingToday: Int, cooldownRemaining: Int) {
        let defaults = UserDefaults.standard
        let cooldown = max(defaults.integer(forKey: "ai.shared.cooldown_seconds"), 1)
        let dailyLimit = max(defaults.integer(forKey: "ai.shared.daily_limit"), 1)

        let dayKey = Self.dayStamp(from: now)
        let storedDay = defaults.string(forKey: "\(limitKeyPrefix).day") ?? ""
        let count = storedDay == dayKey ? defaults.integer(forKey: "\(limitKeyPrefix).count") : 0
        let remaining = max(0, dailyLimit - count)

        var cooldownRemaining = 0
        if let last = defaults.object(forKey: "\(limitKeyPrefix).lastAttempt") as? Date {
            let elapsed = Int(now.timeIntervalSince(last))
            if elapsed < cooldown {
                cooldownRemaining = max(1, cooldown - elapsed)
            }
        }

        return (remaining, cooldownRemaining)
    }

    private static func dayStamp(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
