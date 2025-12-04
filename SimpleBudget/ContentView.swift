//
//  ContentView.swift
//  SimpleBudget
//
//  Created by Dionicy Tarantino on 12/2/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var settingsCollection: [BudgetSettings]
    @Query(sort: \BudgetCategory.name) private var categoryModels: [BudgetCategory]

    @State private var selectedTab: Tab = .add
    @State private var selectedMonth: Date = .now

    private var settings: BudgetSettings {
        if let settings = settingsCollection.first {
            return settings
        }
        return BudgetSettings.bootstrap(in: modelContext)
    }

    private var categories: [String] {
        let names = categoryModels.map(\.name)
        return names.isEmpty ? BudgetSettings.defaultCategories : names
    }

    private enum Tab: Hashable {
        case add, history, settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            AddExpenseTab(
                transactions: transactions,
                settings: settings,
                categories: categories,
                onAdd: addTransaction
            )
            .tag(Tab.add)
            .tabItem {
                Label("Add", systemImage: "plus")
            }

            MonthlyExpensesTab(
                transactions: transactions,
                monthlyBudget: settings.monthlyBudget,
                selectedMonth: $selectedMonth,
                onDelete: { offsets, list in
                    deleteTransactions(at: offsets, in: list)
                }
            )
            .tag(Tab.history)
            .tabItem {
                Label("Expenses", systemImage: "list.bullet")
            }

            SettingsTab(
                settings: settings,
                categories: categoryModels,
                onAddCategory: addCategory,
                onDeleteCategory: deleteCategory,
                onUpdateBudget: updateBudget
            )
            .tag(Tab.settings)
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .onAppear {
            _ = settings
        }
        .toolbarBackground(.visible, for: .tabBar)
    }

    private func addTransaction(_ draft: TransactionDraft) {
        guard draft.isValid else { return }

        let transaction = Transaction(
            amount: draft.amount,
            category: draft.category,
            date: draft.date,
            notes: draft.note
        )

        modelContext.insert(transaction)
    }

    private func deleteTransactions(at offsets: IndexSet, in list: [Transaction]) {
        offsets.forEach { index in
            modelContext.delete(list[index])
        }
    }

    private func deleteTransactions(offsets: IndexSet) {
        withAnimation {
            deleteTransactions(at: offsets, in: transactions)
        }
    }

    private func addCategory(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !categoryModels.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }

        let category = BudgetCategory(name: trimmed)
        category.settings = settings
        modelContext.insert(category)
        var updated = settings.categories ?? []
        updated.append(category)
        settings.categories = updated
    }

    private func deleteCategory(_ category: BudgetCategory) {
        if var current = settings.categories, let index = current.firstIndex(of: category) {
            current.remove(at: index)
            settings.categories = current
        }
        modelContext.delete(category)
    }

    private func updateBudget(_ newValue: Double) {
        settings.monthlyBudget = max(0, newValue)
    }
}

// MARK: - Add Expense

private struct AddExpenseTab: View {
    let transactions: [Transaction]
    let settings: BudgetSettings
    let categories: [String]
    var onAdd: (TransactionDraft) -> Void

    @State private var draft = TransactionDraft()

    private var currentMonthTotal: Double {
        transactions.filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
    }

    private var remainingBudget: Double {
        max(settings.monthlyBudget - currentMonthTotal, 0)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                BudgetHeaderCard(
                    remainingBudget: remainingBudget,
                    currencyCode: Locale.current.currency?.identifier ?? "USD"
                )

                ExpenseDialCard(
                    remainingBudget: remainingBudget,
                    currencyCode: Locale.current.currency?.identifier ?? "USD",
                    draft: $draft
                )

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Category")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        CategoryChips(categories: categories, selection: $draft.category)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Note")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("Optional note", text: $draft.note, axis: .vertical)
                            .padding(8)
                            .lineLimit(1...3)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
                    }

                    Button(action: {
                        onAdd(draft)
                        draft = TransactionDraft(category: categories.first ?? "General")
                    }) {
                        Text("Add Expense")
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(.white)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(draft.isValid ? Color.blue : Color.gray.opacity(0.5))
                            )
                    }
                    .disabled(!draft.isValid)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("New Expense")
            .onAppear {
                if draft.category.isEmpty {
                    draft.category = categories.first ?? "General"
                }
            }
        }
    }
}

private struct BudgetHeaderCard: View {
    let remainingBudget: Double
    let currencyCode: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Remaining this month")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Text(remainingBudget, format: .currency(code: currencyCode))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Stay on track with mindful spending.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        )
    }
}

private struct ExpenseDialCard: View {
    let remainingBudget: Double
    let currencyCode: String
    @Binding var draft: TransactionDraft

    private var amountBinding: Binding<Double> {
        Binding(
            get: { draft.amount },
            set: { newValue in
                draft.setAmount(newValue)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Set expense amount")
                        .font(.subheadline.weight(.semibold))
                    Text("Drag around the dial to fine-tune your spend.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(Date.now, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            BudgetDial(
                amount: amountBinding,
                remainingBudget: remainingBudget,
                currencyCode: currencyCode
            )
            .frame(height: 180)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct BudgetDial: View {
    @Binding var amount: Double
    let remainingBudget: Double
    let currencyCode: String

    @GestureState private var isDragging = false
    @State private var initialProgress: Double = 0
    @State private var progressDelta: Double = 0
    @State private var previousAngle: Double?

    private var dialRange: Double { max(remainingBudget, 0.01) }
    private var progress: Double { dialRange > 0 ? amount / dialRange : 0 }
    private var normalizedProgress: Double { max(progress, 0) }
    private var primaryTrim: Double { min(normalizedProgress, 1) }
    private var wrappedProgress: Double {
        guard normalizedProgress > 0 else { return 0 }
        let remainder = normalizedProgress.truncatingRemainder(dividingBy: 1)
        return remainder == 0 ? 1 : remainder
    }
    private var overBudget: Bool { remainingBudget > 0 ? amount > remainingBudget : amount > 0 }
    private var remainingAfterSelection: Double { max(remainingBudget - amount, 0) }
    private var overageAmount: Double {
        guard remainingBudget > 0 else { return max(amount, 0) }
        return max(amount - remainingBudget, 0)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let ringWidth: CGFloat = 18
            let knobRadius = size / 2
            let endAngle = Angle(degrees: wrappedProgress * 360)
            let endPoint = CGPoint(
                x: center.x + cos(CGFloat(endAngle.radians)) * knobRadius,
                y: center.y + sin(CGFloat(endAngle.radians)) * knobRadius
            )

            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.1), lineWidth: ringWidth)

                let fillGradient = AngularGradient(
                    colors: [Color.blue.opacity(0.35), .blue],
                    center: .center,
                    startAngle: .degrees(0),
                    endAngle: .degrees(primaryTrim * 360)
                )

                Circle()
                    .trim(from: 0, to: primaryTrim)
                    .stroke(fillGradient, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(0))

                if overBudget {
                    Circle()
                        .trim(from: 0, to: wrappedProgress)
                        .stroke(
                            AngularGradient(
                                colors: [Color.red.opacity(0.65), .red],
                                center: .center,
                                startAngle: .degrees(0),
                                endAngle: .degrees(wrappedProgress * 360)
                            ),
                            style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                        )
                }

                Circle()
                    .fill(overBudget ? Color.red : Color.black)
                    .frame(width: 16, height: 16)
                    .position(endPoint)

                VStack(spacing: 6) {
                    Text(amount, format: .currency(code: currencyCode))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text(
                        overBudget
                            ? "Over by \(overageAmount, format: .currency(code: currencyCode))"
                            : "Remaining \(remainingAfterSelection, format: .currency(code: currencyCode))"
                    )
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDragging) { _, state, _ in
                        state = true
                    }
                    .onChanged { value in
                        updateAmount(from: value.location, in: proxy.size)
                    }
                    .onEnded { _ in
                        resetDragState()
                    }
            )
        }
    }

    private func updateAmount(from location: CGPoint, in size: CGSize) {
        let angle = normalizedAngle(for: location, in: size)

        if previousAngle == nil {
            previousAngle = angle
            initialProgress = amount / dialRange
        }

        if let previousAngle {
            progressDelta += angleDelta(from: previousAngle, to: angle) / 360
        }

        previousAngle = angle

        let newProgress = max(0, initialProgress + progressDelta)
        amount = max(0, newProgress * dialRange)
    }

    private func resetDragState() {
        initialProgress = amount / dialRange
        progressDelta = 0
        previousAngle = nil
    }

    private func normalizedAngle(for location: CGPoint, in size: CGSize) -> Double {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let vector = CGVector(dx: location.x - center.x, dy: location.y - center.y)
        let angle = atan2(vector.dy, vector.dx)
        var degrees = angle * 180 / .pi
        if degrees < 0 { degrees += 360 }
        return degrees
    }

    private func angleDelta(from previous: Double, to current: Double) -> Double {
        var delta = current - previous
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }
}

private struct CategoryChips: View {
    let categories: [String]
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { name in
                    let isSelected = name == selection
                    Button {
                        selection = name
                    } label: {
                        Text(name)
                            .font(.caption.weight(.semibold))
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .frame(minWidth: 46)
                            .background(
                                Capsule()
                                    .fill(isSelected ? Color.blue.opacity(0.15) : Color(.systemGray6))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.2), lineWidth: 1)
                            )
                            .foregroundStyle(isSelected ? Color.blue : .primary)
                    }
                }
            }
        }
    }
}

private struct AddExpenseForm: View {
    let categories: [String]
    var onSave: (TransactionDraft) -> Void
    var onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = TransactionDraft()

    var body: some View {
        Form {
            Section("Details") {
                TextField("Amount", text: $draft.amountText)
                    .keyboardType(.decimalPad)
                Picker("Category", selection: $draft.category) {
                    ForEach(categories, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                DatePicker("Date", selection: $draft.date, displayedComponents: .date)
            }

            Section("Notes") {
                TextField("Optional note", text: $draft.note, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
        .navigationTitle("Add Expense")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    onDismiss()
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(draft)
                    onDismiss()
                }
                .disabled(!draft.isValid)
            }
        }
        .onAppear {
            if draft.category.isEmpty {
                draft.category = categories.first ?? "General"
            }
        }
    }
}

private struct TransactionDraft {
    var amountText: String = ""
    var category: String = BudgetSettings.defaultCategories.first ?? "General"
    var date: Date = .now
    var note: String = ""

    var amount: Double { Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    var isValid: Bool { amount > 0 && !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    mutating func setAmount(_ value: Double) {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        formatter.locale = Locale.current
        formatter.numberStyle = .decimal
        amountText = formatter.string(from: NSNumber(value: max(0, value))) ?? ""
    }
}

// MARK: - Monthly overview

private struct MonthlyExpensesTab: View {
    let transactions: [Transaction]
    let monthlyBudget: Double
    @Binding var selectedMonth: Date
    var onDelete: (IndexSet, [Transaction]) -> Void

    private var monthTransactions: [Transaction] {
        transactions.filter { Calendar.current.isDate($0.date, equalTo: selectedMonth, toGranularity: .month) }
    }

    private var monthTotal: Double {
        monthTransactions.reduce(0) { $0 + $1.amount }
    }

    private var remaining: Double {
        monthlyBudget - monthTotal
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                MonthSummaryCard(
                    month: selectedMonth,
                    spent: monthTotal,
                    limit: monthlyBudget,
                    remaining: remaining
                )

                List {
                    Section(header: MonthSelector(selectedMonth: $selectedMonth)) {
                        if monthTransactions.isEmpty {
                            ContentUnavailableView(
                                "No expenses",
                                systemImage: "tray",
                                description: Text("Add transactions to see them here.")
                            )
                            .frame(maxWidth: .infinity)
                        } else {
                            ForEach(Array(monthTransactions.enumerated()), id: \.element.id) { index, transaction in
                                TransactionCard(transaction: transaction)
                            }
                            .onDelete { indexSet in
                                onDelete(indexSet, monthTransactions)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .padding()
            .navigationTitle("Monthly Expenses")
        }
    }
}

private struct MonthSummaryCard: View {
    let month: Date
    let spent: Double
    let limit: Double
    let remaining: Double

    private var progress: Double {
        guard limit > 0 else { return 0 }
        return min(spent / limit, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(month, format: .dateTime.month(.wide).year())
                        .font(.headline)
                    Text("Spending overview")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Spent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(spent, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        .font(.title2.weight(.semibold))
                }
            }

            ProgressView(value: progress)
                .tint(remaining >= 0 ? .blue : .red)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(remaining >= 0 ? "Remaining" : "Over limit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(abs(remaining), format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        .font(.headline)
                        .foregroundStyle(remaining >= 0 ? .blue : .red)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Limit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(limit, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        .font(.headline)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.15), Color.purple.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct MonthSelector: View {
    @Binding var selectedMonth: Date

    var body: some View {
        HStack {
            Button {
                withAnimation {
                    selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
                }
            } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(selectedMonth, format: .dateTime.month(.wide).year())
                .font(.headline)
            Spacer()
            Button {
                withAnimation {
                    selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                }
            } label: {
                Image(systemName: "chevron.right")
            }
        }
    }
}

private struct TransactionCard: View {
    let transaction: Transaction

    private var avatarGradient: LinearGradient {
        LinearGradient(
            colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(avatarGradient)
                    .frame(width: 52, height: 52)

                Image(systemName: "creditcard.fill")
                    .foregroundStyle(.white)
                    .font(.title3)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(transaction.category)
                    .font(.headline)
                    .lineLimit(1)

                if !transaction.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(transaction.notes)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text(transaction.date, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(-transaction.amount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.red)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Settings

private struct SettingsTab: View {
    let settings: BudgetSettings
    let categories: [BudgetCategory]
    var onAddCategory: (String) -> Void
    var onDeleteCategory: (BudgetCategory) -> Void
    var onUpdateBudget: (Double) -> Void

    @State private var newCategory = ""
    @State private var budgetText: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    budgetCard
                    categoriesCard
                }
                .padding()
            }
            .navigationTitle("Settings")
        }
    }

    private var currencySymbol: String { Locale.current.currencySymbol ?? "$" }

    private var budgetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Monthly Budget")
                    .font(.title3.weight(.semibold))
                Text("Set the amount you want to keep an eye on each month.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Text(currencySymbol)
                    .font(.title3.weight(.semibold))
                    .padding(.leading, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.systemGray6))
                    )

                TextField("0", text: Binding(
                    get: { budgetText.isEmpty ? settings.monthlyBudget.formatted(.number) : budgetText },
                    set: { budgetText = $0 }
                ))
                .keyboardType(.decimalPad)
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemGray6))
                )
                .onChange(of: budgetText) { value in
                    let parsed = Double(value.replacingOccurrences(of: ",", with: ".")) ?? settings.monthlyBudget
                    onUpdateBudget(parsed)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var categoriesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Categories")
                    .font(.title3.weight(.semibold))
                Text("Organize where your money is going by keeping categories tidy.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                ForEach(categories) { category in
                    HStack(spacing: 8) {
                        Text(category.name)
                            .font(.callout.weight(.semibold))
                        Spacer(minLength: 0)
                        Button {
                            onDeleteCategory(category)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.bold())
                                .padding(6)
                                .background(Circle().fill(Color(.systemGray5)))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.systemGray6))
                    )
                }

                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.callout.weight(.semibold))
                    TextField("Add category", text: $newCategory)
                        .submitLabel(.done)
                        .onSubmit(addCategory)
                    Button(action: addCategory) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3.weight(.semibold))
                    }
                    .disabled(newCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.blue.opacity(0.4), lineWidth: 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.systemBackground))
                        )
                )
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func addCategory() {
        let trimmed = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onAddCategory(trimmed)
        newCategory = ""
    }
}

// MARK: - Transaction row

private struct TransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.15))
                    .frame(width: 42, height: 42)

                Image(systemName: "arrow.up.right.circle")
                    .foregroundStyle(Color.red)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.category)
                    .font(.headline)
                if !transaction.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(transaction.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(-transaction.amount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(transaction.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Transaction.self, BudgetSettings.self, BudgetCategory.self], inMemory: true)
}
