//
//  Transaction.swift
//  SimpleBudget
//
//  Created by Dionicy Tarantino on 12/2/25.
//

import Foundation
import SwiftData

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

    var monthIdentifier: String {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

}
