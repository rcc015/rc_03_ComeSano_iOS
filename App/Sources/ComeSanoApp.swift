import SwiftUI
import ComeSanoCore
import ComeSanoUI
import ComeSanoAI
import ComeSanoPersistence
import ComeSanoHealthKit
#if os(iOS)
import UIKit
#endif

@main
struct ComeSanoApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

private struct RootView: View {
    private enum AppTab: Hashable {
        case progress
        case plan
        case camera
        case recipes
        case grocery
    }

    private let dashboardViewModel: DashboardViewModel
    private let stores: CoreDataStores
    private let healthStore: HealthKitNutritionStore
    @StateObject private var photoAnalyzerViewModel: FoodPhotoAnalyzerViewModel
    @StateObject private var recipeSuggestionViewModel: RecipeSuggestionViewModel
    @StateObject private var groceryListViewModel: GroceryListViewModel
    @StateObject private var profileStore: UserProfileStore
    @StateObject private var planStore: NutritionPlanStore
    @StateObject private var keychainStore: AIKeychainStore
    @StateObject private var reminderManager: ReminderNotificationManager
    @StateObject private var watchConnector: WatchConnector
    @State private var hasRequestedHealthAuthorization = false
    @State private var selectedTab: AppTab = .progress
    @State private var isShowingAISettings = false
    @State private var isShowingDietaryProfile = false
    @State private var isShowingFridgeScannerForGrocery = false
    @State private var healthBodyMetrics: HealthBodyMetrics?

    init() {
        let profileStore = UserProfileStore()
        let profile = profileStore.profile

        let persistence = PersistenceController()
        let stores = CoreDataStores(controller: persistence)
        self.stores = stores
        let healthStore = HealthKitNutritionStore()
        self.healthStore = healthStore

        dashboardViewModel = DashboardViewModel(
            profile: profile,
            burnProvider: healthStore,
            intakeProvider: stores
        )

        let keyStore = AIKeychainStore()
        _photoAnalyzerViewModel = StateObject(
            wrappedValue: FoodPhotoAnalyzerViewModel(
                aiClient: Self.makeAIClient(from: keyStore),
                foodStore: stores,
                shoppingStore: stores,
                dietaryWriter: healthStore
            )
        )
        _recipeSuggestionViewModel = StateObject(
            wrappedValue: RecipeSuggestionViewModel(
                aiClient: Self.makeRecipeAIClient(from: keyStore),
                shoppingStore: stores
            )
        )
        _groceryListViewModel = StateObject(wrappedValue: GroceryListViewModel(shoppingStore: stores))
        _profileStore = StateObject(wrappedValue: profileStore)
        _planStore = StateObject(wrappedValue: NutritionPlanStore())
        _keychainStore = StateObject(wrappedValue: keyStore)
        _reminderManager = StateObject(wrappedValue: ReminderNotificationManager())
        _watchConnector = StateObject(wrappedValue: WatchConnector.shared)
        _isShowingDietaryProfile = State(initialValue: false)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                DashboardView(viewModel: dashboardViewModel, onQuickAdd: handleQuickAdd)
                    .tag(AppTab.progress)
                    .tabItem {
                        Label("Progreso", systemImage: "chart.line.uptrend.xyaxis")
                    }

                PlanDailyView(
                    planStore: planStore,
                    onCreatePlanTap: {
                        Task {
                            await ensureHealthDataLoaded()
                            isShowingDietaryProfile = true
                        }
                    },
                    onGenerateWeeklyPlanTap: { slot, ajustes, ingredientesRefri in
                        try await generateWeeklyPlan(slot: slot, ajustes: ajustes, ingredientesRefri: ingredientesRefri)
                    },
                    onGenerateWeeklyGroceryTap: { weeklyPlan, ingredientesRefri, replaceExisting in
                        try await generateWeeklyGroceryList(for: weeklyPlan, ingredientesRefri: ingredientesRefri, replaceExisting: replaceExisting)
                    },
                    onAnalyzeFridgeTap: { imagesData in
                        try await analyzeFridgeIngredients(from: imagesData)
                    }
                )
                .tag(AppTab.plan)
                .tabItem {
                    Label("Plan", systemImage: "list.bullet.clipboard")
                }

                CameraAnalysisView(viewModel: photoAnalyzerViewModel)
                    .tag(AppTab.camera)
                    .tabItem {
                        Label("Foto", systemImage: "camera")
                    }

                RecipeSuggestionView(viewModel: recipeSuggestionViewModel)
                    .tag(AppTab.recipes)
                    .tabItem {
                        Label("Recetas", systemImage: "fork.knife")
                    }

                GroceryListView(viewModel: groceryListViewModel) {
                    isShowingFridgeScannerForGrocery = true
                }
                .tag(AppTab.grocery)
                .tabItem {
                    Label("Súper", systemImage: "cart")
                }
            }

            Button {
                #if os(iOS)
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                #endif
                isShowingAISettings = true
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.35), lineWidth: 0.8)
                        )

                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 56, height: 56)
                .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(FloatingSettingsButtonStyle())
            .padding(.trailing, 18)
            .padding(.bottom, 92)
            .accessibilityLabel("Ajustes de IA")
        }
        .sheet(isPresented: $isShowingFridgeScannerForGrocery) {
            #if os(iOS)
            FridgeInventoryScannerView(
                onAnalyze: { imagesData in
                    try await analyzeFridgeIngredients(from: imagesData)
                },
                onApplyIngredients: { ingredients in
                    Task {
                        try? await applyFridgeInventoryToShoppingList(ingredients: ingredients)
                        await groceryListViewModel.refresh()
                    }
                }
            )
            #else
            Text("Escáner de refri solo disponible en iOS")
            #endif
        }
        .sheet(isPresented: $isShowingAISettings) {
            AISettingsView(keychainStore: keychainStore, reminderManager: reminderManager) {
                photoAnalyzerViewModel.updateAIClient(Self.makeAIClient(from: keychainStore))
                recipeSuggestionViewModel.updateAIClient(Self.makeRecipeAIClient(from: keychainStore))
            } onOpenDietaryProfile: {
                isShowingAISettings = false
                Task {
                    await ensureHealthDataLoaded()
                    isShowingDietaryProfile = true
                }
            }
        }
        .fullScreenCover(isPresented: $isShowingDietaryProfile) {
            DietaryProfileView(
                initialProfile: profileStore.profile,
                bodyMetrics: healthBodyMetrics,
                planGenerator: Self.makePlanGenerator(from: keychainStore)
            ) { updatedProfile, plan in
                profileStore.save(profile: updatedProfile, markOnboardingDone: true)
                planStore.save(plan)
                dashboardViewModel.updateProfile(updatedProfile)
                Task { await dashboardViewModel.refresh() }
                isShowingDietaryProfile = false
            }
        }
        .task {
            await ensureHealthDataLoaded()
            if !profileStore.hasCompletedOnboarding {
                isShowingDietaryProfile = true
            }
        }
        .onReceive(watchConnector.$lastEvent) { event in
            guard event != nil else { return }
            Task {
                await dashboardViewModel.refresh()
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            guard newValue == .progress else { return }
            if !profileStore.hasCompletedOnboarding {
                Task {
                    await ensureHealthDataLoaded()
                    isShowingDietaryProfile = true
                }
            }
        }
    }

    @MainActor
    private func ensureHealthDataLoaded() async {
        guard !hasRequestedHealthAuthorization else { return }
        hasRequestedHealthAuthorization = true

        do {
            try await healthStore.requestAuthorization()
            healthBodyMetrics = await healthStore.fetchBodyMetrics()
        } catch {
            // If authorization fails/denied, onboarding remains editable manually.
        }

        await dashboardViewModel.refresh()
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
            return NutritionAIClientFactory.makeGemini(apiKey: key, model: .gemini25Flash)
        }

        switch store.primaryProvider {
        case .openAI:
            guard let openAIClient else {
                return EmptyNutritionInference(
                    message: "Proveedor principal OpenAI seleccionado, pero no hay OPENAI_API_KEY configurada en IA."
                )
            }
            return openAIClient
        case .gemini:
            guard let geminiClient else {
                return EmptyNutritionInference(
                    message: "Proveedor principal Gemini seleccionado, pero no hay GEMINI_API_KEY configurada en IA."
                )
            }
            return geminiClient
        }
    }

    private static func makeRecipeAIClient(from store: AIKeychainStore) -> MultimodalRecipeInference {
        let openAIKey = store.key(for: .openAI) ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        let geminiKey = store.key(for: .gemini) ?? ProcessInfo.processInfo.environment["GEMINI_API_KEY"]

        let openAIClient = openAIKey.flatMap { key -> MultimodalRecipeInference? in
            guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return NutritionAIClientFactory.makeOpenAIRecipe(apiKey: key, model: .gpt4point1mini)
        }

        let geminiClient = geminiKey.flatMap { key -> MultimodalRecipeInference? in
            guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return NutritionAIClientFactory.makeGeminiRecipe(apiKey: key, model: .gemini25Flash)
        }

        switch store.primaryProvider {
        case .openAI:
            return openAIClient ?? EmptyRecipeInference(
                message: "Proveedor principal OpenAI seleccionado, pero no hay OPENAI_API_KEY configurada en IA."
            )
        case .gemini:
            return geminiClient ?? EmptyRecipeInference(
                message: "Proveedor principal Gemini seleccionado, pero no hay GEMINI_API_KEY configurada en IA."
            )
        }
    }

    private static func makePlanGenerator(from store: AIKeychainStore) -> any NutritionPlanGenerating {
        NutritionPlanRemoteGenerator(
            primaryProvider: store.primaryProvider,
            openAIKey: store.key(for: .openAI) ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
            geminiKey: store.key(for: .gemini) ?? ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
        )
    }

    private func handleQuickAdd(_ kind: DashboardView.QuickAddKind) {
        Task {
            await registerQuickAdd(kind)
        }
    }

    @MainActor
    private func registerQuickAdd(_ kind: DashboardView.QuickAddKind) async {
        let preset = QuickAddPreset.from(kind)

        do {
            if preset.calories > 0 {
                try await healthStore.saveDietaryEnergy(kilocalories: preset.calories, at: .now)
                try await saveFoodRecord(for: preset)
            }

            await dashboardViewModel.refresh()
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
        } catch {
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            #endif
        }
    }

    private func makeProfileInput() -> NutritionProfileInput {
        let profile = profileStore.profile
        return NutritionProfileInput(
            nombre: profile.name,
            sexo: "No especificado",
            edad: profile.age,
            alturaCM: profile.heightCM,
            pesoKG: profile.weightKG,
            meta: profile.primaryGoal,
            diasGym: 4,
            preferenciaAlimenticia: "Ninguna",
            alergias: ""
        )
    }

    @MainActor
    private func generateWeeklyPlan(slot: WeeklyPlanSlot, ajustes: String, ingredientesRefri: String) async throws -> WeeklyNutritionPlan {
        let generator = Self.makePlanGenerator(from: keychainStore)
        let profileInput = makeProfileInput()
        let ingredients = parseIngredients(ingredientesRefri)

        let weeklyInput = WeeklyPlanGenerationInput(
            profile: profileInput,
            ajustes: ajustes,
            ingredientesRefri: ingredients
        )
        let weeklyPlan = try await generator.generateWeeklyPlan(for: weeklyInput)
        planStore.saveWeekly(weeklyPlan, for: slot)
        return weeklyPlan
    }

    @MainActor
    private func generateWeeklyGroceryList(for weeklyPlan: WeeklyNutritionPlan, ingredientesRefri: String, replaceExisting: Bool) async throws -> Int {
        let generator = Self.makePlanGenerator(from: keychainStore)
        let profileInput = makeProfileInput()
        let ingredients = parseIngredients(ingredientesRefri)
        let normalizedFridge = ingredients.map(normalizeIngredientName(_:))

        let listInput = WeeklyShoppingListInput(
            profile: profileInput,
            weeklyPlan: weeklyPlan,
            ingredientesRefri: ingredients
        )
        let generatedItems = try await generator.generateWeeklyShoppingList(for: listInput)
        let generatedNormalized = generatedItems.map { normalizeIngredientName($0.name) }
        let fridgeOnly = ingredients.filter { fridgeName in
            !generatedNormalized.contains(where: { similarIngredientName($0, fridgeName) })
        }
        let fridgeAsItems = fridgeOnly.map {
            ShoppingListItem(
                name: $0,
                category: "En refri",
                quantity: 1,
                unit: "pieza",
                isPurchased: true
            )
        }
        let generatedWithFridgeState = generatedItems.map { item -> ShoppingListItem in
            let itemName = normalizeIngredientName(item.name)
            let isAlreadyInFridge = normalizedFridge.contains(where: { similarIngredientName(itemName, $0) })
            return ShoppingListItem(
                id: item.id,
                name: item.name,
                category: isAlreadyInFridge ? "En refri" : item.category,
                quantity: item.quantity,
                unit: item.unit,
                isPurchased: isAlreadyInFridge || item.isPurchased
            )
        }
        let finalGenerated = generatedWithFridgeState + fridgeAsItems

        if replaceExisting {
            try await stores.save(shoppingItems: finalGenerated)
            return finalGenerated.count
        }

        let existing = try await stores.fetchShoppingItems()
        var merged = existing
        var added = 0
        for item in finalGenerated {
            let normalized = item.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if let index = merged.firstIndex(where: {
                $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == normalized
            }) {
                // Preserve user progress but mark as en casa when detected in fridge.
                if item.isPurchased {
                    merged[index].isPurchased = true
                    merged[index].category = "En refri"
                }
                continue
            }
            merged.append(item)
            added += 1
        }
        try await stores.save(shoppingItems: merged)
        return added
    }

    private func parseIngredients(_ raw: String) -> [String] {
        raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func analyzeFridgeIngredients(from imagesData: [Data]) async throws -> [String] {
        guard !imagesData.isEmpty else { return [] }
        let client = Self.makeAIClient(from: keychainStore)
        var found: [String] = []

        for imageData in imagesData {
            let prompt = """
            Analiza esta imagen de refrigerador/alacena/congelador.
            Objetivo: inventario de ingredientes disponibles para plan nutricional (NO recetas).
            Responde detectando alimentos en `foodItems` con nombres concretos (ej: pechuga de pollo, huevo, brócoli, yogurt griego).
            Si aplica, usa `shoppingList` solo para productos faltantes obvios.
            """
            let inference = try await client.inferNutrition(fromImageData: imageData, prompt: prompt)
            found.append(contentsOf: inference.foodItems.map(\.name))
        }

        let cleaned = found
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let unique = Array(Set(cleaned.map { normalizeIngredientName($0) }))
            .sorted()

        if unique.isEmpty {
            throw FridgeInventoryError.noIngredientsDetected
        }
        return unique
    }

    private func applyFridgeInventoryToShoppingList(ingredients: [String]) async throws {
        guard !ingredients.isEmpty else { return }
        let existing = try await stores.fetchShoppingItems()
        var merged = existing
        for ingredient in ingredients {
            let normalized = normalizeIngredientName(ingredient)
            if let index = merged.firstIndex(where: {
                normalizeIngredientName($0.name) == normalized
            }) {
                merged[index].isPurchased = true
                merged[index].category = "En refri"
                continue
            }
            merged.append(
                ShoppingListItem(
                    name: ingredient,
                    category: "En refri",
                    quantity: 1,
                    unit: "pieza",
                    isPurchased: true
                )
            )
        }
        try await stores.save(shoppingItems: merged)
    }

    private func normalizeIngredientName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
    }

    private func similarIngredientName(_ lhs: String, _ rhs: String) -> Bool {
        let a = normalizeIngredientName(lhs)
        let b = normalizeIngredientName(rhs)
        if a == b { return true }
        return a.contains(b) || b.contains(a)
    }

    private func saveFoodRecord(for preset: QuickAddPreset) async throws {
        let nutrition = NutritionPerServing(
            calories: preset.calories,
            proteinGrams: preset.proteinGrams,
            carbsGrams: preset.carbsGrams,
            fatGrams: preset.fatGrams
        )

        let item = FoodItem(
            name: preset.name,
            servingDescription: preset.servingDescription,
            nutrition: nutrition,
            source: "quick-add",
            loggedAt: .now
        )

        let existingItems = try await stores.fetchFoodItems()
        try await stores.save(foodItems: existingItems + [item])
    }
}

private enum FridgeInventoryError: LocalizedError {
    case noIngredientsDetected

    var errorDescription: String? {
        switch self {
        case .noIngredientsDetected:
            return "No se detectaron ingredientes en las fotos."
        }
    }
}

private struct QuickAddPreset {
    let name: String
    let servingDescription: String
    let calories: Double
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double

    static func from(_ kind: DashboardView.QuickAddKind) -> Self {
        switch kind {
        case .coffee:
            return .init(
                name: "Café con leche deslactosada y Splenda",
                servingDescription: "250 ml",
                calories: 45,
                proteinGrams: 2.5,
                carbsGrams: 4,
                fatGrams: 1.5
            )
        case .waterGlass:
            return .init(
                name: "Vaso de agua",
                servingDescription: "250 ml",
                calories: 0,
                proteinGrams: 0,
                carbsGrams: 0,
                fatGrams: 0
            )
        case .apple:
            return .init(
                name: "Manzana mediana",
                servingDescription: "1 pieza",
                calories: 95,
                proteinGrams: 0.5,
                carbsGrams: 25,
                fatGrams: 0.3
            )
        }
    }
}

private struct FloatingSettingsButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct EmptyNutritionInference: MultimodalNutritionInference {
    let message: String

    init(message: String = "Configura OPENAI_API_KEY o GEMINI_API_KEY desde el botón de ajustes (engranaje).") {
        self.message = message
    }

    func inferNutrition(fromImageData data: Data, prompt: String) async throws -> NutritionInferenceResult {
        _ = data
        _ = prompt
        return NutritionInferenceResult(
            foodItems: [],
            shoppingList: [],
            notes: message
        )
    }
}

private struct EmptyRecipeInference: MultimodalRecipeInference {
    let message: String

    init(message: String = "Configura OPENAI_API_KEY o GEMINI_API_KEY desde el botón de ajustes (engranaje).") {
        self.message = message
    }

    func inferRecipes(fromImageData images: [Data], prompt: String) async throws -> [RecipeSuggestion] {
        _ = images
        _ = prompt
        throw EmptyInferenceError(message: message)
    }
}

private struct EmptyInferenceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
