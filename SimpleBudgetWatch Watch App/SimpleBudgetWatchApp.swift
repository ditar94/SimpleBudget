import SwiftUI
import SwiftData

@main
struct SimpleBudgetWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .modelContainer(WatchModelContainer.shared)
        }
    }
}
