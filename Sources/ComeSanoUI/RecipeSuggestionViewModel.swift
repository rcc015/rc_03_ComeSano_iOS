import Foundation
import ComeSanoCore
import ComeSanoAI

@MainActor
public final class RecipeSuggestionViewModel: ObservableObject {
    @Published public private(set) var recipes: [RecipeSuggestion] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var isSaving = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var saveMessage: String?
    @Published public private(set) var saveErrorMessage: String?
    @Published public private(set) var limitStatusMessage: String?

    private var aiClient: MultimodalRecipeInference
    private let shoppingStore: ShoppingListStore?
    private let limitKeyPrefix = "ai.limit.recipes"

    public init(aiClient: MultimodalRecipeInference, shoppingStore: ShoppingListStore? = nil) {
        self.aiClient = aiClient
        self.shoppingStore = shoppingStore
        refreshLimitStatus()
    }

    public func updateAIClient(_ client: MultimodalRecipeInference) {
        aiClient = client
    }

    public func analyze(imagesData: [Data], userInstruction: String = "") async {
        switch evaluateRateLimit() {
        case .allowed:
            break
        case .cooldown(let seconds):
            errorMessage = "Espera \(seconds)s antes de volver a generar recetas."
            refreshLimitStatus()
            return
        case .dailyLimitReached(let max):
            errorMessage = "Límite diario alcanzado (\(max) análisis de recetas)."
            refreshLimitStatus()
            return
        }

        isLoading = true
        errorMessage = nil
        saveMessage = nil
        saveErrorMessage = nil

        do {
            recipes = try await aiClient.inferRecipes(fromImageData: imagesData, prompt: userInstruction)
        } catch {
            recipes = []
            errorMessage = "No se pudieron generar recetas: \(error.localizedDescription)"
        }

        isLoading = false
        refreshLimitStatus()
    }

    public func saveMissingIngredientsToShoppingList() async {
        guard let shoppingStore else {
            saveErrorMessage = "No hay almacenamiento configurado para la lista del súper."
            return
        }

        let missing = recipes.flatMap(\.ingredientesFaltantes)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !missing.isEmpty else {
            saveErrorMessage = "No hay ingredientes faltantes para guardar."
            return
        }

        isSaving = true
        saveMessage = nil
        saveErrorMessage = nil

        do {
            let existing = try await shoppingStore.fetchShoppingItems()
            var merged = existing
            for ingredient in missing {
                if merged.contains(where: { $0.name.compare(ingredient, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
                    continue
                }
                merged.append(
                    ShoppingListItem(
                        name: ingredient,
                        category: "Recetas IA",
                        quantity: 1,
                        unit: "pieza",
                        isPurchased: false
                    )
                )
            }
            try await shoppingStore.save(shoppingItems: merged)
            saveMessage = "Ingredientes faltantes guardados en la lista del súper."
        } catch {
            saveErrorMessage = "No se pudo guardar la lista: \(error.localizedDescription)"
        }

        isSaving = false
    }

    public func refreshLimitStatus() {
        let status = currentLimitStatus()
        let cooldownPart = status.cooldownRemaining > 0 ? " · espera \(status.cooldownRemaining)s" : ""
        limitStatusMessage = "Te quedan \(status.remainingToday) análisis de recetas hoy\(cooldownPart)."
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
