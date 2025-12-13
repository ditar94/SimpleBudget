import Foundation
import SwiftData
import SwiftUI

/// Loads the shared `ModelContainer` on a background task and exposes it for injection
/// once ready. Keeps the configuration consistent with the rest of the app while
/// providing a fallback path when entitlements or CloudKit are unavailable.
@MainActor
final class ModelContainerLoader: ObservableObject {
    @Published private(set) var container: ModelContainer?

    private static let groupIdentifier = AppIdentifiers.appGroup
    private static let cloudKitIdentifier = AppIdentifiers.cloudContainer
    private static let isUITesting = ProcessInfo.processInfo.arguments.contains("UI-Testing")

    init() {
        Task(priority: .userInitiated) {
            let container = await Self.buildContainer()
            await MainActor.run { [weak self] in
                self?.container = container
            }
        }
    }

    private static func buildContainer() async -> ModelContainer {
        let schema = BudgetModelSchema.schema
        let supportsAppGroup = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) != nil
        let storeName = AppIdentifiers.persistentStoreName

        let primaryConfiguration: ModelConfiguration = {
            if isUITesting {
                return ModelConfiguration(
                    "ui-testing",
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    allowsSave: true
                )
            } else if supportsAppGroup {
                return ModelConfiguration(
                    storeName,
                    schema: schema,
                    isStoredInMemoryOnly: false,
                    allowsSave: true,
                    groupContainer: .identifier(groupIdentifier),
                    cloudKitDatabase: .private(cloudKitIdentifier)
                )
            } else {
                return ModelConfiguration(
                    storeName,
                    schema: schema,
                    isStoredInMemoryOnly: false,
                    allowsSave: true,
                    cloudKitDatabase: .private(cloudKitIdentifier)
                )
            }
        }()

        do {
            let container = try ModelContainer(for: schema, configurations: [primaryConfiguration])
            if isUITesting {
                seedUITestData(in: container)
            }
            return container
        } catch {
            // Fallback to a local-only store to keep the app running when entitlements
            // or CloudKit availability cause initialization to fail (e.g., Simulator).
            let fallbackConfiguration = ModelConfiguration(
                storeName,
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true
            )
            do {
                return try ModelContainer(for: schema, configurations: [fallbackConfiguration])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }

    private static func seedUITestData(in container: ModelContainer) {
        let context = ModelContext(container)
        let settings = BudgetSettings.bootstrap(in: context)

        if let budgetOverride = ProcessInfo.processInfo.environment["UITEST_BUDGET"],
           let budgetValue = Double(budgetOverride) {
            settings.monthlyBudget = budgetValue
        }

        if ProcessInfo.processInfo.arguments.contains("UITestSeedRefund") {
            let refund = Transaction(
                title: "Refund",
                amount: -200,
                category: "Refund",
                date: .now,
                notes: "UITest Seed"
            )
            context.insert(refund)
        }

        try? context.save()
    }
}

/// Lightweight loading UI shown while the shared model container initializes.
struct ModelContainerLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading your budget data…")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
