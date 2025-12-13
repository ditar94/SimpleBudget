import Foundation

/// Persistence helpers for storing the quick-add amount shared between the
/// main app and the widget extension.
enum BudgetWidgetAmountStore {
    static let key = "budget_widget_quick_amount"
    static let defaultAmount: Double = 1
    static let defaults: UserDefaults = AppGroupContainer.sharedDefaults
}

