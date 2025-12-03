//
//  SimpleBudgetApp.swift
//  SimpleBudget
//
//  Created by Dionicy Tarantino on 12/2/25.
//

import SwiftUI
import SwiftData

@main
struct SimpleBudgetApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Transaction.self,
            BudgetSettings.self,
            BudgetCategory.self
        ])
        let configuration = ModelConfiguration(
            nil,
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .identifier("group.com.example.SimpleBudget"),
            cloudKitDatabase: .private("iCloud.com.example.SimpleBudget")
        )

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
