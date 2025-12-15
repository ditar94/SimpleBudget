//
//  Transaction.swift
//  SimpleBudget
//
//  Created by Dionicy Tarantino on 12/2/25.
//

import Foundation
import SwiftData

// Persistent model capturing a single spending transaction
// Note: When iOS 18 becomes minimum target, add #Index<Transaction>([\.date], [\.category])
// for improved query performance on date and category filtering
@Model
final class Transaction {
    var title: String = ""
    var amount: Double = 0
    var category: String = ""
    var date: Date = Date()
    var notes: String = ""

    init(
        title: String = "",
        amount: Double = 0,
        category: String = "",
        date: Date = Date(),
        notes: String = ""
    ) {
        self.title = title
        self.amount = amount
        self.category = category
        self.date = date
        self.notes = notes
    }
}

// MARK: - Display Helpers (cached string operations for efficiency)
extension Transaction {
    /// Returns the display title, using category as fallback if title is empty
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? category : title
    }

    /// Whether the title has meaningful content
    var hasTitle: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether notes have meaningful content
    var hasNotes: Bool {
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
