//
//  ContentView.swift
//  SimpleBudget
//
//  Created by Dionicy Tarantino on 12/2/25.
//

import SwiftUI
import SwiftData

// Shared color palette for consistent styling across views
private extension Color {
    static let primaryBlue = Color(red: 0.25, green: 0.55, blue: 1.0)
    static let primaryText = Color(red: 0.12, green: 0.14, blue: 0.2)
    static let secondaryLabel = Color(red: 0.45, green: 0.5, blue: 0.58)
    static let cardBackground = Color(red: 0.96, green: 0.97, blue: 0.99)
    static let pageBackground = Color(red: 0.96, green: 0.97, blue: 0.99)
    static let border = Color(red: 0.88, green: 0.91, blue: 0.96)
}

// Root tab view orchestrating expense entry, history, and settings
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

    // Tab identifiers for the main application sections
    private enum Tab: Hashable {
        case add, history, settings
    }

    // Main container displaying each tab
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
                onDelete: deleteTransaction
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

    // Handles adding a new transaction from user input
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

    // Removes a transaction when confirmed by the user
    private func deleteTransaction(_ transaction: Transaction) {
        withAnimation {
            modelContext.delete(transaction)
        }
    }

    // Adds a new budget category while ensuring uniqueness
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

    // Deletes a category and cleans up its association with settings
    private func deleteCategory(_ category: BudgetCategory) {
        if var current = settings.categories, let index = current.firstIndex(of: category) {
            current.remove(at: index)
            settings.categories = current
        }
        modelContext.delete(category)
    }

    // Updates the monthly budget while preventing negative values
    private func updateBudget(_ newValue: Double) {
        settings.monthlyBudget = max(0, newValue)
    }
}

// MARK: - Add Expense

// Tab presenting the form and dial for creating a new expense
private struct AddExpenseTab: View {
    let transactions: [Transaction]
    let settings: BudgetSettings
    let categories: [String]
    var onAdd: (TransactionDraft) -> Void

    @State private var draft = TransactionDraft()
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case note }

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
                ExpenseDialCard(
                    remainingBudget: remainingBudget,
                    monthlyBudget: settings.monthlyBudget,
                    currentSpent: currentMonthTotal,
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
                            .focused($focusedField, equals: .note)
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
                        focusedField = nil
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
            .onAppear {
                if draft.category.isEmpty {
                    draft.category = categories.first ?? "General"
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
        }
    }
}

// Card wrapping the dial and header for selecting expense amounts
private struct ExpenseDialCard: View {
    let remainingBudget: Double
    let monthlyBudget: Double
    let currentSpent: Double
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
        VStack(alignment: .leading, spacing: 30) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("New Expense")
                        .font(.system(size: 25, weight: .semibold))
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
                monthlyBudget: monthlyBudget,
                currentSpent: currentSpent,
                currencyCode: currencyCode
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.cardBackground)
        )
//        .overlay(
//            RoundedRectangle(cornerRadius: 20, style: .continuous)
//                .stroke(Color.border, lineWidth: 1)
//        )
    }
}

// Computes the smallest directional difference between two angles in degrees
func smallestSignedAngleDelta(from previous: Double, to current: Double) -> Double {
    let rawDelta = current - previous
    let wrapped = ((rawDelta + 180).truncatingRemainder(dividingBy: 360) + 360)
        .truncatingRemainder(dividingBy: 360)
    return wrapped - 180
}

/// Extracted scaling math for the budget dial so it can be validated in tests.
struct BudgetDialScalingMetrics {
    let amount: Double
    let remainingBudget: Double
    let monthlyBudget: Double
    let currentSpent: Double

    private let overBudgetRange: Double = 500

    private var remainingRange: Double {
        guard monthlyBudget > 0 else { return max(remainingBudget, 0) }

        if shouldCapRange {
            return max(min(remainingBudget, monthlyBudget), 0)
        }

        return max(remainingBudget, 0)
    }

    private var projectedTotal: Double { currentSpent + amount }

    private var shouldCapRange: Bool {
        guard monthlyBudget > 0 else { return false }
        return remainingBudget > monthlyBudget
            || currentSpent > monthlyBudget
            || projectedTotal > monthlyBudget
    }

    var dialRange: Double { remainingRange + overBudgetRange }

    func progress(for selection: Double) -> Double {
        let selection = max(selection, 0)

        guard remainingRange > 0 else {
            return 1 + selection / overBudgetRange
        }

        if selection <= remainingRange {
            return selection / remainingRange
        }

        return 1 + (selection - remainingRange) / overBudgetRange
    }

    func amount(for progress: Double) -> Double {
        let progress = max(progress, 0)

        guard remainingRange > 0 else {
            return max(0, (progress - 1) * overBudgetRange)
        }

        if progress <= 1 {
            return progress * remainingRange
        }

        return remainingRange + max(0, (progress - 1) * overBudgetRange)
    }

    var normalizedProgress: Double { progress(for: amount) }

    var primaryTrim: Double { min(normalizedProgress, 1) }

    var knobRotationProgress: Double { normalizedProgress }
}

// Interactive radial dial used to adjust the expense amount
private struct BudgetDial: View {
    @Binding var amount: Double
    let remainingBudget: Double
    let monthlyBudget: Double
    let currentSpent: Double
    let currencyCode: String

    @GestureState private var isDragging = false
    @State private var initialProgress: Double = 0
    @State private var progressDelta: Double = 0
    @State private var previousAngle: Double?

    private var scaling: BudgetDialScalingMetrics {
        BudgetDialScalingMetrics(
            amount: amount,
            remainingBudget: remainingBudget,
            monthlyBudget: monthlyBudget,
            currentSpent: currentSpent
        )
    }

    private var dialRange: Double { scaling.dialRange }
    private var normalizedProgress: Double { scaling.normalizedProgress }
    private var primaryTrim: Double { scaling.primaryTrim }
    private var knobRotationProgress: Double { scaling.knobRotationProgress }
    private var notZero: Bool { amount > 0 }
    private var projectedTotal: Double { currentSpent + amount }
    private var remainingAfterSelection: Double { max(monthlyBudget - projectedTotal, 0) }
    private var remainingDaysInMonth: Int {
        let calendar = Calendar.current
        let today = calendar.component(.day, from: .now)
        let daysInMonth = calendar.range(of: .day, in: .month, for: .now)?.count ?? today
        return max(daysInMonth - today + 1, 1)
    }
    private var perDayAllowance: Double {
        guard remainingDaysInMonth > 0 else { return 0 }
        return remainingAfterSelection / Double(remainingDaysInMonth)
    }
    private var isMonthOverBudget: Bool { monthlyBudget > 0 && currentSpent >= monthlyBudget }
    private var isProjectedOverBudget: Bool { monthlyBudget > 0 && projectedTotal >= monthlyBudget }
    private var overageAmount: Double { max(projectedTotal - monthlyBudget, 0) }
    private var statusText: String {
        if isMonthOverBudget || isProjectedOverBudget {
            return "⚠️ Over by \(overageAmount.formatted(.currency(code: currencyCode)))"
        } else if isDragging {
            return "Remaining \(remainingAfterSelection.formatted(.currency(code: currencyCode)))"
        }

        return "Remaining \(remainingAfterSelection.formatted(.currency(code: currencyCode)))"
    }
    private var statusBackground: Color {
        if isMonthOverBudget || isProjectedOverBudget {
            return Color.red.opacity(0.12)
        } else if isDragging {
            return Color.blue.opacity(0.12)
        }
        return Color.gray.opacity(0.12)
    }
    private var statusForeground: Color {
        if isMonthOverBudget || isProjectedOverBudget {
            return .red
        } else if isDragging {
            return .blue
        }
        return Color.gray
    }

    private let maxDialDiameter: CGFloat = 360

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let dialSize = min(proxy.size.width, maxDialDiameter)
                let center = CGPoint(x: dialSize / 2, y: dialSize / 2)
                let ringWidth: CGFloat = 18
                let ringRadius = dialSize / 2 - ringWidth / 2
                let endAngle = Angle(degrees: knobRotationProgress * 360 - 90)
                let endPoint = CGPoint(
                    x: center.x + cos(CGFloat(endAngle.radians)) * ringRadius,
                    y: center.y + sin(CGFloat(endAngle.radians)) * ringRadius
                )
                let dragGesture = DragGesture(minimumDistance: 0, coordinateSpace: .named("dial"))
                    .updating($isDragging) { _, state, _ in
                        state = true
                    }
                    .onChanged { value in
                        updateAmount(from: value.location, in: CGSize(width: dialSize, height: dialSize))
                    }
                    .onEnded { _ in
                        resetDragState()
                    }

                ZStack {
                    if isMonthOverBudget || isProjectedOverBudget {
                        Circle()
                            .stroke(Color.red, lineWidth: ringWidth)
                            .frame(width: ringRadius * 2, height: ringRadius * 2, alignment: .center)
                    } else {
                        Circle()
                            .stroke(Color.primaryBlue.opacity(0.12), lineWidth: ringWidth)
                            .frame(width: ringRadius * 2, height: ringRadius * 2, alignment: .center)

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
                            .frame(width: ringRadius * 2, height: ringRadius * 2, alignment: .center)
                    }

                    Circle()
                        .fill(Color.black)
                        .frame(width: 17, height: 17)
                        .position(endPoint)
                        .contentShape(Circle().inset(by: -28))
                        .highPriorityGesture(dragGesture)

                    VStack(spacing: 6) {
                        amountText
                        Button {
                            amount = 0
                        } label: {

                                HStack(spacing: 6) {
                                    Image(systemName: "xmark")
                                    Text("Clear")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundStyle(notZero ? Color.secondaryLabel : Color.pageBackground)

                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: dialSize, height: dialSize, alignment: .center)
                .contentShape(Circle().inset(by: -24))
                .coordinateSpace(name: "dial")
                .gesture(dragGesture)
            }
            .frame(maxWidth: .infinity)
            .frame(maxWidth: maxDialDiameter)
            .aspectRatio(1, contentMode: .fit)

            Text(statusText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(statusForeground)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(statusBackground)
                )

            Group {
                if !isMonthOverBudget && !isProjectedOverBudget {
                    Text("Daily allowance \(perDayAllowance.formatted(.currency(code: currencyCode)))")
                } else {
                    Text("Daily allowance placeholder")
                        .hidden()
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.secondaryLabel)
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("BudgetDial")
        .accessibilityLabel("Budget Dial")
        .accessibilityValue("range:\(Int(dialRange.rounded()))")
    }

    private var amountText: Text {
        let formattedAmount = amount.formatted(.number.precision(.fractionLength(0)))
        var attributedString = AttributedString("$ \(formattedAmount)")

        if let symbolRange = attributedString.range(of: "$ ") {
            attributedString[symbolRange].font = .system(size: 30, weight: .bold)
            attributedString[symbolRange].foregroundColor = .primaryBlue
        }

        if let amountRange = attributedString.range(of: formattedAmount) {
            attributedString[amountRange].font = .system(size: 38, weight: .bold, design: .rounded)
            attributedString[amountRange].foregroundColor = .primaryText
        }

        return Text(attributedString)
    }

    private func updateAmount(from location: CGPoint, in size: CGSize) {
        let angle = normalizedAngle(for: location, in: size)

        if previousAngle == nil {
            previousAngle = angle
            initialProgress = scaling.normalizedProgress
        }

        if let previousAngle, dialRange > 0 {
            progressDelta += angleDelta(from: previousAngle, to: angle) / 360
        }

        previousAngle = angle

        guard dialRange > 0 else { return }

        let newProgress = max(0, initialProgress + progressDelta)
        amount = scaling.amount(for: newProgress)
    }

    private func resetDragState() {
        initialProgress = scaling.normalizedProgress
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

// A flexible horizontal layout that wraps subviews onto new lines as needed
private struct WrappingHStack: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let availableWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let itemWidth = size.width
            let itemHeight = size.height

            // Wrap to next line if this item doesn't fit
            if currentX > 0 && currentX + spacing + itemWidth > availableWidth {
                currentX = 0
                currentY += lineHeight + lineSpacing
                lineHeight = 0
            }

            if currentX > 0 { currentX += spacing }
            currentX += itemWidth
            lineHeight = max(lineHeight, itemHeight)
        }

        // If width is not constrained, return the total width consumed; otherwise honor available width
        let finalWidth = availableWidth.isFinite ? availableWidth : currentX
        return CGSize(width: finalWidth, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let availableWidth = bounds.width
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let itemWidth = size.width
            let itemHeight = size.height

            // Wrap to next line if this item doesn't fit
            if currentX > bounds.minX && currentX + spacing + itemWidth > bounds.minX + availableWidth {
                currentX = bounds.minX
                currentY += lineHeight + lineSpacing
                lineHeight = 0
            }

            if currentX > bounds.minX { currentX += spacing }

            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(width: itemWidth, height: itemHeight)
            )

            currentX += itemWidth
            lineHeight = max(lineHeight, itemHeight)
        }
    }
}

// Scrollable chip selector for choosing expense categories
private struct CategoryChips: View {
    let categories: [String]
    @Binding var selection: String

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            WrappingHStack(spacing: 10, lineSpacing: 10) {
                ForEach(categories, id: \.self) { name in
                    let isSelected = name == selection
                    Button {
                        selection = name
                    } label: {
                        Text(name)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.vertical, 7)
                            .padding(.horizontal, 12)
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 80)
    }
}

// Legacy form-style expense entry used in alternate flows
private struct AddExpenseForm: View {
    let categories: [String]
    var onSave: (TransactionDraft) -> Void
    var onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = TransactionDraft()
    @FocusState private var isNoteFocused: Bool

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
                    .focused($isNoteFocused)
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
                    isNoteFocused = false
                    onSave(draft)
                    onDismiss()
                }
                .disabled(!draft.isValid)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isNoteFocused = false }
            }
        }
        .onAppear {
            if draft.category.isEmpty {
                draft.category = categories.first ?? "General"
            }
        }
    }
}

// Data holder used for binding form fields before creating a Transaction
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

// Tab summarizing spending for a selected month with deletion support
private struct MonthlyExpensesTab: View {
    let transactions: [Transaction]
    let monthlyBudget: Double
    @Binding var selectedMonth: Date
    var onDelete: (Transaction) -> Void

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
            List {
                Section {
                    MonthSelector(selectedMonth: $selectedMonth)
                        .padding(.top, 4)
                        .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 6, trailing: 20))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color(.systemGroupedBackground))

                    MonthSummaryCard(
                        month: selectedMonth,
                        spent: monthTotal,
                        limit: monthlyBudget,
                        remaining: remaining
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 12, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color(.systemGroupedBackground))
                }
                .textCase(nil)

                TransactionsSection(
                    transactions: monthTransactions,
                    onDelete: onDelete
                )
            }
            .listStyle(.plain)
            .listSectionSeparator(.hidden)
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Monthly Overview")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// Summary card highlighting spending progress and remaining budget
private struct MonthSummaryCard: View {
    let month: Date
    let spent: Double
    let limit: Double
    let remaining: Double

    private var progress: Double {
        guard limit > 0 else { return 0 }
        let ratio = spent / limit
        return min(max(ratio, 0), 1)
    }

    private var progressPercentage: Int {
        Int(progress * 100)
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

                    Text("\(progressPercentage)% of limit")
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

// Header control for navigating between months in history view
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

// List section summarizing transactions for the selected month
private struct TransactionsSection: View {
    let transactions: [Transaction]
    var onDelete: (Transaction) -> Void

    @State private var pendingDeletion: Transaction?
    @State private var showingDeleteConfirmation = false

    var body: some View {
        Section {
            if transactions.isEmpty {
                ContentUnavailableView(
                    "No expenses",
                    systemImage: "tray",
                    description: Text("Add transactions to see them here.")
                )
                .frame(maxWidth: .infinity)
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 12, trailing: 20))
                .listRowBackground(Color(.systemGroupedBackground))
            } else {
                ForEach(transactions, id: \.id) { transaction in
                    TransactionCard(transaction: transaction)
                        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color(.systemGroupedBackground))
                        .swipeActions(allowsFullSwipe: true) {
                            Button {
                                pendingDeletion = transaction
                                showingDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                }
            }
        } header: {
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
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .background(Color(.systemGroupedBackground))
        }
        .alert("Delete transaction?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let pendingDeletion {
                    onDelete(pendingDeletion)
                }
                pendingDeletion = nil
            }

            Button("Cancel", role: .cancel) {
                pendingDeletion = nil
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }
}

// Card-styled row displaying transaction details and quick actions
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

// Tab for adjusting budget preferences and managing categories
private struct SettingsTab: View {
    let settings: BudgetSettings
    let categories: [BudgetCategory]
    var onAddCategory: (String) -> Void
    var onDeleteCategory: (BudgetCategory) -> Void
    var onUpdateBudget: (Double) -> Void

    @State private var newCategory = ""
    @State private var budgetText: String = ""
    @FocusState private var isBudgetFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    budgetCard
                    categoriesCard
                }
                .padding()
                .contentShape(Rectangle())
                .onTapGesture { isBudgetFieldFocused = false }
            }
            .scrollDismissesKeyboard(.immediately)
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
                .focused($isBudgetFieldFocused)
                .keyboardType(.decimalPad)
                .submitLabel(.done)
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemGray6))
                )
                .onChange(of: budgetText) { _, newValue in
                    let parsed = Double(newValue.replacingOccurrences(of: ",", with: ".")) ?? settings.monthlyBudget
                    onUpdateBudget(parsed)
                }
                .onSubmit {
                    isBudgetFieldFocused = false
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            isBudgetFieldFocused = false
                        }
                    }
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

// MARK: - Transaction row

// Compact row used in list previews of transactions
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

