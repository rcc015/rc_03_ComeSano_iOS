import SwiftUI
import ComeSanoCore
import ComeSanoUI
import ComeSanoAI
import ComeSanoPersistence
import ComeSanoHealthKit
#if os(iOS)
import UIKit
#if canImport(WidgetKit)
import WidgetKit
#endif
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
    private enum WidgetShared {
        static let appGroupID = "group.rcTools.ComeSano"
        static let consumedKey = "widget.calories.consumed"
        static let goalKey = "widget.calories.goal"
        static let activeKey = "widget.calories.active"
        static let basalKey = "widget.calories.basal"
        static let adjustedBudgetKey = "widget.calories.adjustedBudget"
        static let adjustedDeltaKey = "widget.calories.adjustedDelta"
        static let proteinActualKey = "widget.macros.protein.actual"
        static let proteinTargetKey = "widget.macros.protein.target"
        static let carbsActualKey = "widget.macros.carbs.actual"
        static let carbsTargetKey = "widget.macros.carbs.target"
        static let fatActualKey = "widget.macros.fat.actual"
        static let fatTargetKey = "widget.macros.fat.target"
    }

    private enum AppTab: Hashable {
        case progress
        case foodLog
        case plan
        case camera
        case recipes
        case grocery
    }

    private enum AppMode: String {
        case calorieCounter
        case smartNutrition

        var title: String {
            switch self {
            case .calorieCounter:
                return "Contador de Calorías"
            case .smartNutrition:
                return "Nutriólogo Smart"
            }
        }

        var icon: String {
            switch self {
            case .calorieCounter:
                return "flame.fill"
            case .smartNutrition:
                return "brain.head.profile"
            }
        }
    }

    private let dashboardViewModel: DashboardViewModel
    private let stores: CoreDataStores
    private let healthStore: HealthKitNutritionStore
    @StateObject private var photoAnalyzerViewModel: FoodPhotoAnalyzerViewModel
    @StateObject private var recipeSuggestionViewModel: RecipeSuggestionViewModel
    @StateObject private var groceryListViewModel: GroceryListViewModel
    @StateObject private var foodLogViewModel: FoodLogViewModel
    @StateObject private var profileStore: UserProfileStore
    @StateObject private var planStore: NutritionPlanStore
    @StateObject private var mealScheduleStore: MealScheduleStore
    @StateObject private var keychainStore: AIKeychainStore
    @StateObject private var reminderManager: ReminderNotificationManager
    @StateObject private var watchConnector: WatchConnector
    @State private var hasRequestedHealthAuthorization = false
    @State private var selectedTab: AppTab = .progress
    @State private var appMode: AppMode = .calorieCounter
    @State private var isShowingAISettings = false
    @State private var isShowingDietaryProfile = false
    @State private var isShowingFridgeScannerForGrocery = false
    @State private var healthBodyMetrics: HealthBodyMetrics?
    @State private var hasSyncedHydrationLogs = false

    init() {
        #if os(iOS)
        Self.configureTabBarAppearance()
        #endif

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
        _foodLogViewModel = StateObject(wrappedValue: FoodLogViewModel(foodStore: stores))
        _profileStore = StateObject(wrappedValue: profileStore)
        _planStore = StateObject(wrappedValue: NutritionPlanStore())
        _mealScheduleStore = StateObject(wrappedValue: MealScheduleStore())
        _keychainStore = StateObject(wrappedValue: keyStore)
        _reminderManager = StateObject(wrappedValue: ReminderNotificationManager())
        _watchConnector = StateObject(wrappedValue: WatchConnector.shared)
        _isShowingDietaryProfile = State(initialValue: false)
    }

    var body: some View {
        VStack(spacing: 10) {
            modeSwitcher

            TabView(selection: $selectedTab) {
                DashboardView(
                    viewModel: dashboardViewModel,
                    onQuickAdd: handleQuickAdd,
                    onQuickAddCustomMeal: handleQuickAddCustomMeal,
                    aiSuggestionProvider: { snapshot, goal in
                        await requestAISmartSuggestion(for: snapshot, goal: goal)
                    },
                    macroTargetsProvider: { date in
                        macroTargets(for: date)
                    }
                )
                    .tag(AppTab.progress)
                    .tabItem {
                        Label("Progreso", systemImage: "chart.line.uptrend.xyaxis")
                    }

                FoodLogView(viewModel: foodLogViewModel)
                    .tag(AppTab.foodLog)
                    .tabItem {
                        Label("Diario", systemImage: "list.bullet.rectangle")
                    }

                if appMode == .smartNutrition {
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
                }

                CameraAnalysisView(viewModel: photoAnalyzerViewModel)
                    .tag(AppTab.camera)
                    .tabItem {
                        Label("Foto", systemImage: "camera")
                    }

                if appMode == .smartNutrition {
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
            }
        }
        .tint(.accentColor)
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
            AISettingsView(
                keychainStore: keychainStore,
                reminderManager: reminderManager,
                mealScheduleStore: mealScheduleStore
            ) {
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
                planGenerator: Self.makePlanGenerator(from: keychainStore),
                mealScheduleStore: mealScheduleStore
            ) { updatedProfile, plan in
                profileStore.save(profile: updatedProfile, markOnboardingDone: true)
                planStore.save(plan)
                dashboardViewModel.updateProfile(updatedProfile)
                Task { await dashboardViewModel.refresh() }
                isShowingDietaryProfile = false
            }
        }
        .task {
            loadAppMode()
            await ensureHealthDataLoaded()
            await syncHydrationLogsToDiaryIfNeeded(force: true)
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
        .onReceive(dashboardViewModel.$today) { snapshot in
            guard let snapshot else { return }
            syncWidgetStore(with: snapshot)
        }
        .onOpenURL { url in
            handleDeepLink(url)
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
        .onChange(of: appMode) { _, newMode in
            saveAppMode(newMode)
            if newMode == .calorieCounter {
                let allowedTabs: Set<AppTab> = [.progress, .foodLog, .camera]
                if !allowedTabs.contains(selectedTab) {
                    selectedTab = .progress
                }
            }
        }
        .onChange(of: reminderManager.loggedWaterGlasses) { _, _ in
            Task {
                await syncHydrationLogsToDiaryIfNeeded(force: false)
            }
        }
    }

    private var settingsButton: some View {
        Button {
            #if os(iOS)
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            #endif
            isShowingAISettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(8)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ajustes de IA")
    }

    private var modeSwitcher: some View {
        HStack(spacing: 8) {
            Image(systemName: appMode.icon)
            Text(appMode.title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            settingsButton
            Button {
                appMode = appMode == .calorieCounter ? .smartNutrition : .calorieCounter
            } label: {
                Text("Cambiar")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private func loadAppMode() {
        let raw = UserDefaults.standard.string(forKey: "app.mode")
        appMode = AppMode(rawValue: raw ?? AppMode.calorieCounter.rawValue) ?? .calorieCounter
        if appMode == .calorieCounter {
            let allowedTabs: Set<AppTab> = [.progress, .foodLog, .camera]
            if !allowedTabs.contains(selectedTab) {
                selectedTab = .progress
            }
        }
    }

    private func saveAppMode(_ mode: AppMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: "app.mode")
    }

    private func handleDeepLink(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "comesano" else { return }
        guard let host = url.host?.lowercased() else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        switch host {
        case "quickadd":
            let type = components?.queryItems?.first(where: { $0.name == "type" })?.value?.lowercased()
            let caloriesRaw = components?.queryItems?.first(where: { $0.name == "calories" })?.value
            let calories = Double(caloriesRaw ?? "") ?? 400

            switch type {
            case "coffee":
                handleQuickAdd(.coffee)
            case "water":
                handleQuickAdd(.waterGlass)
            case "apple":
                handleQuickAdd(.apple)
            case "meal":
                handleQuickAddCustomMeal(calories)
            default:
                break
            }
        case "open":
            let tab = components?.queryItems?.first(where: { $0.name == "tab" })?.value?.lowercased()
            if tab == "camera" {
                selectedTab = .camera
            }
        default:
            break
        }
    }

    #if os(iOS)
    private static func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        appearance.backgroundColor = UIColor.black.withAlphaComponent(0.38)

        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.tintColor = UIColor(Color.accentColor)
    }
    #endif

    private func requestAISmartSuggestion(for snapshot: DailyCalorieSnapshot, goal: PrimaryGoal) async -> String? {
        let prompt = smartSuggestionPrompt(for: snapshot, goal: goal)
        let primary = keychainStore.primaryProvider

        switch primary {
        case .backend:
            if let token = keychainStore.backendSessionToken(),
               let backendURL = keychainStore.backendURL(),
               let text = try? await requestBackendSuggestion(prompt: prompt, baseURL: backendURL, sessionToken: token) {
                return text
            }
            if let key = normalizedKey(storeKey: keychainStore.key(for: .gemini), env: "GEMINI_API_KEY"),
               let text = try? await requestGeminiSuggestion(prompt: prompt, apiKey: key) {
                return text
            }
            if let key = normalizedKey(storeKey: keychainStore.key(for: .openAI), env: "OPENAI_API_KEY"),
               let text = try? await requestOpenAISuggestion(prompt: prompt, apiKey: key) {
                return text
            }
        case .gemini:
            if let key = normalizedKey(storeKey: keychainStore.key(for: .gemini), env: "GEMINI_API_KEY"),
               let text = try? await requestGeminiSuggestion(prompt: prompt, apiKey: key) {
                return text
            }
            if let key = normalizedKey(storeKey: keychainStore.key(for: .openAI), env: "OPENAI_API_KEY"),
               let text = try? await requestOpenAISuggestion(prompt: prompt, apiKey: key) {
                return text
            }
        case .openAI:
            if let key = normalizedKey(storeKey: keychainStore.key(for: .openAI), env: "OPENAI_API_KEY"),
               let text = try? await requestOpenAISuggestion(prompt: prompt, apiKey: key) {
                return text
            }
            if let key = normalizedKey(storeKey: keychainStore.key(for: .gemini), env: "GEMINI_API_KEY"),
               let text = try? await requestGeminiSuggestion(prompt: prompt, apiKey: key) {
                return text
            }
        }

        return nil
    }

    @MainActor
    private func syncHydrationLogsToDiaryIfNeeded(force: Bool) async {
        // Avoid duplicate runs on first render; force=true on initial task still executes once.
        if hasSyncedHydrationLogs && !force { return }
        hasSyncedHydrationLogs = true

        let defaults = UserDefaults.standard
        let processedKey = "notifications.water.loggedCount.processedToDiary"
        let totalLogged = reminderManager.loggedWaterGlasses
        let alreadyProcessed = defaults.integer(forKey: processedKey)
        guard totalLogged > alreadyProcessed else { return }

        let missing = totalLogged - alreadyProcessed
        let waterItemTemplate = FoodItem(
            name: "Vaso de agua",
            servingDescription: "250 ml",
            nutrition: NutritionPerServing(calories: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0),
            source: "notification-water",
            loggedAt: .now
        )

        do {
            let existingItems = try await stores.fetchFoodItems()
            var nextItems = existingItems
            for _ in 0..<missing {
                nextItems.append(
                    FoodItem(
                        name: waterItemTemplate.name,
                        servingDescription: waterItemTemplate.servingDescription,
                        nutrition: waterItemTemplate.nutrition,
                        source: waterItemTemplate.source,
                        loggedAt: .now
                    )
                )
            }
            try await stores.save(foodItems: nextItems)
            defaults.set(totalLogged, forKey: processedKey)
        } catch {
            // Keep processed marker unchanged; next sync retries pending hydration logs.
        }
    }

    private func normalizedKey(storeKey: String?, env: String) -> String? {
        let value = storeKey ?? ProcessInfo.processInfo.environment[env]
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func smartSuggestionPrompt(for snapshot: DailyCalorieSnapshot, goal: PrimaryGoal) -> String {
        let macroTarget = macroTargets(for: snapshot.date)
        let proteinTarget = Int((macroTarget?.protein ?? 0).rounded())
        let carbsTarget = Int((macroTarget?.carbs ?? 0).rounded())
        let fatTarget = Int((macroTarget?.fat ?? 0).rounded())
        let proteinActual = Int(snapshot.consumedProteinGrams.rounded())
        let carbsActual = Int(snapshot.consumedCarbsGrams.rounded())
        let fatActual = Int(snapshot.consumedFatGrams.rounded())

        return """
        Eres un nutriólogo deportivo. Genera una sugerencia breve (máximo 2 frases) en español, clara y accionable.
        Contexto del día:
        - Objetivo: \(goalText(goal))
        - Consumidas: \(Int(snapshot.consumedKcal.rounded())) kcal
        - Meta base diaria: \(Int(snapshot.targetKcal.rounded())) kcal
        - Quemadas activas (ejercicio): \(Int(snapshot.activeBurnedKcal.rounded())) kcal
        - Quemadas basales (informativo): \(Int(snapshot.basalBurnedKcal.rounded())) kcal
        - Meta ajustada (meta base + activas): \(Int((snapshot.targetKcal + snapshot.activeBurnedKcal).rounded())) kcal
        - Desviación ajustada (consumidas - meta ajustada): \(Int((snapshot.consumedKcal - (snapshot.targetKcal + snapshot.activeBurnedKcal)).rounded())) kcal
        - Proteína: \(proteinActual)g / \(proteinTarget)g
        - Carbohidratos: \(carbsActual)g / \(carbsTarget)g
        - Grasas: \(fatActual)g / \(fatTarget)g

        Prioriza recomendaciones sobre balance calórico y macros (si hay desvíos relevantes, menciónalos).
        Responde solo texto plano, sin markdown ni bullets.
        """
    }

    private func goalText(_ goal: PrimaryGoal) -> String {
        switch goal {
        case .loseFat: return "Perder grasa"
        case .maintain: return "Mantener peso"
        case .gainMuscle: return "Ganar masa muscular"
        }
    }

    private func macroTargets(for date: Date) -> (protein: Double, carbs: Double, fat: Double)? {
        _ = date
        if let weekly = planStore.weeklyPlan(for: .current) {
            return (
                protein: Double(weekly.proteinaObjetivoGramos),
                carbs: Double(weekly.carbohidratosObjetivoGramos),
                fat: Double(weekly.grasasObjetivoGramos)
            )
        }
        if let daily = planStore.currentPlan {
            return (
                protein: Double(daily.proteinaGramos),
                carbs: Double(daily.carbohidratosGramos),
                fat: Double(daily.grasasGramos)
            )
        }
        return nil
    }

    private func syncWidgetStore(with snapshot: DailyCalorieSnapshot) {
        guard let defaults = UserDefaults(suiteName: WidgetShared.appGroupID) else { return }

        let target = macroTargets(for: snapshot.date)
        let adjustedBudget = snapshot.targetKcal + snapshot.activeBurnedKcal
        let adjustedDelta = snapshot.consumedKcal - adjustedBudget

        defaults.set(snapshot.consumedKcal, forKey: WidgetShared.consumedKey)
        defaults.set(snapshot.targetKcal, forKey: WidgetShared.goalKey)
        defaults.set(snapshot.activeBurnedKcal, forKey: WidgetShared.activeKey)
        defaults.set(snapshot.basalBurnedKcal, forKey: WidgetShared.basalKey)
        defaults.set(adjustedBudget, forKey: WidgetShared.adjustedBudgetKey)
        defaults.set(adjustedDelta, forKey: WidgetShared.adjustedDeltaKey)
        defaults.set(snapshot.consumedProteinGrams, forKey: WidgetShared.proteinActualKey)
        defaults.set(target?.protein ?? 0, forKey: WidgetShared.proteinTargetKey)
        defaults.set(snapshot.consumedCarbsGrams, forKey: WidgetShared.carbsActualKey)
        defaults.set(target?.carbs ?? 0, forKey: WidgetShared.carbsTargetKey)
        defaults.set(snapshot.consumedFatGrams, forKey: WidgetShared.fatActualKey)
        defaults.set(target?.fat ?? 0, forKey: WidgetShared.fatTargetKey)

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    private func requestGeminiSuggestion(prompt: String, apiKey: String) async throws -> String? {
        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ]
        ]

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = json["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let text = parts.first?["text"] as? String
        else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func requestOpenAISuggestion(prompt: String, apiKey: String) async throws -> String? {
        let body: [String: Any] = [
            "model": "gpt-4.1-mini",
            "input": [
                [
                    "role": "user",
                    "content": [
                        ["type": "input_text", "text": prompt]
                    ]
                ]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let outputText = json["output_text"] as? String {
            let trimmed = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if
            let output = json["output"] as? [[String: Any]],
            let firstItem = output.first,
            let content = firstItem["content"] as? [[String: Any]],
            let firstContent = content.first,
            let text = firstContent["text"] as? String
        {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private func requestBackendSuggestion(prompt: String, baseURL: URL, sessionToken: String) async throws -> String? {
        let body: [String: Any] = [
            "prompt": prompt
        ]

        let endpoint = URL(string: "/v1/ai/suggestions", relativeTo: baseURL)!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let value = json["text"] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            if let value = json["content"] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }

        let fallback = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? nil : fallback
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
        let backendToken = store.backendSessionToken()
        let backendURL = store.backendURL()

        let openAIClient = openAIKey.flatMap { key -> MultimodalNutritionInference? in
            guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return NutritionAIClientFactory.makeOpenAI(apiKey: key, model: .gpt4point1mini)
        }

        let geminiClient = geminiKey.flatMap { key -> MultimodalNutritionInference? in
            guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return NutritionAIClientFactory.makeGemini(apiKey: key, model: .gemini25Flash)
        }

        let backendClient: MultimodalNutritionInference? = {
            guard let backendURL, let backendToken else { return nil }
            guard !backendToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return NutritionAIClientFactory.makeBackend(baseURL: backendURL, sessionToken: backendToken)
        }()

        switch store.primaryProvider {
        case .backend:
            guard let backendClient else {
                return EmptyNutritionInference(
                    message: "Proveedor Cuenta seleccionado, pero no hay sesión backend activa."
                )
            }
            return backendClient
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
        let backendToken = store.backendSessionToken()
        let backendURL = store.backendURL()

        let openAIClient = openAIKey.flatMap { key -> MultimodalRecipeInference? in
            guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return NutritionAIClientFactory.makeOpenAIRecipe(apiKey: key, model: .gpt4point1mini)
        }

        let geminiClient = geminiKey.flatMap { key -> MultimodalRecipeInference? in
            guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return NutritionAIClientFactory.makeGeminiRecipe(apiKey: key, model: .gemini25Flash)
        }

        let backendClient: MultimodalRecipeInference? = {
            guard let backendURL, let backendToken else { return nil }
            guard !backendToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return NutritionAIClientFactory.makeBackendRecipe(baseURL: backendURL, sessionToken: backendToken)
        }()

        switch store.primaryProvider {
        case .backend:
            return backendClient ?? EmptyRecipeInference(
                message: "Proveedor Cuenta seleccionado, pero no hay sesión backend activa."
            )
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
            geminiKey: store.key(for: .gemini) ?? ProcessInfo.processInfo.environment["GEMINI_API_KEY"],
            backendBaseURL: store.backendURL(),
            backendSessionToken: store.backendSessionToken()
        )
    }

    private func handleQuickAdd(_ kind: DashboardView.QuickAddKind) {
        Task {
            await registerQuickAdd(kind)
        }
    }

    private func handleQuickAddCustomMeal(_ calories: Double) {
        Task {
            await registerCustomQuickMeal(calories: calories)
        }
    }

    @MainActor
    private func registerQuickAdd(_ kind: DashboardView.QuickAddKind) async {
        let preset = QuickAddPreset.from(kind)

        do {
            // Always persist quick-add events in local diary, including 0 kcal items like water.
            try await saveFoodRecord(for: preset)

            if preset.calories > 0 {
                try await healthStore.saveDietaryEnergy(kilocalories: preset.calories, at: .now)
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

    @MainActor
    private func registerCustomQuickMeal(calories: Double) async {
        let safeCalories = max(0, calories)
        let preset = QuickAddPreset(
            name: "Comida estándar",
            servingDescription: "Registro rápido",
            calories: safeCalories,
            proteinGrams: 0,
            carbsGrams: 0,
            fatGrams: 0
        )

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
            alergias: "",
            horarios: NutritionMealSchedule(
                desayuno: mealScheduleStore.breakfastTime,
                colacion1: mealScheduleStore.snack1Time,
                comida: mealScheduleStore.lunchTime,
                colacion2: mealScheduleStore.snack2Time,
                cena: mealScheduleStore.dinnerTime
            )
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
