import Foundation
import SwiftData

@Model
final class BudgetCategory: Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    @Relationship(inverse: \BudgetSettings.categories) var settings: BudgetSettings?

    init(id: UUID = UUID(), name: String = "") {
        self.id = id
        self.name = name
    }

    static func == (lhs: BudgetCategory, rhs: BudgetCategory) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@Model
final class BudgetSettings {
    var monthlyBudget: Double = 2000
    var quickAddAmount: Double = 20
    var lastSyncedAt: Date = .now
    @Relationship(deleteRule: .cascade, inverse: \BudgetCategory.settings) var categories: [BudgetCategory]? = []

    init(
        monthlyBudget: Double = 2000,
        quickAddAmount: Double = 20,
        lastSyncedAt: Date = .now,
        categories: [BudgetCategory]? = []
    ) {
        self.monthlyBudget = monthlyBudget
        self.quickAddAmount = quickAddAmount
        self.lastSyncedAt = lastSyncedAt
        self.categories = categories
    }
}

extension BudgetSettings {
    static let defaultCategories = [
        "Food",
        "Transport",
        "Entertainment",
        "Bills",
        "Shopping",
        "Other"
    ]

    static func bootstrap(in context: ModelContext) -> BudgetSettings {
        if let existing = try? context.fetch(FetchDescriptor<BudgetSettings>()).first {
            return existing
        }

        let categories = defaultCategories.map { BudgetCategory(name: $0) }
        let settings = BudgetSettings(categories: categories)
        categories.forEach {
            $0.settings = settings
            context.insert($0)
        }
        context.insert(settings)
        return settings
    }
}
