import SwiftData

enum BudgetModelSchema {
    static let schema = Schema([
        Transaction.self,
        BudgetSettings.self,
        BudgetCategory.self
    ])
}
