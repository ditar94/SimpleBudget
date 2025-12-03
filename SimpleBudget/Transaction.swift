//
//  Transaction.swift
//  SimpleBudget
//
//  Created by Dionicy Tarantino on 12/2/25.
//

import Foundation
import SwiftData
import AppIntents

enum TransactionType: String, Codable, CaseIterable {
    case expense
    case income

    var title: String {
        switch self {
        case .expense:
            return "Expense"
        case .income:
            return "Income"
        }
    }

    var symbolName: String {
        switch self {
        case .expense:
            return "arrow.up.right.circle"
        case .income:
            return "arrow.down.left.circle"
        }
    }

    var tint: String {
        switch self {
        case .expense:
            return "systemRed"
        case .income:
            return "systemGreen"
        }
    }
}

extension TransactionType: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Transaction Type"
    }

    static var caseDisplayRepresentations: [TransactionType: DisplayRepresentation] {
        [
            .expense: "Expense",
            .income: "Income"
        ]
    }
}

@Model
final class Transaction {
    var title: String
    var amount: Double
    var category: String
    var date: Date
    var notes: String
    var type: TransactionType

    init(title: String, amount: Double, category: String, date: Date, notes: String = "", type: TransactionType) {
        self.title = title
        self.amount = amount
        self.category = category
        self.date = date
        self.notes = notes
        self.type = type
    }

    var monthIdentifier: String {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    var signedAmount: Double {
        type == .income ? amount : -amount
    }
}
