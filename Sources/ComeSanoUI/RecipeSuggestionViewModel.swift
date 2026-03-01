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

    private var aiClient: MultimodalRecipeInference
    private let shoppingStore: ShoppingListStore?

    public init(aiClient: MultimodalRecipeInference, shoppingStore: ShoppingListStore? = nil) {
        self.aiClient = aiClient
        self.shoppingStore = shoppingStore
    }

    public func updateAIClient(_ client: MultimodalRecipeInference) {
        aiClient = client
    }

    public func analyze(imagesData: [Data], userInstruction: String = "") async {
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
}
