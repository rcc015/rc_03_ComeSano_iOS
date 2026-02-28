import SwiftUI
import ComeSanoCore

public struct DashboardView: View {
    @StateObject private var viewModel: DashboardViewModel

    public init(viewModel: DashboardViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            Group {
                if let error = viewModel.errorMessage {
                    ContentUnavailableView("Error de lectura", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if let today = viewModel.today, let weekly = viewModel.weekly {
                    List {
                        Section("Hoy") {
                            metricRow("Consumidas", value: today.consumedKcal)
                            metricRow("Gastadas", value: today.totalBurnedKcal)
                            metricRow("Balance neto", value: today.netKcal)
                            metricRow("Meta diaria", value: today.targetKcal)
                        }

                        Section("Semana") {
                            metricRow("Promedio neto", value: weekly.averageNetKcal)
                            metricRow("Desviación de meta", value: weekly.averageTargetDeltaKcal)
                            HStack {
                                Text("Adherencia")
                                Spacer()
                                Text("\(Int(weekly.adherenceScore))%")
                            }
                        }
                    }
                } else {
                    ProgressView("Cargando datos")
                }
            }
            .navigationTitle("ComeSano")
            .task { await viewModel.refresh() }
        }
    }

    private func metricRow(_ title: String, value: Double) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(Int(value.rounded())) kcal")
                .foregroundStyle(.secondary)
        }
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
