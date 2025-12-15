import Foundation
import SwiftData

/// Factory for a SwiftData container shared between the watch app and other targets.
/// Uses the same app group and CloudKit configuration as the iOS app and widget.
enum WatchModelContainer {
    static let shared: ModelContainer = {
        let groupIdentifier = AppIdentifiers.appGroup
        let cloudKitIdentifier = AppIdentifiers.cloudContainer
        let storeName = AppIdentifiers.persistentStoreName
        let schema = BudgetModelSchema.schema

        // Check if app group container is available
        let supportsAppGroup = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) != nil

        // Ensure required directories exist
        if supportsAppGroup {
            ensureAppGroupDirectoriesExist(groupIdentifier: groupIdentifier)
        }

        let primaryConfiguration: ModelConfiguration = {
            if supportsAppGroup {
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
            return try ModelContainer(for: schema, configurations: [primaryConfiguration])
        } catch {
            // Fallback to local-only storage
            let fallbackConfiguration = ModelConfiguration(
                storeName,
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true
            )
            do {
                return try ModelContainer(for: schema, configurations: [fallbackConfiguration])
            } catch {
                fatalError("Failed to initialize ModelContainer: \(error)")
            }
        }
    }()

    private static func ensureAppGroupDirectoriesExist(groupIdentifier: String) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else { return }

        let applicationSupportURL = containerURL.appendingPathComponent(
            "Library/Application Support",
            isDirectory: true
        )

        if !FileManager.default.fileExists(atPath: applicationSupportURL.path) {
            try? FileManager.default.createDirectory(
                at: applicationSupportURL,
                withIntermediateDirectories: true
            )
        }
    }
}
