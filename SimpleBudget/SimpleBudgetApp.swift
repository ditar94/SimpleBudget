//
//  SimpleBudgetApp.swift
//  SimpleBudget
//
//  Created by Dionicy Tarantino on 12/2/25.
//

import SwiftUI
import SwiftData
import Foundation

@main
struct SimpleBudgetApp: App {
    private static let groupIdentifier = "group.com.example.SimpleBudget"
    private static let cloudKitIdentifier = "iCloud.com.example.SimpleBudget"

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Transaction.self,
            BudgetSettings.self,
            BudgetCategory.self
        ])
        let supportsAppGroup = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) != nil

        let primaryConfiguration = ModelConfiguration(
            supportsAppGroup ? "shared-config" : "local-config",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: supportsAppGroup ? .identifier(groupIdentifier) : nil,
            cloudKitDatabase: .private(cloudKitIdentifier)
        )

        do {
            return try ModelContainer(for: schema, configurations: [primaryConfiguration])
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
