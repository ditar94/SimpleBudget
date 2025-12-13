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
    @StateObject private var containerLoader = ModelContainerLoader()

    var body: some Scene {
        WindowGroup {
            if let container = containerLoader.container {
                ContentView()
                    .modelContainer(container)
            } else {
                ModelContainerLoadingView()
            }
        }
    }
}
