import SwiftUI

struct WatchSettingsView: View {
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

#Preview {
    WatchSettingsView()
}
