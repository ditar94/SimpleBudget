import Foundation
import SwiftData
import SwiftUI

/// Creates the shared `ModelContainer` for instant app launch with background CloudKit sync.
///
/// Strategy:
/// - First launch: Uses local-only storage (instant), warms up CloudKit in background
/// - Subsequent launches: Uses CloudKit directly (fast, schema already validated)
/// - CloudKit sync happens automatically in background once enabled
enum ModelContainerLoader {
    private static let groupIdentifier = AppIdentifiers.appGroup
    private static let cloudKitIdentifier = AppIdentifiers.cloudContainer
    private static let isUITesting = ProcessInfo.processInfo.arguments.contains("UI-Testing")

    /// UserDefaults key to track if CloudKit has been warmed up
    private static let cloudKitReadyKey = "cloudkit_schema_initialized"

    /// Check if CloudKit has been previously initialized (schema created)
    private static var isCloudKitReady: Bool {
        get { UserDefaults.standard.bool(forKey: cloudKitReadyKey) }
        set { UserDefaults.standard.set(newValue, forKey: cloudKitReadyKey) }
    }

    /// The shared container - created once and cached
    static let shared: ModelContainer = buildContainer()

    private static func buildContainer() -> ModelContainer {
        let schema = BudgetModelSchema.schema
        let supportsAppGroup = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) != nil
        let storeName = AppIdentifiers.persistentStoreName

        // Ensure required directories exist in app group container
        if supportsAppGroup {
            ensureAppGroupDirectoriesExist()
        }

        // For UI testing, use in-memory store
        if isUITesting {
            return createUITestContainer(schema: schema)
        }

        // If CloudKit was previously initialized, use it directly (should be fast)
        if isCloudKitReady && supportsAppGroup {
            if let container = createCloudKitContainer(schema: schema, storeName: storeName) {
                return container
            }
            // CloudKit failed, reset flag and fall through to local
            isCloudKitReady = false
        }

        // Use local storage for instant launch
        let container = createLocalContainer(schema: schema, storeName: storeName, supportsAppGroup: supportsAppGroup)

        // Warm up CloudKit in background for next launch
        if supportsAppGroup && !isCloudKitReady {
            warmUpCloudKitInBackground(schema: schema, storeName: storeName)
        }

        return container
    }

    // MARK: - Directory Setup

    /// Ensures the required directories exist in the app group container.
    /// CoreData/SwiftData requires the Library/Application Support directory to exist.
    private static func ensureAppGroupDirectoriesExist() {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
            return
        }

        let applicationSupportURL = containerURL.appendingPathComponent("Library/Application Support", isDirectory: true)

        if !FileManager.default.fileExists(atPath: applicationSupportURL.path) {
            try? FileManager.default.createDirectory(at: applicationSupportURL, withIntermediateDirectories: true)
        }
    }

    // MARK: - Container Creation Methods

    private static func createUITestContainer(schema: Schema) -> ModelContainer {
        let config = ModelConfiguration(
            "ui-testing",
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            seedUITestData(in: container)
            return container
        } catch {
            fatalError("Could not create UI test ModelContainer: \(error)")
        }
    }

    private static func createCloudKitContainer(schema: Schema, storeName: String) -> ModelContainer? {
        let config = ModelConfiguration(
            storeName,
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .identifier(groupIdentifier),
            cloudKitDatabase: .private(cloudKitIdentifier)
        )
        return try? ModelContainer(for: schema, configurations: [config])
    }

    private static func createLocalContainer(schema: Schema, storeName: String, supportsAppGroup: Bool) -> ModelContainer {
        // Try with app group first (for widget sharing)
        if supportsAppGroup {
            let localGroupConfig = ModelConfiguration(
                storeName,
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true,
                groupContainer: .identifier(groupIdentifier),
                cloudKitDatabase: .none
            )
            if let container = try? ModelContainer(for: schema, configurations: [localGroupConfig]) {
                return container
            }
        }

        // Fallback: completely local store
        let localConfig = ModelConfiguration(
            storeName,
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [localConfig])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    // MARK: - Background CloudKit Warmup

    /// Initializes CloudKit container in background so next launch is fast.
    /// This triggers schema creation/validation without blocking the UI.
    private static func warmUpCloudKitInBackground(schema: Schema, storeName: String) {
        DispatchQueue.global(qos: .utility).async {
            let config = ModelConfiguration(
                storeName,
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true,
                groupContainer: .identifier(groupIdentifier),
                cloudKitDatabase: .private(cloudKitIdentifier)
            )

            // This may take time on first run - that's fine, we're in background
            if let _ = try? ModelContainer(for: schema, configurations: [config]) {
                // CloudKit schema is now validated and ready
                DispatchQueue.main.async {
                    isCloudKitReady = true
                }
            }
        }
    }

    // MARK: - Test Data Seeding

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
