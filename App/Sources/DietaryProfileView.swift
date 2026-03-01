import SwiftUI
import ComeSanoCore
import ComeSanoHealthKit

struct DietaryProfileView: View {
    enum Sex: String, CaseIterable {
        case female = "Mujer"
        case male = "Hombre"
    }

    enum DietaryPreference: String, CaseIterable {
        case none = "Ninguna"
        case vegetarian = "Vegetariana"
        case keto = "Keto"
        case lactoseFree = "Sin Lactosa"
    }

    let initialProfile: UserProfile
    let bodyMetrics: HealthBodyMetrics?
    let planGenerator: any NutritionPlanGenerating
    let onPlanAccepted: (UserProfile, NutritionPlan) -> Void

    @State private var name = ""
    @State private var selectedGoal: PrimaryGoal = .loseFat
    @State private var selectedSex: Sex = .male
    @State private var age = 30
    @State private var heightCM = 170.0
    @State private var weightKG = 75.0
    @State private var gymDays = 4
    @State private var preference: DietaryPreference = .none
    @State private var allergies = ""
    @State private var isGenerating = false
    @State private var generatedPlan: NutritionPlan?
    @State private var generationError: String?
    @State private var didApplyHealthPrefill = false
    @State private var allowManualHealthEdit = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Tus Datos") {
                    TextField("Nombre", text: $name)
                    Picker("Sexo biológico", selection: $selectedSex) {
                        ForEach(Sex.allCases, id: \.self) { sex in
                            Text(sex.rawValue).tag(sex)
                        }
                    }
                    Stepper("Edad: \(age) años", value: $age, in: 14...90)
                        .disabled(isAgeFromHealth && !allowManualHealthEdit)
                    Stepper("Peso: \(Int(weightKG.rounded())) kg", value: $weightKG, in: 35...220, step: 1)
                        .disabled(isWeightFromHealth && !allowManualHealthEdit)
                    Stepper("Altura: \(Int(heightCM.rounded())) cm", value: $heightCM, in: 130...220, step: 1)
                        .disabled(isHeightFromHealth && !allowManualHealthEdit)
                    if hasAnyHealthMetric {
                        Toggle("Editar manualmente datos de Salud", isOn: $allowManualHealthEdit)
                            .font(.footnote)
                    }
                }
                if !hasAnyHealthMetric {
                    Section {
                        Text("No se pudieron leer datos de Apple Health. Puedes capturarlos manualmente.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Metas y Estilo de Vida") {
                    Picker("Meta principal", selection: $selectedGoal) {
                        Text("Perder Peso").tag(PrimaryGoal.loseFat)
                        Text("Mantener Peso").tag(PrimaryGoal.maintain)
                        Text("Ganar Masa Muscular").tag(PrimaryGoal.gainMuscle)
                    }
                    Stepper("Días de gym por semana: \(gymDays)", value: $gymDays, in: 0...7)
                    Picker("Preferencia alimenticia", selection: $preference) {
                        ForEach(DietaryPreference.allCases, id: \.self) { pref in
                            Text(pref.rawValue).tag(pref)
                        }
                    }
                    TextField("Alergias o alimentos a evitar", text: $allergies, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section {
                    Button {
                        Task { await generatePlan() }
                    } label: {
                        HStack {
                            Spacer()
                            if isGenerating {
                                ProgressView().tint(.white)
                            } else {
                                Text("Generar Mi Plan")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.green)
                    .foregroundStyle(.white)
                }

                if let generationError {
                    Section("Error") {
                        Text(generationError)
                            .foregroundStyle(.red)
                    }
                }

                if let plan = generatedPlan {
                    Section("Tu Meta Diaria") {
                        HStack {
                            Text("Calorías")
                            Spacer()
                            Text("\(plan.caloriasDiarias) kcal").fontWeight(.semibold)
                        }
                        HStack {
                            Text("Proteína")
                            Spacer()
                            Text("\(plan.proteinaGramos) g").foregroundStyle(.blue)
                        }
                        HStack {
                            Text("Carbohidratos")
                            Spacer()
                            Text("\(plan.carbohidratosGramos) g").foregroundStyle(.orange)
                        }
                        HStack {
                            Text("Grasas")
                            Spacer()
                            Text("\(plan.grasasGramos) g").foregroundStyle(.purple)
                        }
                    }

                    Section("Menú Sugerido Día 1") {
                        mealRow("Desayuno", meal: plan.desayuno)
                        mealRow("Comida", meal: plan.comida)
                        mealRow("Cena", meal: plan.cena)
                    }

                    Section {
                        Button("Aceptar Plan y Usar en Dashboard") {
                            let profile = UserProfile(
                                name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Usuario" : name,
                                age: age,
                                heightCM: heightCM,
                                weightKG: weightKG,
                                primaryGoal: selectedGoal,
                                dailyCalorieTarget: Double(plan.caloriasDiarias),
                                hydrationTargetML: initialProfile.hydrationTargetML
                            )
                            onPlanAccepted(profile, plan)
                        }
                        .fontWeight(.bold)
                    }
                }
            }
            .navigationTitle("Plan Nutricional")
            .task {
                prefillFields()
            }
            .onChange(of: bodyMetrics?.weightKG) { _, _ in
                applyHealthPrefillIfAvailable()
            }
            .onChange(of: bodyMetrics?.heightCM) { _, _ in
                applyHealthPrefillIfAvailable()
            }
            .onChange(of: bodyMetrics?.ageYears) { _, _ in
                applyHealthPrefillIfAvailable()
            }
        }
    }

    private func mealRow(_ label: String, meal: NutritionMeal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(meal.calorias) kcal").font(.caption).foregroundStyle(.secondary)
            }
            Text(meal.titulo).font(.headline)
            Text(meal.descripcion).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func prefillFields() {
        name = initialProfile.name
        selectedGoal = initialProfile.primaryGoal
        age = initialProfile.age
        heightCM = initialProfile.heightCM
        weightKG = initialProfile.weightKG

        applyHealthPrefillIfAvailable()
    }

    private var hasAnyHealthMetric: Bool {
        isWeightFromHealth || isHeightFromHealth || isAgeFromHealth
    }

    private var isWeightFromHealth: Bool {
        (bodyMetrics?.weightKG ?? 0) > 0
    }

    private var isHeightFromHealth: Bool {
        (bodyMetrics?.heightCM ?? 0) > 0
    }

    private var isAgeFromHealth: Bool {
        (bodyMetrics?.ageYears ?? 0) > 0
    }

    private func applyHealthPrefillIfAvailable() {
        guard !didApplyHealthPrefill else { return }
        guard let metrics = bodyMetrics else { return }

        var applied = false
        if let weight = metrics.weightKG, weight > 0 {
            weightKG = weight
            applied = true
        }
        if let height = metrics.heightCM, height > 0 {
            heightCM = height
            applied = true
        }
        if let fetchedAge = metrics.ageYears, fetchedAge > 0 {
            age = fetchedAge
            applied = true
        }

        if applied {
            didApplyHealthPrefill = true
        }
    }

    private func generatePlan() async {
        isGenerating = true
        generationError = nil

        let input = NutritionProfileInput(
            nombre: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Usuario" : name,
            sexo: selectedSex.rawValue,
            edad: age,
            alturaCM: heightCM,
            pesoKG: weightKG,
            meta: selectedGoal,
            diasGym: gymDays,
            preferenciaAlimenticia: preference.rawValue,
            alergias: allergies.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        do {
            let aiPlan = try await planGenerator.generatePlan(for: input)
            generatedPlan = aiPlan
        } catch {
            generationError = "No se pudo generar con IA. Se creó un plan local base. Detalle: \(error.localizedDescription)"
            generatedPlan = localFallbackPlan()
        }

        isGenerating = false
    }

    private func calculateTDEE() -> Int {
        // Mifflin-St Jeor
        let bmr: Double
        switch selectedSex {
        case .male:
            bmr = (10 * weightKG) + (6.25 * heightCM) - (5 * Double(age)) + 5
        case .female:
            bmr = (10 * weightKG) + (6.25 * heightCM) - (5 * Double(age)) - 161
        }

        let activity: Double
        switch gymDays {
        case 0...1: activity = 1.2
        case 2...3: activity = 1.375
        case 4...5: activity = 1.55
        default: activity = 1.725
        }

        return Int((bmr * activity).rounded())
    }

    private func adjustedCalories(fromTDEE tdee: Int) -> Int {
        switch selectedGoal {
        case .loseFat:
            return max(1300, tdee - 400)
        case .maintain:
            return tdee
        case .gainMuscle:
            return tdee + 250
        }
    }

    private func calculateMacros(targetCalories: Int) -> (protein: Int, carbs: Int, fats: Int) {
        let proteinPerKG: Double = selectedGoal == .gainMuscle ? 2.0 : 1.8
        let protein = Int((weightKG * proteinPerKG).rounded())
        let fats = Int((weightKG * 0.8).rounded())
        let caloriesLeft = max(0, targetCalories - (protein * 4) - (fats * 9))
        let carbs = Int((Double(caloriesLeft) / 4.0).rounded())
        return (protein, carbs, fats)
    }

    private func breakfastSuggestion() -> NutritionMeal {
        switch preference {
        case .vegetarian:
            return .init(titulo: "Avena proteica con yogurt griego", calorias: 450, descripcion: "Avena, yogurt griego, frutos rojos y nueces.")
        case .keto:
            return .init(titulo: "Huevos con aguacate y queso", calorias: 430, descripcion: "3 huevos, aguacate y queso fresco.")
        case .lactoseFree:
            return .init(titulo: "Smoothie de proteína sin lactosa", calorias: 420, descripcion: "Leche vegetal, proteína aislada, plátano y avena.")
        case .none:
            return .init(titulo: "Omelette de claras con tostada integral", calorias: 410, descripcion: "Claras, espinaca y pan integral.")
        }
    }

    private func lunchSuggestion() -> NutritionMeal {
        switch preference {
        case .vegetarian:
            return .init(titulo: "Bowl de quinoa con garbanzos", calorias: 700, descripcion: "Quinoa, garbanzos, verduras salteadas y aceite de oliva.")
        case .keto:
            return .init(titulo: "Salmón con ensalada verde", calorias: 720, descripcion: "Salmón a la plancha, pepino, aguacate y semillas.")
        case .lactoseFree:
            return .init(titulo: "Pollo con arroz y vegetales", calorias: 690, descripcion: "Pechuga de pollo, arroz jazmín y verduras.")
        case .none:
            return .init(titulo: "Pollo a la plancha con camote", calorias: 680, descripcion: "Pechuga, camote horneado y ensalada.")
        }
    }

    private func dinnerSuggestion() -> NutritionMeal {
        switch preference {
        case .vegetarian:
            return .init(titulo: "Tofu con verduras al wok", calorias: 520, descripcion: "Tofu, pimiento, calabaza y salsa ligera.")
        case .keto:
            return .init(titulo: "Carne magra con brócoli", calorias: 540, descripcion: "Carne de res magra y brócoli con mantequilla.")
        case .lactoseFree:
            return .init(titulo: "Atún con papa y ensalada", calorias: 510, descripcion: "Atún, papa cocida y ensalada verde.")
        case .none:
            return .init(titulo: "Pescado al horno con arroz", calorias: 500, descripcion: "Pescado blanco, arroz y espárragos.")
        }
    }

    private func localFallbackPlan() -> NutritionPlan {
        let tdee = calculateTDEE()
        let targetCalories = adjustedCalories(fromTDEE: tdee)
        let macros = calculateMacros(targetCalories: targetCalories)
        return NutritionPlan(
            caloriasDiarias: targetCalories,
            proteinaGramos: macros.protein,
            carbohidratosGramos: macros.carbs,
            grasasGramos: macros.fats,
            desayuno: breakfastSuggestion(),
            comida: lunchSuggestion(),
            cena: dinnerSuggestion(),
            source: "local"
        )
    }
}

#Preview {
    DietaryProfileView(
        initialProfile: UserProfile(
            name: "Usuario",
            age: 30,
            heightCM: 170,
            weightKG: 75,
            primaryGoal: .loseFat,
            dailyCalorieTarget: 2100
        ),
        bodyMetrics: nil,
        planGenerator: EmptyNutritionPlanGenerator(),
        onPlanAccepted: { _, _ in }
    )
}
