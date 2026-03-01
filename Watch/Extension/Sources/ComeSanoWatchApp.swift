import SwiftUI
import ComeSanoHealthKit

@main
struct ComeSanoWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchDashboardView(viewModel: WatchDashboardViewModel())
        }
    }
}
