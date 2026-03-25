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
        static let fiberActualKey = "widget.macros.fiber.actual"
        static let fiberTargetKey = "widget.macros.fiber.target"
        static let suggestionKey = "widget.smart.suggestion"
        static let watchQuickAddFavoritesKey = "watch.quickAddFavorites"
        static let watchTodayMealsKey = "watch.todayMeals"
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
    @State private var quickAddFavorites: [QuickAddFavoriteRecord] = []
    @State private var hasLoadedQuickAddFavorites = false

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
                    quickAddFavorites: quickAddFavorites.map(\.asDashboardFavorite),
                    onQuickAddFavorite: { favorite in
                        Task { await registerFavoriteQuickAdd(favorite) }
                    },
                    onRemoveQuickAddFavorite: { favorite in
                        removeQuickAddFavorite(id: favorite.id)
                    },
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

                FoodLogView(
                    viewModel: foodLogViewModel,
                    onRepeatTodayTap: { item in
                        try await repeatFoodLogItemToday(item)
                    },
                    onAddToQuickAddTap: { item in
                        await addFoodItemToQuickAddFavorites(item)
                    }
                )
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
                        },
                        onLogMealTap: { mealLabel, meal in
                            try await logPlannedMealToDiary(mealLabel: mealLabel, meal: meal)
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
            loadQuickAddFavoritesIfNeeded()
            syncWatchQuickAddFavorites()
            syncWatchTodayMeals()
            watchConnector.eventHandler = { event in
                Task {
                    await persistWatchEventIfNeeded(event)
                    await dashboardViewModel.refresh()
                    await foodLogViewModel.refresh()
                }
            }
            await ensureHealthDataLoaded()
            await syncHydrationLogsToDiaryIfNeeded(force: true)
            if !profileStore.hasCompletedOnboarding {
                isShowingDietaryProfile = true
            }
        }
        .onReceive(dashboardViewModel.$today) { snapshot in
            guard let snapshot else { return }
            syncWidgetStore(with: snapshot)
            syncWatchState(with: snapshot)
        }
        .onReceive(planStore.$currentPlan) { _ in
            syncWatchTodayMeals()
        }
        .onReceive(planStore.$weeklyPlansBySlot) { _ in
            syncWatchTodayMeals()
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
        case .gemini:
            if let key = normalizedKey(
                storeKey: keychainStore.key(for: .gemini) ?? keychainStore.sharedGeminiKey() ?? keychainStore.bundledGeminiKey(),
                env: "GEMINI_API_KEY"
            ),
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
            if let key = normalizedKey(
                storeKey: keychainStore.key(for: .gemini) ?? keychainStore.sharedGeminiKey() ?? keychainStore.bundledGeminiKey(),
                env: "GEMINI_API_KEY"
            ),
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
            nutrition: NutritionPerServing(calories: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0, fiberGrams: 0),
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

    @MainActor
    private func persistWatchEventIfNeeded(_ event: WatchConnector.Event) async {
        let fingerprint = [
            event.alimento,
            event.servingDescription,
            String(format: "%.2f", event.calorias),
            String(Int(event.timestamp.timeIntervalSince1970))
        ].joined(separator: "|")

        let defaults = UserDefaults.standard
        let processedKey = "watch.last.processed.event"
        guard defaults.string(forKey: processedKey) != fingerprint else { return }

        do {
            let servingDescription = event.servingDescription.isEmpty ? "Apple Watch" : event.servingDescription
            let item = FoodItem(
                name: event.alimento,
                servingDescription: servingDescription,
                nutrition: NutritionPerServing(
                    calories: event.calorias,
                    proteinGrams: event.proteinGrams,
                    carbsGrams: event.carbsGrams,
                    fatGrams: event.fatGrams,
                    fiberGrams: event.fiberGrams
                ),
                source: "watch",
                loggedAt: event.timestamp
            )
            let existingItems = try await stores.fetchFoodItems()
            try await stores.save(foodItems: existingItems + [item])
            defaults.set(fingerprint, forKey: processedKey)
        } catch {
            // Leave event unmarked so next app activation can retry persistence.
        }
    }

    private func smartSuggestionPrompt(for snapshot: DailyCalorieSnapshot, goal: PrimaryGoal) -> String {
        let macroTarget = macroTargets(for: snapshot.date)
        let proteinTarget = Int((macroTarget?.protein ?? 0).rounded())
        let carbsTarget = Int((macroTarget?.carbs ?? 0).rounded())
        let fatTarget = Int((macroTarget?.fat ?? 0).rounded())
        let fiberTarget = Int(recommendedFiberGrams.rounded())
        let proteinActual = Int(snapshot.consumedProteinGrams.rounded())
        let carbsActual = Int(snapshot.consumedCarbsGrams.rounded())
        let fatActual = Int(snapshot.consumedFatGrams.rounded())
        let fiberActual = Int(snapshot.consumedFiberGrams.rounded())

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
        - Fibra: \(fiberActual)g / \(fiberTarget)g

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

    private var recommendedFiberGrams: Double {
        profileStore.profile.recommendedFiberGrams
    }

    private func defaultWidgetSuggestion(for snapshot: DailyCalorieSnapshot) -> String {
        let adjustedBudget = snapshot.targetKcal + snapshot.activeBurnedKcal
        let delta = snapshot.consumedKcal - adjustedBudget
        let proteinTarget = macroTargets(for: snapshot.date)?.protein ?? 0

        if delta > 150 {
            return "Vas arriba de la meta ajustada. Prioriza una cena ligera y alta en proteína."
        }
        if delta < -250 {
            return "Todavía tienes margen. Sube proteína y fibra con una comida simple y saciante."
        }
        if snapshot.consumedProteinGrams < proteinTarget * 0.7 {
            return "Te falta proteína. Agrega yogurt griego, pollo, atún o huevo."
        }
        if snapshot.consumedFiberGrams < recommendedFiberGrams * 0.6 {
            return "Vas bajo en fibra. Suma fruta, avena, verduras o leguminosas."
        }
        return "Vas bien. Mantén porciones estables y prioriza alimentos poco procesados."
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
        defaults.set(snapshot.consumedFiberGrams, forKey: WidgetShared.fiberActualKey)
        defaults.set(recommendedFiberGrams, forKey: WidgetShared.fiberTargetKey)
        defaults.set(defaultWidgetSuggestion(for: snapshot), forKey: WidgetShared.suggestionKey)

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    private func syncWatchQuickAddFavorites() {
        guard let defaults = UserDefaults(suiteName: WidgetShared.appGroupID) else { return }
        let watchFavorites = quickAddFavorites.map {
            WatchQuickAddFavoriteRecord(
                name: $0.name,
                servingDescription: $0.servingDescription,
                calories: $0.calories,
                proteinGrams: $0.proteinGrams,
                carbsGrams: $0.carbsGrams,
                fatGrams: $0.fatGrams,
                fiberGrams: $0.fiberGrams
            )
        }
        guard let data = try? JSONEncoder().encode(watchFavorites) else { return }
        defaults.set(data, forKey: WidgetShared.watchQuickAddFavoritesKey)
        syncWatchState()
    }

    private func syncWatchTodayMeals() {
        guard let defaults = UserDefaults(suiteName: WidgetShared.appGroupID) else { return }
        let meals = makeWatchTodayMeals()
        guard let data = try? JSONEncoder().encode(meals) else { return }
        defaults.set(data, forKey: WidgetShared.watchTodayMealsKey)
        syncWatchState()
    }

    private func syncWatchState(with snapshot: DailyCalorieSnapshot? = nil) {
        let snapshotToSync = snapshot ?? dashboardViewModel.today
        guard let snapshotToSync else { return }

        let favorites = quickAddFavorites.map {
            WatchConnector.QuickAddFavoriteState(
                name: $0.name,
                servingDescription: $0.servingDescription,
                calories: $0.calories,
                proteinGrams: $0.proteinGrams,
                carbsGrams: $0.carbsGrams,
                fatGrams: $0.fatGrams,
                fiberGrams: $0.fiberGrams
            )
        }
        let todayMeals = makeWatchTodayMeals().map {
            WatchConnector.TodayMealState(
                label: $0.label,
                name: $0.name,
                servingDescription: $0.servingDescription,
                calories: $0.calories,
                proteinGrams: $0.proteinGrams,
                carbsGrams: $0.carbsGrams,
                fatGrams: $0.fatGrams,
                fiberGrams: $0.fiberGrams,
                scheduledHour: $0.scheduledHour,
                scheduledMinute: $0.scheduledMinute
            )
        }

        watchConnector.syncDashboardStateToWatch(
            consumed: snapshotToSync.consumedKcal,
            goal: snapshotToSync.targetKcal,
            totalBurned: snapshotToSync.activeBurnedKcal + snapshotToSync.basalBurnedKcal,
            proteinActual: snapshotToSync.consumedProteinGrams,
            proteinTarget: macroTargets(for: snapshotToSync.date)?.protein ?? 0,
            carbsActual: snapshotToSync.consumedCarbsGrams,
            carbsTarget: macroTargets(for: snapshotToSync.date)?.carbs ?? 0,
            fatActual: snapshotToSync.consumedFatGrams,
            fatTarget: macroTargets(for: snapshotToSync.date)?.fat ?? 0,
            fiberActual: snapshotToSync.consumedFiberGrams,
            fiberTarget: recommendedFiberGrams,
            quickAddFavorites: favorites,
            todayMeals: todayMeals
        )
    }

    private func makeWatchTodayMeals() -> [WatchTodayMealRecord] {
        let selectedMeals: [(label: String, meal: NutritionMeal, hour: Int, minute: Int)]
        if let weekly = planStore.weeklyPlan(for: .current),
           let currentDay = currentDayFromWeeklyPlan(weekly) {
            selectedMeals = scheduledWatchMeals(
                from: [
                    ("Desayuno", currentDay.desayuno, mealScheduleStore.breakfastHour, mealScheduleStore.breakfastMinute),
                    ("Colación 1", currentDay.colacion1, mealScheduleStore.snack1Hour, mealScheduleStore.snack1Minute),
                    ("Comida", currentDay.comida, mealScheduleStore.lunchHour, mealScheduleStore.lunchMinute),
                    ("Colación 2", currentDay.colacion2, mealScheduleStore.snack2Hour, mealScheduleStore.snack2Minute),
                    ("Cena", currentDay.cena, mealScheduleStore.dinnerHour, mealScheduleStore.dinnerMinute)
                ]
            )
        } else if let daily = planStore.currentPlan {
            selectedMeals = scheduledWatchMeals(
                from: [
                    ("Desayuno", daily.desayuno, mealScheduleStore.breakfastHour, mealScheduleStore.breakfastMinute),
                    ("Colación 1", daily.colacion1, mealScheduleStore.snack1Hour, mealScheduleStore.snack1Minute),
                    ("Comida", daily.comida, mealScheduleStore.lunchHour, mealScheduleStore.lunchMinute),
                    ("Colación 2", daily.colacion2, mealScheduleStore.snack2Hour, mealScheduleStore.snack2Minute),
                    ("Cena", daily.cena, mealScheduleStore.dinnerHour, mealScheduleStore.dinnerMinute)
                ]
            )
        } else {
            selectedMeals = []
        }

        return selectedMeals.map {
            WatchTodayMealRecord(
                label: $0.label,
                name: $0.meal.titulo,
                servingDescription: $0.meal.descripcion,
                calories: Double($0.meal.calorias),
                proteinGrams: estimatedMealNutrition(for: $0.meal, mealLabel: $0.label).proteinGrams,
                carbsGrams: estimatedMealNutrition(for: $0.meal, mealLabel: $0.label).carbsGrams,
                fatGrams: estimatedMealNutrition(for: $0.meal, mealLabel: $0.label).fatGrams,
                fiberGrams: estimatedMealNutrition(for: $0.meal, mealLabel: $0.label).fiberGrams,
                scheduledHour: $0.hour,
                scheduledMinute: $0.minute
            )
        }
    }

    private func scheduledWatchMeals(
        from meals: [(label: String, meal: NutritionMeal, hour: Int, minute: Int)]
    ) -> [(label: String, meal: NutritionMeal, hour: Int, minute: Int)] {
        meals
            .filter { !$0.meal.titulo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { $0 }
    }

    private func currentDayFromWeeklyPlan(_ plan: WeeklyNutritionPlan) -> WeeklyPlanDay? {
        guard !plan.dias.isEmpty else { return nil }
        let mondayFirstIndex = (Calendar.current.component(.weekday, from: Date()) + 5) % 7
        let expectedDay = ["lunes", "martes", "miercoles", "jueves", "viernes", "sabado", "domingo"][mondayFirstIndex]

        if let byName = plan.dias.first(where: { normalizeDayName($0.dia) == expectedDay }) {
            return byName
        }
        if mondayFirstIndex < plan.dias.count {
            return plan.dias[mondayFirstIndex]
        }
        return plan.dias.first
    }

    private func normalizeDayName(_ value: String) -> String {
        value
            .lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func estimatedMealNutrition(for meal: NutritionMeal, mealLabel: String) -> NutritionPerServing {
        if let weekly = planStore.weeklyPlan(for: .current) {
            return estimateNutrition(
                calories: Double(meal.calorias),
                totalCalories: Double(max(weekly.caloriasObjetivoDiarias, 1)),
                proteinTarget: Double(weekly.proteinaObjetivoGramos),
                carbsTarget: Double(weekly.carbohidratosObjetivoGramos),
                fatTarget: Double(weekly.grasasObjetivoGramos),
                fiberTarget: recommendedFiberGrams
            )
        }
        if let daily = planStore.currentPlan {
            return estimateNutrition(
                calories: Double(meal.calorias),
                totalCalories: Double(max(daily.caloriasDiarias, 1)),
                proteinTarget: Double(daily.proteinaGramos),
                carbsTarget: Double(daily.carbohidratosGramos),
                fatTarget: Double(daily.grasasGramos),
                fiberTarget: recommendedFiberGrams
            )
        }
        return NutritionPerServing(
            calories: Double(meal.calorias),
            proteinGrams: 0,
            carbsGrams: 0,
            fatGrams: 0,
            fiberGrams: 0
        )
    }

    private func estimateNutrition(
        calories: Double,
        totalCalories: Double,
        proteinTarget: Double,
        carbsTarget: Double,
        fatTarget: Double,
        fiberTarget: Double
    ) -> NutritionPerServing {
        let ratio = min(max(calories / max(totalCalories, 1), 0), 1)
        return NutritionPerServing(
            calories: calories,
            proteinGrams: proteinTarget * ratio,
            carbsGrams: carbsTarget * ratio,
            fatGrams: fatTarget * ratio,
            fiberGrams: fiberTarget * ratio
        )
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
        let geminiKey = store.key(for: .gemini)
            ?? store.sharedGeminiKey()
            ?? store.bundledGeminiKey()
            ?? ProcessInfo.processInfo.environment["GEMINI_API_KEY"]

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
                    message: "Proveedor principal Gemini seleccionado, pero no hay GEMINI_API_KEY (ni compartida) configurada."
                )
            }
            return geminiClient
        }
    }

    private static func makeRecipeAIClient(from store: AIKeychainStore) -> MultimodalRecipeInference {
        let openAIKey = store.key(for: .openAI) ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        let geminiKey = store.key(for: .gemini)
            ?? store.sharedGeminiKey()
            ?? store.bundledGeminiKey()
            ?? ProcessInfo.processInfo.environment["GEMINI_API_KEY"]

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
                message: "Proveedor principal Gemini seleccionado, pero no hay GEMINI_API_KEY (ni compartida) configurada."
            )
        }
    }

    private static func makePlanGenerator(from store: AIKeychainStore) -> any NutritionPlanGenerating {
        NutritionPlanRemoteGenerator(
            primaryProvider: store.primaryProvider,
            openAIKey: store.key(for: .openAI) ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
            geminiKey: store.key(for: .gemini)
                ?? store.sharedGeminiKey()
                ?? store.bundledGeminiKey()
                ?? ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
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

    private func loadQuickAddFavoritesIfNeeded() {
        guard !hasLoadedQuickAddFavorites else { return }
        hasLoadedQuickAddFavorites = true
        quickAddFavorites = QuickAddFavoriteStore.load()
        syncWatchQuickAddFavorites()
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
            fatGrams: 0,
            fiberGrams: 0
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

    @MainActor
    private func registerFavoriteQuickAdd(_ favorite: DashboardView.QuickAddFavorite) async {
        let preset = QuickAddPreset(
            name: favorite.name,
            servingDescription: favorite.servingDescription,
            calories: max(0, favorite.calories),
            proteinGrams: max(0, favorite.proteinGrams),
            carbsGrams: max(0, favorite.carbsGrams),
            fatGrams: max(0, favorite.fatGrams),
            fiberGrams: max(0, favorite.fiberGrams)
        )

        do {
            try await saveFoodRecord(for: preset)
            if preset.calories > 0 {
                try await healthStore.saveDietaryEnergy(kilocalories: preset.calories, at: .now)
            }
            await dashboardViewModel.refresh()
            await foodLogViewModel.refresh()
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
    private func repeatFoodLogItemToday(_ item: FoodItem) async throws {
        let repeated = FoodItem(
            name: item.name,
            servingDescription: item.servingDescription,
            nutrition: item.nutrition,
            source: "repeat",
            loggedAt: .now
        )
        let existingItems = try await stores.fetchFoodItems()
        try await stores.save(foodItems: existingItems + [repeated])
        if repeated.nutrition.calories > 0 {
            try await healthStore.saveDietaryEnergy(kilocalories: repeated.nutrition.calories, at: .now)
        }
        await dashboardViewModel.refresh()
        await foodLogViewModel.refresh()
    }

    @MainActor
    private func addFoodItemToQuickAddFavorites(_ item: FoodItem) async -> FoodLogQuickAddResult {
        if quickAddFavorites.count >= QuickAddFavoriteStore.maxFavorites {
            return .maxReached
        }
        let normalizedName = normalizeFavoriteName(item.name)
        if quickAddFavorites.contains(where: { normalizeFavoriteName($0.name) == normalizedName }) {
            return .alreadyExists
        }

        let favorite = QuickAddFavoriteRecord(
            id: UUID().uuidString,
            name: item.name,
            servingDescription: item.servingDescription,
            calories: item.nutrition.calories,
            proteinGrams: item.nutrition.proteinGrams,
            carbsGrams: item.nutrition.carbsGrams,
            fatGrams: item.nutrition.fatGrams,
            fiberGrams: item.nutrition.fiberGrams
        )
        var next = quickAddFavorites
        next.append(favorite)
        quickAddFavorites = next
        QuickAddFavoriteStore.save(next)
        syncWatchQuickAddFavorites()
        return .added
    }

    private func removeQuickAddFavorite(id: String) {
        quickAddFavorites.removeAll { $0.id == id }
        QuickAddFavoriteStore.save(quickAddFavorites)
        syncWatchQuickAddFavorites()
    }

    private func normalizeFavoriteName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
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

    private func saveFoodRecord(
        for preset: QuickAddPreset,
        source: String = "quick-add",
        loggedAt: Date = .now
    ) async throws {
        let nutrition = NutritionPerServing(
            calories: preset.calories,
            proteinGrams: preset.proteinGrams,
            carbsGrams: preset.carbsGrams,
            fatGrams: preset.fatGrams,
            fiberGrams: preset.fiberGrams
        )

        let item = FoodItem(
            name: preset.name,
            servingDescription: preset.servingDescription,
            nutrition: nutrition,
            source: source,
            loggedAt: loggedAt
        )

        let existingItems = try await stores.fetchFoodItems()
        try await stores.save(foodItems: existingItems + [item])
    }

    @MainActor
    private func logPlannedMealToDiary(mealLabel: String, meal: NutritionMeal) async throws {
        let trimmedDescription = meal.descripcion.trimmingCharacters(in: .whitespacesAndNewlines)
        let serving = trimmedDescription.isEmpty ? "Comida planeada: \(mealLabel)" : trimmedDescription
        let normalizedLabel = mealLabel
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        let estimatedNutrition = estimatedMealNutrition(for: meal, mealLabel: mealLabel)
        let item = FoodItem(
            name: meal.titulo,
            servingDescription: serving,
            nutrition: estimatedNutrition,
            source: "plan-\(normalizedLabel)",
            loggedAt: .now
        )

        let existingItems = try await stores.fetchFoodItems()
        try await stores.save(foodItems: existingItems + [item])
        await dashboardViewModel.refresh()
        await foodLogViewModel.refresh()
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
    let fiberGrams: Double

    static func from(_ kind: DashboardView.QuickAddKind) -> Self {
        switch kind {
        case .coffee:
            return .init(
                name: "Café con leche deslactosada y Splenda",
                servingDescription: "250 ml",
                calories: 45,
                proteinGrams: 2.5,
                carbsGrams: 4,
                fatGrams: 1.5,
                fiberGrams: 0
            )
        case .waterGlass:
            return .init(
                name: "Vaso de agua",
                servingDescription: "250 ml",
                calories: 0,
                proteinGrams: 0,
                carbsGrams: 0,
                fatGrams: 0,
                fiberGrams: 0
            )
        case .apple:
            return .init(
                name: "Manzana mediana",
                servingDescription: "1 pieza",
                calories: 95,
                proteinGrams: 0.5,
                carbsGrams: 25,
                fatGrams: 0.3,
                fiberGrams: 4.4
            )
        }
    }
}

private struct QuickAddFavoriteRecord: Codable, Identifiable {
    let id: String
    let name: String
    let servingDescription: String
    let calories: Double
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double
    let fiberGrams: Double

    private enum CodingKeys: String, CodingKey {
        case id, name, servingDescription, calories, proteinGrams, carbsGrams, fatGrams, fiberGrams
    }

    init(id: String, name: String, servingDescription: String, calories: Double, proteinGrams: Double, carbsGrams: Double, fatGrams: Double, fiberGrams: Double) {
        self.id = id
        self.name = name
        self.servingDescription = servingDescription
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        servingDescription = try container.decode(String.self, forKey: .servingDescription)
        calories = try container.decode(Double.self, forKey: .calories)
        proteinGrams = try container.decodeIfPresent(Double.self, forKey: .proteinGrams) ?? 0
        carbsGrams = try container.decodeIfPresent(Double.self, forKey: .carbsGrams) ?? 0
        fatGrams = try container.decodeIfPresent(Double.self, forKey: .fatGrams) ?? 0
        fiberGrams = try container.decodeIfPresent(Double.self, forKey: .fiberGrams) ?? 0
    }

    var asDashboardFavorite: DashboardView.QuickAddFavorite {
        DashboardView.QuickAddFavorite(
            id: id,
            name: name,
            servingDescription: servingDescription,
            calories: calories,
            proteinGrams: proteinGrams,
            carbsGrams: carbsGrams,
            fatGrams: fatGrams,
            fiberGrams: fiberGrams
        )
    }
}

private struct WatchQuickAddFavoriteRecord: Codable {
    let name: String
    let servingDescription: String
    let calories: Double
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double
    let fiberGrams: Double
}

private struct WatchTodayMealRecord: Codable {
    let label: String
    let name: String
    let servingDescription: String
    let calories: Double
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double
    let fiberGrams: Double
    let scheduledHour: Int
    let scheduledMinute: Int
}

private enum QuickAddFavoriteStore {
    static let key = "quick.add.favorites.v1"
    static let maxFavorites = 8

    static func load(defaults: UserDefaults = .standard) -> [QuickAddFavoriteRecord] {
        guard let data = defaults.data(forKey: key) else { return [] }
        guard let decoded = try? JSONDecoder().decode([QuickAddFavoriteRecord].self, from: data) else {
            return []
        }
        return Array(decoded.prefix(maxFavorites))
    }

    static func save(_ favorites: [QuickAddFavoriteRecord], defaults: UserDefaults = .standard) {
        let clipped = Array(favorites.prefix(maxFavorites))
        guard let data = try? JSONEncoder().encode(clipped) else { return }
        defaults.set(data, forKey: key)
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
