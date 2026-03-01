import SwiftUI
import ComeSanoCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct DashboardView: View {
    public enum QuickAddKind: String, CaseIterable, Identifiable {
        case coffee
        case waterGlass
        case apple

        public var id: String { rawValue }
    }

    @StateObject private var viewModel: DashboardViewModel
    @State private var selectedDate: Date = .now
    private let onQuickAdd: (QuickAddKind) -> Void

    public init(viewModel: DashboardViewModel, onQuickAdd: @escaping (QuickAddKind) -> Void = { _ in }) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onQuickAdd = onQuickAdd
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
                            onMoveSelection: moveSelection
                        )

                        Text(selectedDateText(for: selectedSnapshot.date))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        CalorieRingCard(
                            consumed: selectedSnapshot.consumedKcal,
                            goal: selectedSnapshot.targetKcal,
                            burned: selectedSnapshot.totalBurnedKcal
                        )

                        QuickAddSection(onQuickAdd: onQuickAdd)

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
            .navigationTitle("Mi Progreso")
            .background(Color.dashboardGroupedBackground)
            .task { await viewModel.refresh() }
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

    private func moveSelection(_ direction: Int) {
        guard let currentIndex = currentSelectionIndex else { return }
        let targetIndex = max(0, min(viewModel.weekSnapshots.count - 1, currentIndex + direction))
        selectedDate = viewModel.weekSnapshots[targetIndex].date
    }

    private var currentSelectionIndex: Int? {
        let calendar = Calendar.current
        return viewModel.weekSnapshots.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: selectedDate) })
    }

    private func selectedDateText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: date).capitalized
    }
}

private struct QuickAddSection: View {
    let onQuickAdd: (DashboardView.QuickAddKind) -> Void

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
                        .foregroundStyle(.gray)
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
    let onMoveSelection: (Int) -> Void

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    onMoveSelection(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                }
                .disabled(isFirstSelected)

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
                    onMoveSelection(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                }
                .disabled(isLastSelected)
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

    private var selectedIndex: Int? {
        snapshots.firstIndex { calendar.isDate($0.date, inSameDayAs: selectedDate) }
    }

    private var isFirstSelected: Bool {
        selectedIndex == 0
    }

    private var isLastSelected: Bool {
        guard let selectedIndex else { return false }
        return selectedIndex == snapshots.count - 1
    }
}

struct CalorieRingCard: View {
    var consumed: Double
    var goal: Double
    var burned: Double

    var progress: CGFloat {
        let safeGoal = max(goal, 1)
        return CGFloat(max(0, min(consumed / safeGoal, 1)))
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
                        .foregroundStyle(.green)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(style: StrokeStyle(lineWidth: 15, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(.green)
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
                        Text("Meta")
                            .font(.subheadline)
                            .foregroundStyle(.gray)
                        Text("\(Int(goal.rounded())) kcal")
                            .font(.headline)
                    }
                    VStack(alignment: .leading) {
                        Text("Quemadas")
                            .font(.subheadline)
                            .foregroundStyle(.gray)
                        Text("\(Int(burned.rounded())) kcal")
                            .font(.headline)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
            }
        }
        .padding()
        .background(Color.dashboardCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
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
