import SwiftUI

struct PlanDailyView: View {
    @ObservedObject var planStore: NutritionPlanStore
    let onCreatePlanTap: () -> Void
    let onGenerateWeeklyPlanTap: (_ slot: WeeklyPlanSlot, _ ajustes: String, _ ingredientesRefri: String) async throws -> WeeklyNutritionPlan
    let onGenerateWeeklyGroceryTap: (_ plan: WeeklyNutritionPlan, _ ingredientesRefri: String, _ replaceExisting: Bool) async throws -> Int
    let onAnalyzeFridgeTap: (_ imagesData: [Data]) async throws -> [String]

    @State private var selectedWeekSlot: WeeklyPlanSlot = .current
    @State private var ajustesSemanales = ""
    @State private var ingredientesRefri = ""
    @State private var selectedWeeklyDayIndex = 0
    @State private var replaceGroceryList = false
    @State private var autoUpdateGroceryAfterPlan = true
    @State private var isGeneratingWeekly = false
    @State private var isGeneratingGrocery = false
    @State private var actionError: String?
    @State private var actionMessage: String?
    @State private var isShowingFridgeScanner = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let plan = planStore.currentPlan {
                    VStack(spacing: 20) {
                        dailyGoalCard(plan)

                        if let weeklyPlan = planStore.weeklyPlan(for: selectedWeekSlot),
                           let currentDay = currentDayFromWeeklyPlan(weeklyPlan) {
                            currentDayCard(currentDay, slot: selectedWeekSlot)
                        } else {
                            // Fallback while user still has only daily plan.
                            mealCard("Desayuno", icon: "sun.max.fill", color: .orange, meal: plan.desayuno)
                            mealCard("Comida", icon: "sun.haze.fill", color: .yellow, meal: plan.comida)
                            mealCard("Cena", icon: "moon.stars.fill", color: .indigo, meal: plan.cena)
                        }

                        weeklyActionsCard

                        if let weeklyPlan = planStore.weeklyPlan(for: selectedWeekSlot) {
                            weeklyPlanCard(weeklyPlan)
                        }

                        Button("Regenerar Plan Diario") {
                            onCreatePlanTap()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                } else {
                    ContentUnavailableView(
                        "Sin plan nutricional",
                        systemImage: "list.bullet.clipboard",
                        description: Text("Completa el cuestionario para generar tu plan diario.")
                    )
                    .padding(.top, 80)

                    Button("Crear Plan Ahora") {
                        onCreatePlanTap()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Mi Plan")
            .background(Color(uiColor: .systemGroupedBackground))
            .sheet(isPresented: $isShowingFridgeScanner) {
                #if os(iOS)
                FridgeInventoryScannerView(
                    onAnalyze: onAnalyzeFridgeTap,
                    onApplyIngredients: { ingredients in
                        ingredientesRefri = ingredients.joined(separator: ", ")
                        actionMessage = "Inventario actualizado con \(ingredients.count) ingredientes detectados."
                    }
                )
                #else
                Text("Escáner de refri solo disponible en iOS")
                #endif
            }
        }
    }

    private func dailyGoalCard(_ plan: NutritionPlan) -> some View {
        VStack(spacing: 10) {
            Text("Tu Meta Diaria")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("\(plan.caloriasDiarias) kcal")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.green)

            HStack(spacing: 24) {
                macro("Proteína", "\(plan.proteinaGramos)g", color: .blue)
                macro("Carbos", "\(plan.carbohidratosGramos)g", color: .orange)
                macro("Grasas", "\(plan.grasasGramos)g", color: .purple)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var weeklyActionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Plan Semanal")
                .font(.headline)

            workflowSection

            Picker("Semana", selection: $selectedWeekSlot) {
                ForEach(WeeklyPlanSlot.allCases, id: \.self) { slot in
                    Text(slot.title).tag(slot)
                }
            }
            .pickerStyle(.segmented)

            TextField("Ajustes para regenerar (ej. más proteína en cena)", text: $ajustesSemanales, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)

            if !planStore.frequentAdjustments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(planStore.frequentAdjustments, id: \.self) { suggestion in
                            Button(suggestion) {
                                ajustesSemanales = suggestion
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                        }
                    }
                }
            }

            TextField("Ingredientes del refri (separados por coma)", text: $ingredientesRefri, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)

            Button {
                isShowingFridgeScanner = true
            } label: {
                Label("Analizar Refri (Inventario)", systemImage: "refrigerator.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Toggle("Reemplazar lista del súper actual", isOn: $replaceGroceryList)
                .font(.subheadline)
            Toggle("Auto-actualizar lista del súper al regenerar", isOn: $autoUpdateGroceryAfterPlan)
                .font(.subheadline)

            if let actionMessage {
                Text(actionMessage)
                    .font(.footnote)
                    .foregroundStyle(.green)
            }

            if let actionError {
                Text(actionError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await generateWeeklyPlan(useFridgeOnly: false) }
            } label: {
                if isGeneratingWeekly {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Regenerar Plan Semanal")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGeneratingWeekly || isGeneratingGrocery)

            Button {
                Task { await generateWeeklyPlan(useFridgeOnly: true) }
            } label: {
                Text("Regenerar con Ingredientes del Refri")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isGeneratingWeekly || isGeneratingGrocery)

            Button {
                Task { await generateWeeklyGroceryList() }
            } label: {
                if isGeneratingGrocery {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Generar Lista de Súper Semanal")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .disabled(isGeneratingWeekly || isGeneratingGrocery || planStore.weeklyPlan(for: selectedWeekSlot) == nil)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var workflowSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Workflow")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    workflowPill(
                        icon: "refrigerator.fill",
                        title: "Refri",
                        done: !ingredientesRefri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    workflowPill(
                        icon: "calendar.badge.clock",
                        title: "Plan 7 días",
                        done: planStore.weeklyPlan(for: selectedWeekSlot) != nil
                    )
                    workflowPill(
                        icon: "cart.badge.plus",
                        title: "Súper",
                        done: actionMessage?.contains("Lista semanal") == true
                    )
                    workflowPill(
                        icon: "checklist.checked",
                        title: "Tachar en Súper",
                        done: true
                    )
                }
            }
        }
    }

    private func workflowPill(icon: String, title: String, done: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(done ? Color.green.opacity(0.18) : Color(uiColor: .tertiarySystemFill))
        .foregroundStyle(done ? Color.green : .primary)
        .clipShape(Capsule())
    }

    private func weeklyPlanCard(_ weeklyPlan: WeeklyNutritionPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(selectedWeekSlot.title) (Lunes a Domingo)")
                .font(.headline)

            Text("Meta: \(weeklyPlan.caloriasObjetivoDiarias) kcal • P \(weeklyPlan.proteinaObjetivoGramos)g • C \(weeklyPlan.carbohidratosObjetivoGramos)g • G \(weeklyPlan.grasasObjetivoGramos)g")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(weeklyPlan.dias.enumerated()), id: \.offset) { index, day in
                        Button {
                            selectedWeeklyDayIndex = index
                        } label: {
                            Text(day.dia)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(selectedWeeklyDayIndex == index ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                                .foregroundStyle(selectedWeeklyDayIndex == index ? .white : .primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !weeklyPlan.dias.isEmpty {
                let safeIndex = min(selectedWeeklyDayIndex, weeklyPlan.dias.count - 1)
                let day = weeklyPlan.dias[safeIndex]
                VStack(alignment: .leading, spacing: 10) {
                    Text(day.dia)
                        .font(.title3.bold())

                    mealCard("Desayuno", icon: "sun.max.fill", color: .orange, meal: day.desayuno)
                    mealCard("Comida", icon: "sun.haze.fill", color: .yellow, meal: day.comida)
                    mealCard("Cena", icon: "moon.stars.fill", color: .indigo, meal: day.cena)

                    Text("Total estimado: \(day.caloriasTotales) kcal")
                        .font(.subheadline.weight(.semibold))
                }
            }

            if !weeklyPlan.recomendaciones.isEmpty {
                Text(weeklyPlan.recomendaciones)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func currentDayCard(_ day: WeeklyPlanDay, slot: WeeklyPlanSlot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(slot == .current ? "Hoy • \(day.dia)" : "\(slot.title) • \(day.dia)")
                .font(.headline)

            mealCard("Desayuno", icon: "sun.max.fill", color: .orange, meal: day.desayuno)
            mealCard("Comida", icon: "sun.haze.fill", color: .yellow, meal: day.comida)
            mealCard("Cena", icon: "moon.stars.fill", color: .indigo, meal: day.cena)

            Text("Total estimado de hoy: \(day.caloriasTotales) kcal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func macro(_ title: String, _ value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(color)
        }
    }

    private func mealCard(_ title: String, icon: String, color: Color, meal: NutritionMeal) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(meal.calorias) kcal").font(.caption).foregroundStyle(.secondary)
                }
                Text(meal.titulo).font(.headline)
                Text(meal.descripcion)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
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

    @MainActor
    private func generateWeeklyPlan(useFridgeOnly: Bool) async {
        actionError = nil
        actionMessage = nil
        isGeneratingWeekly = true
        defer { isGeneratingWeekly = false }

        do {
            let ajustes = useFridgeOnly ? "Prioriza recetas usando ingredientes del refri y minimiza compras." : ajustesSemanales
            let plan = try await onGenerateWeeklyPlanTap(selectedWeekSlot, ajustes, ingredientesRefri)
            if !ajustes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                planStore.saveFrequentAdjustment(ajustes)
            }
            selectedWeeklyDayIndex = 0
            if autoUpdateGroceryAfterPlan {
                let count = try await onGenerateWeeklyGroceryTap(plan, ingredientesRefri, replaceGroceryList)
                actionMessage = "\(selectedWeekSlot.title): plan generado (\(plan.dias.count) días) y lista actualizada (\(count) productos)."
            } else {
                actionMessage = "\(selectedWeekSlot.title): generado con \(plan.dias.count) días."
            }
        } catch {
            actionError = "No se pudo regenerar el plan semanal: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func generateWeeklyGroceryList() async {
        guard let weeklyPlan = planStore.weeklyPlan(for: selectedWeekSlot) else {
            actionError = "Primero genera el plan de \(selectedWeekSlot.title.lowercased())."
            return
        }
        actionError = nil
        actionMessage = nil
        isGeneratingGrocery = true
        defer { isGeneratingGrocery = false }

        do {
            let count = try await onGenerateWeeklyGroceryTap(weeklyPlan, ingredientesRefri, replaceGroceryList)
            actionMessage = replaceGroceryList
                ? "Lista semanal reemplazada con \(count) productos."
                : "Lista semanal combinada. Se agregaron \(count) productos."
        } catch {
            actionError = "No se pudo generar la lista del súper: \(error.localizedDescription)"
        }
    }
}

#Preview {
    let store = NutritionPlanStore()
    return PlanDailyView(
        planStore: store,
        onCreatePlanTap: {},
        onGenerateWeeklyPlanTap: { _, _, _ in
            WeeklyNutritionPlan(
                caloriasObjetivoDiarias: 2100,
                proteinaObjetivoGramos: 180,
                carbohidratosObjetivoGramos: 200,
                grasasObjetivoGramos: 70,
                dias: [
                    WeeklyPlanDay(
                        dia: "Lunes",
                        desayuno: NutritionMeal(titulo: "Huevos con avena", calorias: 500, descripcion: "3 huevos + avena con fruta"),
                        comida: NutritionMeal(titulo: "Pollo y arroz", calorias: 900, descripcion: "200g pollo, arroz integral, verduras"),
                        cena: NutritionMeal(titulo: "Salmón y ensalada", calorias: 700, descripcion: "Filete con ensalada grande"),
                        caloriasTotales: 2100
                    )
                ],
                recomendaciones: "Mantén hidratación constante y distribución similar los 7 días."
            )
        },
        onGenerateWeeklyGroceryTap: { _, _, _ in 8 },
        onAnalyzeFridgeTap: { _ in ["huevo", "pollo", "brócoli", "yogurt griego"] }
    )
}
