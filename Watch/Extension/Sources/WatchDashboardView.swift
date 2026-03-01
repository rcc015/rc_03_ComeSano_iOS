import SwiftUI

struct WatchDashboardView: View {
    @StateObject var viewModel: WatchDashboardViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                ZStack {
                    Circle()
                        .stroke(lineWidth: 12)
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
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .rotationEffect(.degrees(270))
                        .animation(.easeInOut(duration: 1), value: viewModel.ringProgress)

                    VStack(spacing: 0) {
                        Text("\(Int(viewModel.consumed.rounded()))")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("kcal")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 110, height: 110)
                .padding(.top, 5)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Registro Rápido")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.gray)

                    HStack(spacing: 10) {
                        WatchQuickAddButton(
                            icon: "cup.and.saucer.fill",
                            color: .brown,
                            label: "Café"
                        ) {
                            Task { await viewModel.registerCoffee() }
                        }

                        WatchQuickAddButton(
                            icon: "drop.fill",
                            color: .cyan,
                            label: "Agua"
                        ) {
                            Task { await viewModel.registerWater() }
                        }
                    }
                }
                .padding(.horizontal, 5)

                VStack(spacing: 1) {
                    Text("Meta \(Int(viewModel.goal.rounded())) kcal")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Quemadas \(Int(viewModel.totalBurned.rounded())) kcal")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                if let message = viewModel.statusMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 10)
        }
        .task {
            await viewModel.requestAuthorizationAndRefresh()
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task { await viewModel.refresh() }
        }
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
