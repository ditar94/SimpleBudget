//
//  SimpleBudgetApp.swift
//  SimpleBudget
//
//  Created by Dionicy Tarantino on 12/2/25.
//

import SwiftUI
import SwiftData
import Foundation

// Application entry point configuring shared data container and launching the root view
@main
struct SimpleBudgetApp: App {
    private static let groupIdentifier = "group.com.example.SimpleBudget"
    private static let cloudKitIdentifier = "iCloud.com.example.SimpleBudget"
    private static let isUITesting = ProcessInfo.processInfo.arguments.contains("UI-Testing")

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Transaction.self,
            BudgetSettings.self,
            BudgetCategory.self
        ])
        let supportsAppGroup = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) != nil
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
                    "shared-config",
                    schema: schema,
                    isStoredInMemoryOnly: false,
                    allowsSave: true,
                    groupContainer: .identifier(groupIdentifier),
                    cloudKitDatabase: .private(cloudKitIdentifier)
                )
            } else {
                return ModelConfiguration(
                    "local-config",
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
                "local-fallback",
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
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}

private extension SimpleBudgetApp {
    static func seedUITestData(in container: ModelContainer) {
        let context = ModelContext(container)
        let settings = BudgetSettings.bootstrap(in: context)

        if let budgetOverride = ProcessInfo.processInfo.environment["UITEST_BUDGET"],
           let budgetValue = Double(budgetOverride) {
            settings.monthlyBudget = budgetValue
        }

        if ProcessInfo.processInfo.arguments.contains("UITestSeedRefund") {
            let refund = Transaction(
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
