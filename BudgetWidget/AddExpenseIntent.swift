import AppIntents
import SwiftData
import WidgetKit
import Foundation

// App Intent enabling quick expense creation from widgets and shortcuts
struct AddExpenseIntent: AppIntent, WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Quick Add Expense"
    static var description = IntentDescription("Add an expense from your lock screen or Home Screen widget.")

    static var parameterSummary: some ParameterSummary {
        Summary("Add \\(\\.$amount) in \\(\\.$category)")
    }

    @Parameter(title: "Amount", default: 20)
    var amount: Double

    @Parameter(title: "Title", default: "Quick expense")
    var title: String

    @Parameter(title: "Category", default: "General")
    var category: String

    @Parameter(title: "Note", default: "")
    var note: String

    // Persists a new transaction into the shared model container
    func perform() async throws -> some IntentResult {
        let container = try WidgetModelContainer.shared
        let context = ModelContext(container)
        let transaction = Transaction(
            title: title,
            amount: abs(amount),
            category: category,
            date: .now,
            notes: note
        )
        context.insert(transaction)
        try context.save()
        WidgetCenter.shared.reloadAllTimelines()
        return .result(value: "Saved")
    }
}

// Factory for a SwiftData container that can be shared with the widget extension
enum WidgetModelContainer {
    static var shared: ModelContainer {
        get throws {
            let groupIdentifier = "group.com.example.SimpleBudget"
            let cloudKitIdentifier = "iCloud.com.example.SimpleBudget"
            let schema = Schema([
                Transaction.self,
                BudgetSettings.self,
                BudgetCategory.self
            ])
            let supportsAppGroup = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) != nil
            let primaryConfiguration: ModelConfiguration = {
                if supportsAppGroup {
                    return ModelConfiguration(
                        "widget-config",
                        schema: schema,
                        isStoredInMemoryOnly: false,
                        allowsSave: true,
                        groupContainer: .identifier(groupIdentifier),
                        cloudKitDatabase: .private(cloudKitIdentifier)
                    )
                } else {
                    return ModelConfiguration(
                        "widget-local-config",
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
                let fallbackConfiguration = ModelConfiguration(
                    "widget-local-fallback",
                    schema: schema,
                    isStoredInMemoryOnly: false,
                    allowsSave: true
                )
                return try ModelContainer(for: schema, configurations: [fallbackConfiguration])
            }
        }
    }
}
