//
//  ContentView.swift
//  SimpleBudget
//
//  Created by Dionicy Tarantino on 12/2/25.
//

import SwiftUI
import SwiftData

private extension Color {
    static let primaryBlue = Color(red: 0.25, green: 0.55, blue: 1.0)
    static let primaryText = Color(red: 0.12, green: 0.14, blue: 0.2)
    static let secondaryLabel = Color(red: 0.45, green: 0.5, blue: 0.58)
    static let cardBackground = Color.white
    static let pageBackground = Color(red: 0.96, green: 0.97, blue: 0.99)
    static let border = Color(red: 0.88, green: 0.91, blue: 0.96)
}

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
            VStack(alignment: .leading, spacing: 50) {
                Spacer()
                ExpenseDialCard(
                    remainingBudget: remainingBudget,
                    currencyCode: Locale.current.currency?.identifier ?? "USD",
                    draft: $draft
                )

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Category")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.secondaryLabel)
                            .textCase(.uppercase)

                        CategoryChips(categories: categories, selection: $draft.category)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Note")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.secondaryLabel)
                            .textCase(.uppercase)
                        TextField("Note (optional)", text: $draft.note, axis: .vertical)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .lineLimit(1...3)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.cardBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.border, lineWidth: 1)
                            )
                    }

                    Button(action: {
                        onAdd(draft)
                        draft = TransactionDraft(category: categories.first ?? "General")
                    }) {
                        Text("Add Expense")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(draft.isValid ? Color.primaryBlue : Color.gray.opacity(0.4))
                            )
                    }
                    .disabled(!draft.isValid)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.pageBackground)
            .navigationTitle("New Expense")
            .ignoresSafeArea()
            .onAppear {
                if draft.category.isEmpty {
                    draft.category = categories.first ?? "General"
                }
            }
        }
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
                        .font(.system(size: 16, weight: .semibold))
//                    Text("Drag around the dial to fine-tune your spend.")
//                        .font(.system(size: 13))
//                        .foregroundStyle(Color.secondaryLabel)
                }
                Spacer()
                Text(Date.now, format: Date.FormatStyle().month(.abbreviated).year())
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primaryBlue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.primaryBlue.opacity(0.12))
                    )
            }

            BudgetDial(
                amount: amountBinding,
                remainingBudget: remainingBudget,
                currencyCode: currencyCode
            )
            .frame(height: 180)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.border, lineWidth: 1)
        )
    }
}

func smallestSignedAngleDelta(from previous: Double, to current: Double) -> Double {
    let rawDelta = current - previous
    let wrapped = ((rawDelta + 180).truncatingRemainder(dividingBy: 360) + 360)
        .truncatingRemainder(dividingBy: 360)
    return wrapped - 180
}

private struct BudgetDial: View {
    @Binding var amount: Double
    let remainingBudget: Double
    let currencyCode: String

    @GestureState private var isDragging = false
    @State private var initialProgress: Double = 0
    @State private var progressDelta: Double = 0
    @State private var previousAngle: Double?

    private var dialRange: Double { max(remainingBudget, 0) }
    private var normalizedProgress: Double {
        guard dialRange > 0 else { return 0 }
        return max(amount / dialRange, 0)
    }
    private var primaryTrim: Double { min(normalizedProgress, 1) }
    private var overflowProgress: Double { max(normalizedProgress - 1, 0) }
    private var overflowTrim: Double {
        guard overflowProgress > 0 else { return 0 }
        let remainder = overflowProgress.truncatingRemainder(dividingBy: 1)
        return remainder == 0 ? 1 : remainder
    }
    private var knobRotationProgress: Double {
        guard normalizedProgress >= 1 else { return primaryTrim }
        let wrapped = normalizedProgress.truncatingRemainder(dividingBy: 1)
        return wrapped == 0 ? 1 : wrapped
    }
    private var overBudget: Bool { remainingBudget > 0 ? amount > remainingBudget : amount > 0 }
    private var remainingAfterSelection: Double { max(remainingBudget - amount, 0) }
    private var overageAmount: Double {
        guard remainingBudget > 0 else { return max(amount, 0) }
        return max(amount - remainingBudget, 0)
    }
    private var statusText: String {
        if overBudget {
            return "⚠️ Over by \(overageAmount.formatted(.currency(code: currencyCode)))"
        } else if isDragging {
            return "Remaining \(remainingAfterSelection.formatted(.currency(code: currencyCode)))"
        }
        return "Remaining \(remainingAfterSelection.formatted(.currency(code: currencyCode)))"
    }
    private var statusBackground: Color {
        if overBudget {
            return Color.red.opacity(0.12)
        } else if isDragging {
            return Color.blue.opacity(0.12)
        }
        return Color.gray.opacity(0.12)
    }
    private var statusForeground: Color {
        if overBudget {
            return .red
        } else if isDragging {
            return .blue
        }
        return Color.gray
    }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let dialSize = size
            let center = CGPoint(x: dialSize / 2, y: dialSize / 2)
            let ringWidth: CGFloat = 18
            let knobRadius = dialSize / 2
            let endAngle = Angle(degrees: knobRotationProgress * 360 - 90)
            let endPoint = CGPoint(
                x: center.x + cos(CGFloat(endAngle.radians)) * knobRadius,
                y: center.y + sin(CGFloat(endAngle.radians)) * knobRadius
            )

            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Color.primaryBlue.opacity(0.12), lineWidth: ringWidth)

                    let fillGradient = AngularGradient(
                        colors: [Color.primaryBlue.opacity(0.3), Color.primaryBlue],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(primaryTrim * 360)
                    )

                    Circle()
                        .trim(from: 0, to: primaryTrim)
                        .stroke(fillGradient, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    if overBudget {
                        Circle()
                            .trim(from: 0, to: overflowTrim)
                            .stroke(
                                AngularGradient(
                                    colors: [Color.red.opacity(0.65), .red],
                                    center: .center,
                                    startAngle: .degrees(0),
                                    endAngle: .degrees(overflowTrim * 360)
                                ),
                                style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                    }

                    Circle()
                        .fill(overBudget ? Color.red : Color.primaryBlue)
                        .frame(width: 16, height: 16)
                        .position(endPoint)

                    VStack(spacing: 6) {
                        Text("$ ")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.primaryBlue)
                            + Text(amount, format: .number.precision(.fractionLength(0)))
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.primaryText)
                        Button {
                            amount = 0
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark")
                                Text("Clear")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(Color.secondaryLabel)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: dialSize, height: dialSize)

                Text(statusText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(statusForeground)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(statusBackground)
                    )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDragging) { _, state, _ in
                        state = true
                    }
                    .onChanged { value in
                        let dialFrame = CGRect(
                            x: (proxy.size.width - dialSize) / 2,
                            y: 0,
                            width: dialSize,
                            height: dialSize
                        )
                        updateAmount(from: value.location, in: dialFrame)
                    }
                    .onEnded { _ in
                        resetDragState()
                    }
            )
        }
    }

    private func updateAmount(from location: CGPoint, in dialFrame: CGRect) {
        let dialLocation = CGPoint(
            x: min(max(location.x - dialFrame.minX, 0), dialFrame.width),
            y: min(max(location.y - dialFrame.minY, 0), dialFrame.height)
        )
        let angle = normalizedAngle(for: dialLocation, in: dialFrame.size)

        if previousAngle == nil {
            previousAngle = angle
            initialProgress = dialRange > 0 ? amount / dialRange : 0
        }

        if let previousAngle, dialRange > 0 {
            progressDelta += angleDelta(from: previousAngle, to: angle) / 360
        }

        previousAngle = angle

        guard dialRange > 0 else { return }

        let newProgress = max(0, initialProgress + progressDelta)
        amount = max(0, newProgress * dialRange)
    }

    private func resetDragState() {
        initialProgress = dialRange > 0 ? amount / dialRange : 0
        progressDelta = 0
        previousAngle = nil
    }

    private func normalizedAngle(for location: CGPoint, in size: CGSize) -> Double {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let vector = CGVector(dx: location.x - center.x, dy: location.y - center.y)
        let angle = atan2(vector.dy, vector.dx)
        var degrees = angle * 180 / .pi
        if degrees < 0 { degrees += 360 }
        return (degrees + 90).truncatingRemainder(dividingBy: 360)
    }

    private func angleDelta(from previous: Double, to current: Double) -> Double {
        smallestSignedAngleDelta(from: previous, to: current)
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
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.vertical, 7)
                            .padding(.horizontal, 12)
                            .frame(minWidth: 46)
                            .background(
                                Capsule()
                                    .fill(isSelected ? Color.primaryBlue : Color.cardBackground)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(isSelected ? Color.primaryBlue : Color.border, lineWidth: 1)
                            )
                            .foregroundStyle(isSelected ? Color.white : Color.secondaryLabel)
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

struct TransactionDraft {
    var amountText: String = ""
    var category: String = BudgetSettings.defaultCategories.first ?? "General"
    var date: Date = .now
    var note: String = ""

    var amount: Double {
        let formatter = TransactionDraft.makeNumberFormatter()
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        return formatter.number(from: trimmed)?.doubleValue ?? 0
    }
    var isValid: Bool { amount > 0 && !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    mutating func setAmount(_ value: Double) {
        let formatter = TransactionDraft.makeNumberFormatter()
        amountText = formatter.string(from: NSNumber(value: max(0, value))) ?? ""
    }

    private static func makeNumberFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        formatter.locale = Locale.current
        formatter.numberStyle = .decimal
        return formatter
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
            ScrollView {
                VStack(spacing: 18) {
                    MonthSelector(selectedMonth: $selectedMonth)
                        .padding(.top, 4)

                    MonthSummaryCard(
                        month: selectedMonth,
                        spent: monthTotal,
                        limit: monthlyBudget,
                        remaining: remaining
                    )

                    TransactionsSection(
                        transactions: monthTransactions,
                        onDelete: { indexSet in
                            onDelete(indexSet, monthTransactions)
                        }
                    )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Monthly Overview")
            .navigationBarTitleDisplayMode(.inline)
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(month, format: .dateTime.month(.wide).year())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text("Total spent")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                    Text(spent, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Text("Monthly limit")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                    Text(limit, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)

                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 72, height: 1)

                    Text(remaining >= 0 ? "Remaining" : "Over")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    Text(abs(remaining), format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(remaining >= 0 ? .white : .red.opacity(0.9))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: progress)
                    .tint(.white)
                    .shadow(color: .white.opacity(0.2), radius: 2, x: 0, y: 2)

                HStack {
                    Label(
                        remaining >= 0 ? "On track" : "Over budget",
                        systemImage: remaining >= 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(remaining >= 0 ? .white.opacity(0.9) : .yellow.opacity(0.95))

                    Spacer()

                    Text("\(Int(progress * 100))% of limit")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(red: 0.38, green: 0.32, blue: 0.88), Color(red: 0.65, green: 0.51, blue: 0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .background(.thinMaterial.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct MonthSelector: View {
    @Binding var selectedMonth: Date

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }

            VStack(spacing: 4) {
                Text("Monthly Overview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(selectedMonth, format: .dateTime.month(.wide).year())
                    .font(.title3.weight(.semibold))
            }
            .frame(maxWidth: .infinity)

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.vertical, 2)
    }
}

private struct TransactionsSection: View {
    let transactions: [Transaction]
    var onDelete: (IndexSet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Transactions")
                        .font(.headline)
                    Text("Your spending details for this month")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(transactions.count) items")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if transactions.isEmpty {
                ContentUnavailableView(
                    "No expenses",
                    systemImage: "tray",
                    description: Text("Add transactions to see them here.")
                )
                .frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(Array(transactions.enumerated()), id: \.element.id) { index, transaction in
                        TransactionCard(transaction: transaction)
                            .swipeActions {
                                Button(role: .destructive) {
                                    onDelete(IndexSet(integer: index))
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct TransactionCard: View {
    let transaction: Transaction

    private var avatarGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.53, green: 0.45, blue: 0.95), Color(red: 0.36, green: 0.62, blue: 0.98)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var iconName: String {
        switch transaction.category.lowercased() {
        case let name where name.contains("food") || name.contains("dining"):
            return "fork.knife"
        case let name where name.contains("travel") || name.contains("transport"):
            return "airplane"
        case let name where name.contains("shopping") || name.contains("store"):
            return "bag.fill"
        default:
            return "creditcard.fill"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(avatarGradient)
                    .frame(width: 52, height: 52)

                Image(systemName: iconName)
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
                .foregroundStyle(Color(red: 0.91, green: 0.24, blue: 0.36))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 6)
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
