import Foundation
import SwiftData

@Model
final class BudgetCategory: Identifiable, Hashable {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var name: String

    init(id: UUID = UUID(), name: String) {
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
    var monthlyBudget: Double
    var quickAddAmount: Double
    var lastSyncedAt: Date
    @Relationship(deleteRule: .cascade) var categories: [BudgetCategory]

    init(monthlyBudget: Double = 2000, quickAddAmount: Double = 20, lastSyncedAt: Date = .now, categories: [BudgetCategory] = []) {
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
        categories.forEach { context.insert($0) }
        context.insert(settings)
        return settings
    }
}
