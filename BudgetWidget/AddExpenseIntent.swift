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
    @MainActor
    func perform() async throws -> some IntentResult {
        guard amount > 0 else {
            return .result(dialog: IntentDialog("Amount must be greater than zero."))
        }

        let container = WidgetModelContainer.shared
        let context = ModelContext(container)
        let transaction = Transaction(
            title: expenseTitle,
            amount: amount,
            category: category,
            date: .now,
            notes: note
        )
        context.insert(transaction)
        try context.save()
        resetWidgetAmount()
        CrossProcessNotifier.signalDataChange()
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: IntentDialog("Saved"))
    }

    private func resetWidgetAmount() {
        BudgetWidgetAmountStore.defaults.set(0, forKey: BudgetWidgetAmountStore.key)
    }
}

// Intent used by widget controls to modify the quick add amount directly from the widget surface
struct AdjustQuickAmountIntent: AppIntent {
    static var title: LocalizedStringResource = "Adjust Quick Amount"
    static var description = IntentDescription("Increase or decrease the amount used by the quick add expense widget.")

    @Parameter(title: "Delta", default: 0)
    var delta: Double

    init(delta: Double) {
        self.delta = delta
    }

    init() {
        self.delta = 0
    }

    func perform() async throws -> some IntentResult {
        let updated = updateAmount()

        CrossProcessNotifier.signalDataChange()
        WidgetCenter.shared.reloadAllTimelines()
        return .result(value: updated)
    }

    private func updateAmount() -> Double {
        let defaults = BudgetWidgetAmountStore.defaults
        let hasExistingAmount = defaults.object(forKey: BudgetWidgetAmountStore.key) != nil
        let current = hasExistingAmount
            ? defaults.double(forKey: BudgetWidgetAmountStore.key)
            : BudgetWidgetAmountStore.defaultAmount
        let updated = max(0, current + delta)
        defaults.set(updated, forKey: BudgetWidgetAmountStore.key)
        return updated
    }
}

// Intent used by widget controls to clear the quick add amount
struct ClearQuickAmountIntent: AppIntent {
    static var title: LocalizedStringResource = "Clear Quick Amount"
    static var description = IntentDescription("Resets the quick add expense amount to zero.")

    init() { }

    func perform() async throws -> some IntentResult {
        // Set the stored amount to 0 in UserDefaults.
        clearAmount()

        // Notify the main app and reload widgets.
        CrossProcessNotifier.signalDataChange()
        WidgetCenter.shared.reloadAllTimelines()
        
        return .result()
    }

    private func clearAmount() {
        BudgetWidgetAmountStore.defaults.set(0.0, forKey: BudgetWidgetAmountStore.key)
    }
}


// Factory for a SwiftData container that can be shared with the widget extension
enum WidgetModelContainer {
    static let shared: ModelContainer = {
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
            do {
                return try ModelContainer(for: schema, configurations: [fallbackConfiguration])
            } catch {
                fatalError("Failed to initialize ModelContainer: \(error)")
            }
        }
    }()
}
