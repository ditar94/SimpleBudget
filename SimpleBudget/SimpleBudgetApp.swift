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
        let configuration: ModelConfiguration
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) != nil {
            configuration = ModelConfiguration(
                "shared-config",
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true,
                groupContainer: .identifier(groupIdentifier),
                cloudKitDatabase: .private(cloudKitIdentifier)
            )
        } else {
            configuration = ModelConfiguration(
                "local-config",
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true,
                cloudKitDatabase: .private(cloudKitIdentifier)
            )
        }

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
