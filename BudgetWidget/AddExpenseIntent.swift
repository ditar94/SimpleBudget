import AppIntents
import SwiftData
import WidgetKit

struct AddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Add Expense"
    static var description = IntentDescription("Add an expense from your lock screen or Home Screen widget.")

    @Parameter(title: "Amount", default: 20)
    var amount: Double

    @Parameter(title: "Title", default: "Quick expense")
    var title: String

    @Parameter(title: "Category", default: "General")
    var category: String

    @Parameter(title: "Type", default: .expense)
    var type: TransactionType

    @Parameter(title: "Note", default: "")
    var note: String

    func perform() async throws -> some IntentResult {
        let container = try WidgetModelContainer.shared
        let context = ModelContext(container)
        let transaction = Transaction(
            title: title,
            amount: abs(amount),
            category: category,
            date: .now,
            notes: note,
            type: type
        )
        context.insert(transaction)
        try context.save()
        WidgetCenter.shared.reloadAllTimelines()
        return .result(value: "Saved")
    }
}

enum WidgetModelContainer {
    static var shared: ModelContainer {
        get throws {
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
            return try ModelContainer(for: schema, configurations: [configuration])
        }
    }
}
