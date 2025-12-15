//
//  SimpleBudgetApp.swift
//  SimpleBudget
//
//  Created by Dionicy Tarantino on 12/2/25.
//

import SwiftUI
import SwiftData

// Application entry point configuring shared data container and launching the root view
@main
struct SimpleBudgetApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(ModelContainerLoader.shared)
        }
    }
}
