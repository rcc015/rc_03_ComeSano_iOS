import SwiftUI
import ComeSanoCore
import ComeSanoPersistence

enum FoodLogQuickAddResult: Sendable {
    case added
    case alreadyExists
    case maxReached
    case error(String)
}

@MainActor
final class FoodLogViewModel: ObservableObject {
    @Published private(set) var records: [FoodItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let foodStore: FoodCatalogStore

    init(foodStore: FoodCatalogStore) {
        self.foodStore = foodStore
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let items = try await foodStore.fetchFoodItems()
            records = items.sorted {
                ($0.loggedAt ?? .distantPast) > ($1.loggedAt ?? .distantPast)
            }
            errorMessage = nil
        } catch {
            errorMessage = "No se pudo cargar el diario: \(error.localizedDescription)"
        }
    }

    func deleteRecords(offsets: IndexSet) async {
        var next = records
        next.remove(atOffsets: offsets)
        do {
            try await foodStore.save(foodItems: next)
            records = next
            errorMessage = nil
        } catch {
            errorMessage = "No se pudo borrar el registro: \(error.localizedDescription)"
        }
    }

    func delete(records recordsToDelete: [FoodItem], offsets: IndexSet) async {
        let idsToDelete = offsets.map { recordsToDelete[$0].id }
        var next = records
        next.removeAll { idsToDelete.contains($0.id) }
        do {
            try await foodStore.save(foodItems: next)
            records = next
            errorMessage = nil
        } catch {
            errorMessage = "No se pudo borrar el registro: \(error.localizedDescription)"
        }
    }
}

struct FoodLogView: View {
    @StateObject private var viewModel: FoodLogViewModel
    @State private var selectedDate: Date = .now
    @State private var weekStart: Date
    @State private var actionMessage: String?
    private let calendar = Calendar.current
    private let onRepeatTodayTap: (FoodItem) async throws -> Void
    private let onAddToQuickAddTap: (FoodItem) async -> FoodLogQuickAddResult

    init(
        viewModel: FoodLogViewModel,
        onRepeatTodayTap: @escaping (FoodItem) async throws -> Void = { _ in },
        onAddToQuickAddTap: @escaping (FoodItem) async -> FoodLogQuickAddResult = { _ in .error("Acción no disponible.") }
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onRepeatTodayTap = onRepeatTodayTap
        self.onAddToQuickAddTap = onAddToQuickAddTap
        let today = Calendar.current.startOfDay(for: .now)
        let weekday = Calendar.current.component(.weekday, from: today)
        let mondayOffset = (weekday + 5) % 7
        _weekStart = State(initialValue: Calendar.current.date(byAdding: .day, value: -mondayOffset, to: today) ?? today)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    WeeklyFoodLogCalendarView(
                        weekStart: weekStart,
                        selectedDate: selectedDate,
                        onSelectDate: { selectedDate = $0 },
                        onMoveWeek: { direction in
                            if let nextWeek = calendar.date(byAdding: .day, value: direction * 7, to: weekStart) {
                                weekStart = nextWeek
                                if !isDate(selectedDate, inWeekStartingAt: nextWeek) {
                                    selectedDate = nextWeek
                                }
                            }
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                    .listRowBackground(Color.clear)
                }

                Section {
                    if filteredRecords.isEmpty, !viewModel.isLoading {
                        ContentUnavailableView(
                            "No hay comidas este día",
                            systemImage: "fork.knife.circle",
                            description: Text("No hay registros para \(selectedDateLabel).")
                        )
                    } else {
                        ForEach(filteredRecords) { record in
                            HStack(spacing: 15) {
                                ZStack {
                                    Circle()
                                        .fill(Color.orange.opacity(0.2))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: "flame.fill")
                                        .foregroundStyle(.orange)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)

                                    if let date = record.loggedAt {
                                        Text(date, style: .time)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 6) {
                                    Text("\(Int(record.nutrition.calories.rounded())) kcal")
                                        .font(.system(.headline, design: .rounded))
                                        .fontWeight(.bold)

                                    HStack(spacing: 6) {
                                        Button {
                                            Task { await repeatRecordToday(record) }
                                        } label: {
                                            Image(systemName: "arrow.clockwise.circle")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)
                                        .accessibilityLabel("Repetir en hoy")

                                        Button {
                                            Task { await addRecordToQuickAdd(record) }
                                        } label: {
                                            Image(systemName: "bolt.badge.plus")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)
                                        .accessibilityLabel("Agregar a registro rápido")
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete { offsets in
                            Task { await viewModel.delete(records: filteredRecords, offsets: offsets) }
                        }
                    }
                } header: {
                    HStack {
                        Text(selectedDateLabel)
                        Spacer()
                        Text("\(filteredRecords.count) registro\(filteredRecords.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Diario de Comidas")
            .listStyle(.insetGrouped)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            .task { await viewModel.refresh() }
            .refreshable { await viewModel.refresh() }
            .alert("Error", isPresented: Binding(get: {
                viewModel.errorMessage != nil
            }, set: { _ in })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert("Diario", isPresented: Binding(
                get: { actionMessage != nil },
                set: { isPresented in
                    if !isPresented { actionMessage = nil }
                }
            )) {
                Button("OK", role: .cancel) { actionMessage = nil }
            } message: {
                Text(actionMessage ?? "")
            }
        }
    }

    private var filteredRecords: [FoodItem] {
        viewModel.records.filter {
            guard let loggedAt = $0.loggedAt else { return false }
            return calendar.isDate(loggedAt, inSameDayAs: selectedDate)
        }
    }

    private var selectedDateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.dateFormat = "EEEE d 'de' MMMM"
        return formatter.string(from: selectedDate).capitalized
    }

    private func isDate(_ date: Date, inWeekStartingAt weekStart: Date) -> Bool {
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { return false }
        return date >= weekStart && date < weekEnd
    }

    @MainActor
    private func repeatRecordToday(_ record: FoodItem) async {
        do {
            try await onRepeatTodayTap(record)
            actionMessage = "Se registró nuevamente en tu día actual."
            await viewModel.refresh()
        } catch {
            actionMessage = "No se pudo repetir el alimento: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func addRecordToQuickAdd(_ record: FoodItem) async {
        let result = await onAddToQuickAddTap(record)
        switch result {
        case .added:
            actionMessage = "Se agregó a Registro Rápido."
        case .alreadyExists:
            actionMessage = "Ese alimento ya está en Registro Rápido."
        case .maxReached:
            actionMessage = "Registro Rápido admite máximo 8 alimentos."
        case .error(let message):
            actionMessage = message
        }
    }
}

private struct WeeklyFoodLogCalendarView: View {
    let weekStart: Date
    let selectedDate: Date
    let onSelectDate: (Date) -> Void
    let onMoveWeek: (Int) -> Void
    private let calendar = Calendar.current

    private var weekDates: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    onMoveWeek(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(weekTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    onMoveWeek(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                ForEach(weekDates, id: \.self) { date in
                    let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                    Button {
                        onSelectDate(date)
                    } label: {
                        VStack(spacing: 6) {
                            Text(shortDay(for: date))
                                .font(.caption2.weight(.semibold))
                            Text("\(calendar.component(.day, from: date))")
                                .font(.subheadline.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(isSelected ? .white : .primary)
                        .background(isSelected ? Color.accentColor : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var weekTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.dateFormat = "d MMM"
        guard let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
            return formatter.string(from: weekStart)
        }
        return "\(formatter.string(from: weekStart)) - \(formatter.string(from: weekEnd))"
    }

    private func shortDay(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date).uppercased()
    }
}

#Preview {
    let persistence = PersistenceController(inMemory: true)
    let stores = CoreDataStores(controller: persistence)
    return FoodLogView(viewModel: FoodLogViewModel(foodStore: stores))
}
