import SwiftUI

struct WatchDashboardView: View {
    @StateObject var viewModel: WatchDashboardViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingSettings = false
    private let minuteTicker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    topSummarySection
                    quickAddSection
                    todayMealsSection
                    metaSection
                    statusSection
                }
                .padding(.horizontal, 10)
            }
            .navigationTitle("ComeSano")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                EmbeddedWatchSettingsView()
            }
            .task {
                await viewModel.requestAuthorizationAndRefresh()
            }
            .onReceive(WatchConnector.shared.$dashboardState) { _ in
                _ = viewModel.applyRemoteStateIfAvailable()
            }
            .onReceive(minuteTicker) { now in
                viewModel.refreshSuggestedMeals(referenceDate: now)
            }
            .onChange(of: scenePhase) { _, newValue in
                guard newValue == .active else { return }
                Task { await viewModel.refresh() }
            }
        }
    }
}

private extension WatchDashboardView {
    var topSummarySection: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                calorieRingSection
                macroRingsOnly
            }

            macroLegendRow
        }
        .padding(.top, 5)
    }

    var calorieRingSection: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .stroke(lineWidth: 11)
                    .opacity(0.2)
                    .foregroundStyle(.green)

                Circle()
                    .trim(from: 0, to: viewModel.ringProgress)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [.green, .mint]),
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(lineWidth: 11, lineCap: .round)
                    )
                    .rotationEffect(.degrees(270))
                    .animation(.easeInOut(duration: 1), value: viewModel.ringProgress)

                VStack(spacing: 0) {
                    Text("\(Int(viewModel.consumed.rounded()))")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("kcal")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 96, height: 96)

            Color.clear
                .frame(height: 24)
        }
    }

    var quickAddSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Registro Rápido")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.gray)

            HStack(spacing: 10) {
                WatchQuickAddButton(icon: "cup.and.saucer.fill", color: .brown, label: "Café") {
                    Task { await viewModel.registerCoffee() }
                }

                WatchQuickAddButton(icon: "drop.fill", color: .cyan, label: "Agua") {
                    Task { await viewModel.registerWater() }
                }
            }

            if !viewModel.quickAddFavorites.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Frecuentes")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    ForEach(viewModel.quickAddFavorites.prefix(4)) { favorite in
                        favoriteRow(favorite)
                    }
                }
            }
        }
        .padding(.horizontal, 5)
    }

    var todayMealsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hoy")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.gray)

            if viewModel.todayMeals.isEmpty {
                Text("Sin sugerencias por ahora")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.todayMeals) { meal in
                    todayMealRow(meal)
                }
            }
        }
        .padding(.horizontal, 5)
    }

    var metaSection: some View {
        VStack(spacing: 1) {
            Text("Meta \(Int(viewModel.goal.rounded())) kcal")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Quemadas \(Int(viewModel.totalBurned.rounded())) kcal")
                .font(.caption2)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    var statusSection: some View {
        if let message = viewModel.statusMessage {
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    func favoriteRow(_ favorite: WatchDashboardViewModel.QuickAddFavorite) -> some View {
        Button {
            Task { await viewModel.registerFavorite(favorite) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.mint)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(favorite.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text("\(Int(favorite.calories.rounded())) kcal")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    func todayMealRow(_ meal: WatchDashboardViewModel.TodayMeal) -> some View {
        Button {
            Task { await viewModel.registerTodayMeal(meal) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "fork.knife.circle.fill")
                    .foregroundStyle(.orange)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(meal.label) · \(meal.scheduledTimeText)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(meal.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(2)
                    Text("\(Int(meal.calories.rounded())) kcal")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    var macroRingsOnly: some View {
        ZStack {
            macroRing(progress: viewModel.fiberProgress, diameter: 86, lineWidth: 8, color: .green)
            macroRing(progress: viewModel.fatProgress, diameter: 68, lineWidth: 8, color: .pink)
            macroRing(progress: viewModel.carbsProgress, diameter: 50, lineWidth: 8, color: .orange)
            macroRing(progress: viewModel.proteinProgress, diameter: 32, lineWidth: 8, color: .blue)
        }
        .frame(width: 90, height: 90)
    }

    var macroLegendRow: some View {
        HStack(spacing: 10) {
            macroLegend(label: "P", actual: viewModel.proteinActual, target: viewModel.proteinTarget, color: .blue)
            macroLegend(label: "C", actual: viewModel.carbsActual, target: viewModel.carbsTarget, color: .orange)
            macroLegend(label: "G", actual: viewModel.fatActual, target: viewModel.fatTarget, color: .pink)
            macroLegend(label: "F", actual: viewModel.fiberActual, target: viewModel.fiberTarget, color: .green)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
    }

    func macroRing(progress: Double, diameter: CGFloat, lineWidth: CGFloat, color: Color) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }

    func macroLegend(label: String, actual: Double, target: Double, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
            Text("\(Int(actual.rounded()))/\(Int(target.rounded()))")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct EmbeddedWatchSettingsView: View {
    private var appVersionDescription: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
        return "Versión \(version) (\(build))"
    }

    var body: some View {
        List {
            Section("App") {
                HStack {
                    Text("ComeSano")
                    Spacer()
                    Text(appVersionDescription)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Ajustes")
    }
}

struct WatchQuickAddButton: View {
    let icon: String
    let color: Color
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 50, height: 50)

                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(color)
                }

                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    WatchDashboardView(viewModel: WatchDashboardViewModel())
}
