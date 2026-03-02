import SwiftUI
import ComeSanoCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct DashboardView: View {
    public typealias AISuggestionProvider = @Sendable (_ snapshot: DailyCalorieSnapshot, _ goal: PrimaryGoal) async -> String?
    public typealias MacroTargetsProvider = (_ date: Date) -> (protein: Double, carbs: Double, fat: Double)?

    public enum QuickAddKind: String, CaseIterable, Identifiable {
        case coffee
        case waterGlass
        case apple

        public var id: String { rawValue }
    }

    @StateObject private var viewModel: DashboardViewModel
    @State private var selectedDate: Date = .now
    @State private var isShowingCustomMealPrompt = false
    @State private var customMealCaloriesText = "400"
    @State private var aiSuggestion: String?
    @State private var isLoadingAISuggestion = false
    private let onQuickAdd: (QuickAddKind) -> Void
    private let onQuickAddCustomMeal: (Double) -> Void
    private let aiSuggestionProvider: AISuggestionProvider?
    private let macroTargetsProvider: MacroTargetsProvider?

    public init(
        viewModel: DashboardViewModel,
        onQuickAdd: @escaping (QuickAddKind) -> Void = { _ in },
        onQuickAddCustomMeal: @escaping (Double) -> Void = { _ in },
        aiSuggestionProvider: AISuggestionProvider? = nil,
        macroTargetsProvider: MacroTargetsProvider? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onQuickAdd = onQuickAdd
        self.onQuickAddCustomMeal = onQuickAddCustomMeal
        self.aiSuggestionProvider = aiSuggestionProvider
        self.macroTargetsProvider = macroTargetsProvider
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                if let error = viewModel.errorMessage {
                    ContentUnavailableView("Error de lectura", systemImage: "exclamationmark.triangle", description: Text(error))
                        .frame(maxWidth: .infinity, minHeight: 380)
                } else if let selectedSnapshot {
                    VStack(spacing: 20) {
                        WeeklyCalendarView(
                            snapshots: viewModel.weekSnapshots,
                            selectedDate: selectedDate,
                            onSelectDate: { selectedDate = $0 },
                            onMoveWeek: moveWeek
                        )

                        Text(selectedDateText(for: selectedSnapshot.date))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        CalorieRingCard(
                            consumed: selectedSnapshot.consumedKcal,
                            baseGoal: selectedSnapshot.targetKcal,
                            activeBurned: selectedSnapshot.activeBurnedKcal,
                            basalBurned: selectedSnapshot.basalBurnedKcal
                        )

                        MacrosCardView(
                            proteina: (
                                consumido: selectedSnapshot.consumedProteinGrams,
                                meta: macroTargets(for: selectedSnapshot).protein
                            ),
                            carbohidratos: (
                                consumido: selectedSnapshot.consumedCarbsGrams,
                                meta: macroTargets(for: selectedSnapshot).carbs
                            ),
                            grasas: (
                                consumido: selectedSnapshot.consumedFatGrams,
                                meta: macroTargets(for: selectedSnapshot).fat
                            )
                        )

                        SmartSuggestionCard(
                            message: aiSuggestion ?? smartSuggestion(for: selectedSnapshot, goal: viewModel.currentGoal),
                            isLoadingAI: isLoadingAISuggestion,
                            isFromAI: aiSuggestion != nil
                        )

                        QuickAddSection(
                            onQuickAdd: onQuickAdd,
                            onCustomMealTap: {
                                customMealCaloriesText = "400"
                                isShowingCustomMealPrompt = true
                            }
                        )

                        HStack(spacing: 15) {
                            MacroRingCard(
                                title: "Adherencia",
                                amount: "\(Int(selectedSnapshot.dailyAdherenceScore.rounded()))%",
                                color: .blue,
                                progress: max(0, min(selectedSnapshot.dailyAdherenceScore / 100, 1))
                            )
                            MacroRingCard(
                                title: "Desviación",
                                amount: "\(Int(selectedSnapshot.targetDeltaKcal.rounded())) kcal",
                                color: selectedSnapshot.targetDeltaKcal <= 0 ? .green : .orange,
                                progress: max(0, min(1 - (abs(selectedSnapshot.targetDeltaKcal) / max(selectedSnapshot.targetKcal, 1)), 1))
                            )
                        }
                    }
                    .padding()
                } else {
                    ProgressView("Cargando datos")
                        .frame(maxWidth: .infinity, minHeight: 380)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 100)
            }
            .navigationTitle("Mi Progreso")
            .background(Color.dashboardGroupedBackground)
            .task { await viewModel.refresh() }
            .task(id: suggestionTaskID) {
                await refreshAISuggestion()
            }
            .alert("Comida estándar", isPresented: $isShowingCustomMealPrompt) {
                TextField("Calorías", text: $customMealCaloriesText)

                Button("Cancelar", role: .cancel) {}
                Button("Agregar") {
                    let trimmed = customMealCaloriesText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = Double(trimmed) ?? 400
                    let safeCalories = max(0, value)
                    onQuickAddCustomMeal(safeCalories)
                }
            } message: {
                Text("Ingresa calorías para registrar. Valor por default: 400 kcal.")
            }
            .onChange(of: viewModel.weekSnapshots.count) { _, _ in
                let snapshots = viewModel.weekSnapshots
                guard !snapshots.isEmpty else { return }
                let calendar = Calendar.current
                if snapshots.contains(where: { calendar.isDate($0.date, inSameDayAs: selectedDate) }) {
                    return
                }
                if let today = snapshots.first(where: { calendar.isDateInToday($0.date) }) {
                    selectedDate = today.date
                } else if let first = snapshots.first {
                    selectedDate = first.date
                }
            }
        }
    }

    private var selectedSnapshot: DailyCalorieSnapshot? {
        let calendar = Calendar.current
        return viewModel.weekSnapshots.first(where: { calendar.isDate($0.date, inSameDayAs: selectedDate) })
            ?? viewModel.weekSnapshots.first
    }

    private func moveWeek(_ direction: Int) {
        let calendar = Calendar.current
        guard let targetDate = calendar.date(byAdding: .day, value: direction * 7, to: selectedDate) else { return }
        selectedDate = targetDate
        Task { await viewModel.refresh(referenceDate: targetDate) }
    }

    private func selectedDateText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: date).capitalized
    }

    private func smartSuggestion(for snapshot: DailyCalorieSnapshot, goal: PrimaryGoal) -> String {
        let consumed = snapshot.consumedKcal
        let target = snapshot.targetKcal
        let active = snapshot.activeBurnedKcal
        let adjustedBudget = target + active
        let targetDelta = consumed - adjustedBudget
        let net = consumed - adjustedBudget

        let targetDeltaText = Int(abs(targetDelta).rounded())
        let netText = Int(abs(net).rounded())

        switch goal {
        case .loseFat:
            if net <= -250 {
                return "Objetivo perder grasa: vas bien, tienes margen de \(netText) kcal vs meta ajustada por ejercicio. Prioriza proteína y buena hidratación."
            }
            if net > 100 {
                return "Objetivo perder grasa: hoy vas \(netText) kcal arriba de la meta ajustada. Ajusta porciones en la próxima comida."
            }
            if targetDelta > 150 {
                return "Objetivo perder grasa: vas \(targetDeltaText) kcal arriba de la meta ajustada por ejercicio."
            }
            return "Objetivo perder grasa: vas en buen rango con ejercicio activo. Evita sumar calorías líquidas extras."

        case .maintain:
            if abs(net) <= 150 {
                return "Objetivo mantener: vas muy balanceado (±\(netText) kcal) sobre la meta ajustada. Buen control del día."
            }
            if net < -150 {
                return "Objetivo mantener: hoy quedas corto por \(netText) kcal frente a la meta ajustada. Agrega una colación ligera."
            }
            return "Objetivo mantener: hoy vas pasado por \(netText) kcal frente a la meta ajustada. Reduce densidad calórica en la cena."

        case .gainMuscle:
            if net >= 150 {
                return "Objetivo ganar masa: buen superávit de \(netText) kcal vs meta ajustada. Asegura proteína suficiente."
            }
            if net <= -150 {
                return "Objetivo ganar masa: estás en déficit de \(netText) kcal frente a meta ajustada. Sube carbos y proteína."
            }
            if targetDelta <= -200 {
                return "Objetivo ganar masa: te faltan \(targetDeltaText) kcal para tu meta ajustada por ejercicio. Añade una comida o shake."
            }
            return "Objetivo ganar masa: vas cerca del objetivo. Mantén distribución de comidas durante el día."
        }

    }

    private var suggestionTaskID: String {
        let snapshotStamp = selectedSnapshot?.date.timeIntervalSince1970 ?? 0
        return "\(snapshotStamp)-\(viewModel.currentGoal.rawValue)"
    }

    private func macroTargets(for snapshot: DailyCalorieSnapshot) -> (protein: Double, carbs: Double, fat: Double) {
        if let provided = macroTargetsProvider?(snapshot.date) {
            return provided
        }
        let calories = max(snapshot.targetKcal, 1)
        // Fallback distribution when no explicit plan targets exist.
        return (
            protein: (calories * 0.30) / 4.0,
            carbs: (calories * 0.40) / 4.0,
            fat: (calories * 0.30) / 9.0
        )
    }

    @MainActor
    private func refreshAISuggestion() async {
        aiSuggestion = nil
        guard let selectedSnapshot, let provider = aiSuggestionProvider else {
            isLoadingAISuggestion = false
            return
        }

        isLoadingAISuggestion = true
        let suggestion = await provider(selectedSnapshot, viewModel.currentGoal)
        if let suggestion, !suggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            aiSuggestion = suggestion
        }
        isLoadingAISuggestion = false
    }
}

private struct SmartSuggestionCard: View {
    let message: String
    let isLoadingAI: Bool
    let isFromAI: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.mint)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Sugerencia Inteligente")
                    if isFromAI {
                        Text("IA")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.mint.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    if isLoadingAI {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dashboardCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct QuickAddSection: View {
    let onQuickAdd: (DashboardView.QuickAddKind) -> Void
    let onCustomMealTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Registro Rápido")
                .font(.headline)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 15) {
                    QuickAddButton(
                        icon: "cup.and.saucer.fill",
                        title: "Mi Café",
                        subtitle: "45 kcal • 250ml",
                        color: .brown
                    ) {
                        onQuickAdd(.coffee)
                    }

                    QuickAddButton(
                        icon: "drop.fill",
                        title: "Vaso de Agua",
                        subtitle: "250 ml",
                        color: .cyan
                    ) {
                        onQuickAdd(.waterGlass)
                    }

                    QuickAddButton(
                        icon: "apple.logo",
                        title: "Manzana",
                        subtitle: "95 kcal",
                        color: .red
                    ) {
                        onQuickAdd(.apple)
                    }

                    QuickAddButton(
                        icon: "fork.knife",
                        title: "Comida estándar",
                        subtitle: "400 kcal (editable)",
                        color: .orange
                    ) {
                        onCustomMealTap()
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

private struct QuickAddButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 45, height: 45)

                    Image(systemName: icon)
                        .foregroundStyle(color)
                        .font(.title3)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(width: 150, alignment: .leading)
            .background(Color.dashboardCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

struct WeeklyCalendarView: View {
    let snapshots: [DailyCalorieSnapshot]
    let selectedDate: Date
    let onSelectDate: (Date) -> Void
    let onMoveWeek: (Int) -> Void

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    onMoveWeek(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                }

                HStack {
                    ForEach(snapshots, id: \.date) { snapshot in
                        let isSelected = calendar.isDate(snapshot.date, inSameDayAs: selectedDate)
                        Button {
                            onSelectDate(snapshot.date)
                        } label: {
                            VStack(spacing: 8) {
                                Text(shortDaySymbol(for: snapshot.date))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(isSelected ? .white : .gray)

                                Text(dayNumber(for: snapshot.date))
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(isSelected ? .white : .primary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(isSelected ? Color.green : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    onMoveWeek(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                }
            }
        }
        .padding()
        .background(Color.dashboardCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    private func shortDaySymbol(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date).uppercased()
    }

    private func dayNumber(for date: Date) -> String {
        String(calendar.component(.day, from: date))
    }
}

struct CalorieRingCard: View {
    var consumed: Double
    var baseGoal: Double
    var activeBurned: Double
    var basalBurned: Double

    var progress: CGFloat {
        let safeBudget = max(adjustedBudget, 1)
        return CGFloat(max(0, min(consumed / safeBudget, 1)))
    }

    private var adjustedBudget: Double {
        baseGoal + activeBurned
    }

    private var adjustedDelta: Double {
        consumed - adjustedBudget
    }

    private var ringColor: Color {
        consumed > adjustedBudget ? .red : .green
    }

    var body: some View {
        VStack {
            HStack {
                Text("Balance Diario")
                    .font(.headline)
                Spacer()
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
            }
            .padding(.bottom, 10)

            HStack(spacing: 30) {
                ZStack {
                    Circle()
                        .stroke(lineWidth: 15)
                        .opacity(0.2)
                        .foregroundStyle(ringColor)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(style: StrokeStyle(lineWidth: 15, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(ringColor)
                        .rotationEffect(.degrees(270))
                        .animation(.easeInOut(duration: 1), value: progress)

                    VStack {
                        Text("\(Int(consumed.rounded()))")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("kcal")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                }
                .frame(width: 120, height: 120)

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading) {
                        Text("Meta base")
                            .font(.subheadline)
                            .foregroundStyle(.gray)
                        Text("\(Int(baseGoal.rounded())) kcal")
                            .font(.headline)
                    }
                    VStack(alignment: .leading) {
                        Text("Ejercicio activo")
                            .font(.subheadline)
                            .foregroundStyle(.gray)
                        Text("+\(Int(activeBurned.rounded())) kcal")
                            .font(.headline)
                            .foregroundStyle(.orange)
                    }
                    VStack(alignment: .leading) {
                        Text("Presupuesto")
                            .font(.subheadline)
                            .foregroundStyle(.gray)
                        Text("\(Int(adjustedBudget.rounded())) kcal")
                            .font(.headline)
                            .foregroundStyle(.green)
                    }
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Image(systemName: adjustedDelta <= 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .foregroundStyle(adjustedDelta <= 0 ? .green : .red)
                Text("Balance ajustado: \(Int(adjustedDelta.rounded())) kcal")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)

            Text("La meta se ajusta solo con ejercicio activo. El gasto basal es informativo.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)

            Text("Basal (informativo): \(Int(basalBurned.rounded())) kcal")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color.dashboardCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
    }
}

struct MacrosCardView: View {
    var proteina: (consumido: Double, meta: Double)
    var carbohidratos: (consumido: Double, meta: Double)
    var grasas: (consumido: Double, meta: Double)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Macronutrientes")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 16) {
                MacroDetailRow(
                    titulo: "Proteína",
                    consumido: proteina.consumido,
                    meta: proteina.meta,
                    color: .blue
                )
                MacroDetailRow(
                    titulo: "Carbohidratos",
                    consumido: carbohidratos.consumido,
                    meta: carbohidratos.meta,
                    color: .orange
                )
                MacroDetailRow(
                    titulo: "Grasas",
                    consumido: grasas.consumido,
                    meta: grasas.meta,
                    color: .purple
                )
            }
        }
        .padding(20)
        .background(Color.dashboardCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}

private struct MacroDetailRow: View {
    let titulo: String
    let consumido: Double
    let meta: Double
    let color: Color

    private var progreso: Double {
        let safeMeta = max(meta, 1)
        return min(max(consumido / safeMeta, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom) {
                Text(titulo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("\(Int(consumido.rounded()))g")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    Text("/ \(Int(meta.rounded()))g")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.15))
                        .frame(height: 8)

                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width * progreso, height: 8)
                        .animation(.easeOut(duration: 0.8), value: progreso)
                }
            }
            .frame(height: 8)
        }
    }
}

struct MacroRingCard: View {
    var title: String
    var amount: String
    var color: Color
    var progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.gray)

            HStack {
                Text(amount)
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()

                ZStack {
                    Circle()
                        .stroke(lineWidth: 5)
                        .opacity(0.2)
                        .foregroundStyle(color)

                    Circle()
                        .trim(from: 0, to: CGFloat(max(0, min(progress, 1))))
                        .stroke(style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .foregroundStyle(color)
                        .rotationEffect(.degrees(270))
                }
                .frame(width: 30, height: 30)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.dashboardCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

private extension Color {
    static var dashboardGroupedBackground: Color {
        #if canImport(UIKit)
        return Color(uiColor: .systemGroupedBackground)
        #elseif canImport(AppKit)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color.gray.opacity(0.08)
        #endif
    }

    static var dashboardCardBackground: Color {
        #if canImport(UIKit)
        return Color(uiColor: .secondarySystemGroupedBackground)
        #elseif canImport(AppKit)
        return Color(nsColor: .textBackgroundColor)
        #else
        return Color.white.opacity(0.9)
        #endif
    }
}

#Preview {
    DashboardView(
        viewModel: DashboardViewModel(
            profile: UserProfile(
                name: "Rocas",
                age: 33,
                heightCM: 178,
                weightKG: 80,
                primaryGoal: .loseFat,
                dailyCalorieTarget: 2100
            ),
            burnProvider: MockBurnProvider(),
            intakeProvider: MockIntakeProvider()
        )
    )
}
