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
    @State private var isPresentingAddSheet = false

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
                onUpdateBudget: updateBudget,
                onUpdateQuickAmount: updateQuickAmount
            )
            .tag(Tab.settings)
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .onAppear {
            _ = settings
        }
        .sheet(isPresented: $isPresentingAddSheet) {
            NavigationStack {
                AddExpenseForm(
                    categories: categories,
                    quickAddAmount: settings.quickAddAmount,
                    onSave: addTransaction,
                    onDismiss: { isPresentingAddSheet = false }
                )
            }
            .presentationDetents([.medium, .large])
        }
        .toolbarBackground(.visible, for: .tabBar)
    }

    private func addTransaction(_ draft: TransactionDraft) {
        guard draft.isValid else { return }

        let transaction = Transaction(
            title: draft.title,
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

    private func updateQuickAmount(_ newValue: Double) {
        settings.quickAddAmount = max(0, newValue)
    }
}

// MARK: - Add Expense

private struct AddExpenseTab: View {
    let transactions: [Transaction]
    let settings: BudgetSettings
    let categories: [String]
    var onAdd: (TransactionDraft) -> Void

    @State private var draft = TransactionDraft()
    @State private var showingForm = false

    private var currentMonthTotal: Double {
        transactions.filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
    }

    private var remainingBudget: Double {
        max(settings.monthlyBudget - currentMonthTotal, 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    BudgetHeaderCard(
                        remainingBudget: remainingBudget,
                        currencyCode: Locale.current.currency?.identifier ?? "USD",
                        quickAmount: settings.quickAddAmount
                    ) {
                        draft.setAmount(settings.quickAddAmount)
                    }

                    ExpenseDialCard(
                        remainingBudget: remainingBudget,
                        currencyCode: Locale.current.currency?.identifier ?? "USD",
                        draft: $draft
                    )

                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Title")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("What did you spend on?", text: $draft.title)
                                .textInputAutocapitalization(.sentences)
                                .padding()
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.systemGray6)))
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Category")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Detailed Form") {
                                    showingForm = true
                                }
                                .font(.footnote.weight(.semibold))
                            }

                            CategoryChips(categories: categories, selection: $draft.category)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Note")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("Optional note", text: $draft.note, axis: .vertical)
                                .padding()
                                .lineLimit(1...3)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.systemGray6)))
                        }

                        Button(action: {
                            onAdd(draft)
                            draft = TransactionDraft(category: categories.first ?? "General")
                        }) {
                            Text("Add Expense")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .foregroundStyle(.white)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(draft.isValid ? Color.blue : Color.gray.opacity(0.5))
                                )
                        }
                        .disabled(!draft.isValid)
                    }
                }
                .padding(24)
            }
            .navigationTitle("New Expense")
            .sheet(isPresented: $showingForm) {
                NavigationStack {
                    AddExpenseForm(
                        categories: categories,
                        quickAddAmount: settings.quickAddAmount,
                        onSave: { draft in
                            onAdd(draft)
                            showingForm = false
                            self.draft = TransactionDraft(category: categories.first ?? "General")
                        },
                        onDismiss: { showingForm = false }
                    )
                }
                .presentationDetents([.medium, .large])
            }
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
    let quickAmount: Double
    var onQuickFill: () -> Void

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
            Spacer()
            Button(action: onQuickFill) {
                VStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.title3)
                    Text("Quick")
                        .font(.caption.weight(.semibold))
                    Text(quickAmount, format: .currency(code: currencyCode))
                        .font(.caption2)
                }
                .foregroundStyle(.white)
                .padding(14)
                .frame(width: 84, height: 84)
                .background(.white.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(.white.opacity(0.3), lineWidth: 1)
                )
            }
        }
        .padding(20)
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Set expense amount")
                        .font(.headline)
                    Text("Drag around the dial to fine-tune your spend.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(Date.now, style: .date)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            BudgetDial(
                amount: amountBinding,
                maximum: max(remainingBudget, 0.01),
                displayMaximum: remainingBudget,
                currencyCode: currencyCode
            )
            .frame(height: 280)
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct BudgetDial: View {
    @Binding var amount: Double
    let maximum: Double
    let displayMaximum: Double
    let currencyCode: String

    @GestureState private var isDragging = false

    private var denominator: Double { displayMaximum > 0 ? displayMaximum : maximum }
    private var progress: Double { denominator > 0 ? amount / denominator : 0 }
    private var clampedProgress: Double { min(max(progress, 0), 1) }
    private var overBudget: Bool { displayMaximum > 0 ? amount > displayMaximum : amount > 0 }
    private var remainingAfterSelection: Double { max(displayMaximum - amount, 0) }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = size / 2 - 14
            let endAngle = Angle(degrees: -90 + clampedProgress * 360)
            let endPoint = CGPoint(
                x: center.x + cos(CGFloat(endAngle.radians)) * radius,
                y: center.y + sin(CGFloat(endAngle.radians)) * radius
            )

            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.15), lineWidth: 18)

                let gradient = AngularGradient(
                    colors: overBudget ? [.red, .black] : [.blue, .black],
                    center: .center,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + clampedProgress * 360)
                )

                Circle()
                    .trim(from: 0, to: clampedProgress)
                    .stroke(gradient, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees(0))

                if overBudget {
                    Circle()
                        .stroke(Color.red.opacity(0.25), lineWidth: 18)
                }

                Circle()
                    .fill(overBudget ? Color.red : Color.black)
                    .frame(width: 16, height: 16)
                    .position(endPoint)

                VStack(spacing: 6) {
                    Text(amount, format: .currency(code: currencyCode))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("Remaining \(remainingAfterSelection, format: .currency(code: currencyCode))")
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
            )
        }
    }

    private func updateAmount(from location: CGPoint, in size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let vector = CGVector(dx: location.x - center.x, dy: location.y - center.y)
        let angle = atan2(vector.dy, vector.dx) + .pi / 2
        var degrees = angle * 180 / .pi
        if degrees < 0 { degrees += 360 }
        let newProgress = degrees / 360
        let clampedAmount = min(maximum * newProgress, maximum)
        amount = max(0, clampedAmount)
    }
}

private struct CategoryChips: View {
    let categories: [String]
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(categories, id: \.self) { name in
                    let isSelected = name == selection
                    Button {
                        selection = name
                    } label: {
                        Text(name)
                            .font(.subheadline.weight(.semibold))
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .frame(minWidth: 64)
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
    let quickAddAmount: Double
    var onSave: (TransactionDraft) -> Void
    var onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = TransactionDraft()

    var body: some View {
        Form {
            Section("Details") {
                TextField("Amount", text: $draft.amountText)
                    .keyboardType(.decimalPad)
                TextField("Title", text: $draft.title)
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

            Section("Shortcuts") {
                Button(
                    "Use quick amount (\(quickAddAmount.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))))"
                ) {
                    draft.amountText = quickAddAmount.formatted(.number)
                }
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
    var title: String = ""
    var amountText: String = ""
    var category: String = BudgetSettings.defaultCategories.first ?? "General"
    var date: Date = .now
    var note: String = ""

    var amount: Double { Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    var isValid: Bool { amount > 0 && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

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
    @Binding var selectedMonth: Date
    var onDelete: (IndexSet, [Transaction]) -> Void

    private var monthTransactions: [Transaction] {
        transactions.filter { Calendar.current.isDate($0.date, equalTo: selectedMonth, toGranularity: .month) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MonthSelector(selectedMonth: $selectedMonth)
                }

                Section("This month") {
                    if monthTransactions.isEmpty {
                        ContentUnavailableView(
                            "No expenses",
                            systemImage: "tray",
                            description: Text("Add transactions to see them here.")
                        )
                    } else {
                        ForEach(monthTransactions) { transaction in
                            TransactionRow(transaction: transaction)
                        }
                        .onDelete { offsets in
                            onDelete(offsets, monthTransactions)
                        }
                    }
                }
            }
            .navigationTitle("Monthly Expenses")
        }
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

// MARK: - Settings

private struct SettingsTab: View {
    let settings: BudgetSettings
    let categories: [BudgetCategory]
    var onAddCategory: (String) -> Void
    var onDeleteCategory: (BudgetCategory) -> Void
    var onUpdateBudget: (Double) -> Void
    var onUpdateQuickAmount: (Double) -> Void

    @State private var newCategory = ""
    @State private var budgetText: String = ""
    @State private var quickAmountText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Monthly Budget") {
                    TextField("Amount", text: Binding(
                        get: { budgetText.isEmpty ? settings.monthlyBudget.formatted(.number) : budgetText },
                        set: { budgetText = $0 }
                    ))
                    .keyboardType(.decimalPad)
                    .onChange(of: budgetText) { value in
                        let parsed = Double(value.replacingOccurrences(of: ",", with: ".")) ?? settings.monthlyBudget
                        onUpdateBudget(parsed)
                    }
                }

                Section("Quick add amount") {
                    TextField("Preferred quick add", text: Binding(
                        get: { quickAmountText.isEmpty ? settings.quickAddAmount.formatted(.number) : quickAmountText },
                        set: { quickAmountText = $0 }
                    ))
                    .keyboardType(.decimalPad)
                    .onChange(of: quickAmountText) { value in
                        let parsed = Double(value.replacingOccurrences(of: ",", with: ".")) ?? settings.quickAddAmount
                        onUpdateQuickAmount(parsed)
                    }
                }

                Section("Categories") {
                    ForEach(categories) { category in
                        HStack {
                            Text(category.name)
                            Spacer()
                            Button(role: .destructive) {
                                onDeleteCategory(category)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    HStack {
                        TextField("New category", text: $newCategory)
                        Button("Add") {
                            onAddCategory(newCategory)
                            newCategory = ""
                        }
                        .disabled(newCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section("iCloud") {
                    Label("Data syncs securely with iCloud using CloudKit", systemImage: "icloud")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
            .navigationTitle("Settings")
        }
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
                Text(transaction.title)
                    .font(.headline)
                Text(transaction.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !transaction.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(transaction.notes)
                        .font(.caption2)
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
