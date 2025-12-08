import AppIntents
import SwiftData
import WidgetKit
import Foundation

// App Intent enabling quick expense creation from widgets and shortcuts
struct AddExpenseIntent: AppIntent, WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Quick Add Expense"
    static var description = IntentDescription("Add an expense from your lock screen or Home Screen widget.")

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$amount) in \(\.$category)")
    }

    @Parameter(title: "Amount", default: 20)
    var amount: Double

    @Parameter(title: "Title", default: "Quick expense")
    var expenseTitle: String

    @Parameter(title: "Category", default: "General")
    var category: String

    @Parameter(title: "Note", default: "")
    var note: String

    // Persists a new transaction into the shared model container
    func perform() async throws -> some IntentResult {
        let container = try WidgetModelContainer.shared
        let context = ModelContext(container)
        let transaction = Transaction(
            title: expenseTitle,
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

// Intent used by widget controls to modify the quick add amount directly from the widget surface
struct AdjustQuickAmountIntent: AppIntent {
    static var title: LocalizedStringResource = "Adjust Quick Amount"
    static var description = IntentDescription("Increase or decrease the amount used by the quick add expense widget.")

    @Parameter(title: "Delta")
    var delta: Double

    init(delta: IntentParameter<Double>) {
        _delta = delta
    }

    func perform() async throws -> some IntentResult {
        let defaults = BudgetWidgetAmountStore.defaults
        let hasExistingAmount = defaults.object(forKey: BudgetWidgetAmountStore.key) != nil
        let current = hasExistingAmount
            ? defaults.double(forKey: BudgetWidgetAmountStore.key)
            : BudgetWidgetAmountStore.defaultAmount
        let updated = max(0, current + delta)
        defaults.set(updated, forKey: BudgetWidgetAmountStore.key)

        WidgetCenter.shared.reloadAllTimelines()
        return .result(value: updated)
    }
}

enum BudgetWidgetAmountStore {
    static let key = "budget_widget_quick_amount"
    static let defaultAmount: Double = 20
    static let defaults: UserDefaults = {
        UserDefaults(suiteName: AppIdentifiers.appGroup) ?? .standard
    }()
}

// Factory for a SwiftData container that can be shared with the widget extension
enum WidgetModelContainer {
    static var shared: ModelContainer {
        get throws {
            let groupIdentifier = AppIdentifiers.appGroup
            let cloudKitIdentifier = AppIdentifiers.cloudContainer
            let storeName = AppIdentifiers.persistentStoreName
            let schema = BudgetModelSchema.schema
            let supportsAppGroup = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) != nil
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
                let fallbackConfiguration = ModelConfiguration(
                    storeName,
                    schema: schema,
                    isStoredInMemoryOnly: false,
                    allowsSave: true
                )
                return try ModelContainer(for: schema, configurations: [fallbackConfiguration])
            }
        }
    }
}
