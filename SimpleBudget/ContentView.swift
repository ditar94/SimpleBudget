//
//  ContentView.swift
//  SimpleBudget
//
//  Created by Dionicy Tarantino on 12/2/25.
//

import SwiftUI
import SwiftData
import WidgetKit

// Shared color palette for consistent styling across views
private extension Color {
    static let primaryBlue = Color(red: 0.25, green: 0.55, blue: 1.0)
    static let primaryText = Color(red: 0.12, green: 0.14, blue: 0.2)
    static let secondaryLabel = Color(red: 0.45, green: 0.5, blue: 0.58)
    static let cardBackground = Color(red: 0.96, green: 0.97, blue: 0.99)
    static let pageBackground = Color(red: 0.96, green: 0.97, blue: 0.99)
    static let border = Color(red: 0.88, green: 0.91, blue: 0.96)
}

// MARK: - Cached Global Properties for Efficiency

/// Cached calendar instance to avoid repeated Calendar.current access
private let cachedCalendar = Calendar.current

/// Cached currency code to avoid repeated Locale.current access
private let cachedCurrencyCode = Locale.current.currency?.identifier ?? "USD"

/// Cached currency symbol to avoid repeated Locale.current access
private let cachedCurrencySymbol = Locale.current.currencySymbol ?? "$"

/// Cached number formatter for amount parsing/formatting
private let cachedNumberFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.maximumFractionDigits = 2
    formatter.minimumFractionDigits = 0
    formatter.locale = Locale.current
    formatter.numberStyle = .decimal
    return formatter
}()

// Root tab view orchestrating expense entry, history, and settings
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var settingsCollection: [BudgetSettings]
    @Query(sort: \BudgetCategory.name) private var categoryModels: [BudgetCategory]

    @State private var selectedTab: Tab = .add
    @State private var selectedMonth: Date = .now
    @State private var externalChangeObserver: DarwinNotificationObserver?
    @State private var lastExternalChangeToken: TimeInterval?

    private var settings: BudgetSettings {
        if let settings = settingsCollection.first {
            return settings
        }
        return BudgetSettings.bootstrap(in: modelContext)
    }

    private var categories: [String] {
        ContentView.sanitizedCategories(for: settings, from: categoryModels)
    }

    private func initializeExternalChangeTracking() {
        if lastExternalChangeToken == nil {
            lastExternalChangeToken = CrossProcessNotifier.latestChangeToken()
        }
        startListeningForExternalChanges()
    }

    private func startListeningForExternalChanges() {
        guard externalChangeObserver == nil else { return }

        let observer = DarwinNotificationObserver(name: CrossProcessNotifier.darwinNotificationName) {
            handleExternalChangeSignal()
        }

        externalChangeObserver = observer
        observer.start()
    }

    private func stopListeningForExternalChanges() {
        externalChangeObserver?.stop()
        externalChangeObserver = nil
    }

    private func evaluatePendingExternalChanges() {
        let currentToken = CrossProcessNotifier.latestChangeToken()
        guard currentToken != nil else { return }

        if currentToken != lastExternalChangeToken {
            lastExternalChangeToken = currentToken
            refreshFromExternalChange()
        }
    }

    @MainActor
    private func handleExternalChangeSignal() {
        lastExternalChangeToken = CrossProcessNotifier.latestChangeToken()
        refreshFromExternalChange()
    }

    @MainActor
    private func refreshFromExternalChange() {
        modelContext.rollback()
        _ = try? modelContext.fetch(FetchDescriptor<Transaction>())
        _ = try? modelContext.fetch(FetchDescriptor<BudgetSettings>())
        _ = try? modelContext.fetch(FetchDescriptor<BudgetCategory>())
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
            initializeExternalChangeTracking()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                evaluatePendingExternalChanges()
                startListeningForExternalChanges()
            case .background, .inactive:
                stopListeningForExternalChanges()
            @unknown default:
                break
            }
        }
        .toolbarBackground(.visible, for: .tabBar)
    }

    // Handles adding a new transaction from user input
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
        do {
            try modelContext.save()
        } catch {
            // Consider showing an alert to the user if saving fails.
            print("Failed to save transaction: \(error)")
        }

        BudgetWidgetAmountStore.defaults.set(0, forKey: BudgetWidgetAmountStore.key)
        CrossProcessNotifier.signalDataChange()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // Removes a transaction when confirmed by the user
    private func deleteTransaction(_ transaction: Transaction) {
        withAnimation {
            modelContext.delete(transaction)
            try? modelContext.save()
        }

        WidgetRefreshHelper.reloadAllTimelines()
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
        try? modelContext.save()

        WidgetRefreshHelper.reloadAllTimelines()
    }

    // Deletes a category and cleans up its association with settings
    private func deleteCategory(_ category: BudgetCategory) {
        if var current = settings.categories, let index = current.firstIndex(of: category) {
            current.remove(at: index)
            settings.categories = current
        }
        modelContext.delete(category)
        try? modelContext.save()

        WidgetRefreshHelper.reloadAllTimelines()
    }

    // Updates the monthly budget while preventing negative values
    private func updateBudget(_ newValue: Double) {
        settings.monthlyBudget = max(0, newValue)
        try? modelContext.save()

        WidgetRefreshHelper.reloadAllTimelines()
    }
}

extension ContentView {
    static func sanitizedCategories(for settings: BudgetSettings, from categoryModels: [BudgetCategory]) -> [String] {
        let names = categoryModels
            .filter { $0.settings === settings }
            .map(\.name)

        var seen = Set<String>()
        var unique: [String] = []

        for name in names {
            let key = name.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            unique.append(name)
        }

        return unique.isEmpty ? BudgetSettings.defaultCategories : unique
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
    private enum Field: Hashable { case note}

    private var currentMonthTotal: Double {
        transactions.filter { cachedCalendar.isDate($0.date, equalTo: .now, toGranularity: .month) }
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
                    currencyCode: cachedCurrencyCode,
                    draft: $draft
                )

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Category")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.secondaryLabel)
                            .textCase(.uppercase)

                        CategoryChips(categories: categories, selection: $draft.category)
                        
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

// Card with rounded rectangle perimeter progress bar (matching watch app design)
// Supports drag gesture around the perimeter to adjust amount
private struct ExpenseDialCard: View {
    let remainingBudget: Double
    let monthlyBudget: Double
    let currentSpent: Double
    let currencyCode: String
    @Binding var draft: TransactionDraft

    // Drag gesture state
    @State private var previousAngle: Double?
    @State private var accumulatedRotation: Double = 0  // Total rotation in radians

    // Watch app dimensions: 184x224 points, cornerRadius: 54, lineWidth: 6
    // Using width as base for ratios
    private static let watchWidth: CGFloat = 184
    private static let watchHeight: CGFloat = 224
    private static let watchAspectRatio: CGFloat = watchWidth / watchHeight  // ~0.82
    private let cornerRadiusRatio: CGFloat = 54 / ExpenseDialCard.watchWidth  // ~0.29
    private let lineWidthRatio: CGFloat = 6 / ExpenseDialCard.watchWidth      // ~0.033

    // Computed properties matching watch app
    private var selectedAmount: Double { draft.amount }
    private var projectedRemaining: Double { remainingBudget - selectedAmount }
    private var isOverBudget: Bool { currentSpent >= monthlyBudget }
    private var wouldGoOverBudget: Bool { projectedRemaining < 0 }

    // Amount range for drag - one full rotation = this amount
    private var dialRange: Double {
        let baseRange = max(remainingBudget, 0)
        let overBudgetRange: Double = 500
        return baseRange + overBudgetRange
    }

    private var committedProgress: Double {
        guard monthlyBudget > 0 else { return 0 }
        return min(currentSpent / monthlyBudget, 1.0)
    }

    private var totalProgress: Double {
        guard monthlyBudget > 0 else { return 0 }
        return min((currentSpent + selectedAmount) / monthlyBudget, 1.0)
    }

    // The indicator is ALWAYS at the edge of the pending amount bar
    // When over budget, it keeps moving (wraps every $500 over)
    private var indicatorProgress: Double {
        guard selectedAmount > 0 else { return 0 }

        let totalSpending = currentSpent + selectedAmount

        if totalSpending <= monthlyBudget {
            // Under budget: dot is at the edge of the pending bar
            return totalProgress
        } else {
            // Over budget: dot keeps moving based on amount over
            // Every $500 over = one full rotation around the perimeter
            let overAmount = totalSpending - monthlyBudget
            let wrapAmount: Double = 500
            let progress = (overAmount.truncatingRemainder(dividingBy: wrapAmount)) / wrapAmount
            // If exactly at a multiple of 500, show full (1.0) not zero
            return (progress == 0 && overAmount > 0) ? 1.0 : progress
        }
    }

    var body: some View {
        GeometryReader { geometry in
            // Calculate the frame size maintaining watch aspect ratio
            let availableWidth = geometry.size.width
            let availableHeight = geometry.size.height

            // Use ternary to compute target dimensions based on aspect ratio
            let constrainByHeight = availableWidth / availableHeight > Self.watchAspectRatio
            let targetHeight = constrainByHeight ? availableHeight : availableWidth / Self.watchAspectRatio
            let targetWidth = constrainByHeight ? targetHeight * Self.watchAspectRatio : availableWidth

            // Center the perimeter bar in available space
            let xOffset = (availableWidth - targetWidth) / 2
            let yOffset = (availableHeight - targetHeight) / 2

            // Compute dimensions based on the target width (like watch uses its width)
            let cornerRadius = targetWidth * cornerRadiusRatio
            let lineWidth = max(targetWidth * lineWidthRatio, 6)
            let inset = lineWidth / 2 + 1
            let perimeterRect = CGRect(
                x: inset,
                y: inset,
                width: targetWidth - inset * 2,
                height: targetHeight - inset * 2
            )

            ZStack {
                // Perimeter progress bar (matching watch app ratios)
                AppPerimeterProgressBar(
                    committedProgress: committedProgress,
                    totalProgress: totalProgress,
                    isOverBudget: wouldGoOverBudget || isOverBudget,
                    indicatorProgress: indicatorProgress,
                    cornerRadius: cornerRadius,
                    lineWidth: lineWidth,
                    rect: perimeterRect
                )

                // Center content (matching watch app layout)
                VStack(spacing: 0) {
                    Spacer()

                    // Budget header
                    budgetHeader(fitWidth: targetWidth - lineWidth * 2 - 40)

                    Spacer().frame(height: 12)

                    // Main amount display
                    amountDisplay(fitWidth: targetWidth - lineWidth * 2 - 40)

                    Spacer().frame(height: 16)

                    // Stats row
                    statsRow

                    Spacer().frame(height: 20)

                    // Action buttons (clear only, no increment buttons)
                    actionButtons

                    Spacer()
                }
                .padding(.horizontal, lineWidth + 16)
            }
            .frame(width: targetWidth, height: targetHeight)
            .position(x: availableWidth / 2, y: availableHeight / 2)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Adjust touch location for the offset
                        let adjustedLocation = CGPoint(
                            x: value.location.x - xOffset,
                            y: value.location.y - yOffset
                        )
                        handleDrag(at: adjustedLocation, in: perimeterRect)
                    }
                    .onEnded { _ in
                        endDrag()
                    }
            )
        }
    }

    // MARK: - Drag Gesture Handling

    /// Handles drag gesture - tracks rotation to adjust amount, dot stays at totalProgress
    private func handleDrag(at location: CGPoint, in rect: CGRect) {
        let center = CGPoint(x: rect.midX, y: rect.midY)

        // Calculate current angle from center (in radians)
        let dx = location.x - center.x
        let dy = location.y - center.y
        let currentAngle = atan2(dy, dx)

        if previousAngle == nil {
            // First touch - initialize rotation based on current amount
            previousAngle = currentAngle
            accumulatedRotation = (selectedAmount / dialRange) * 2 * .pi
            return
        }

        guard let prevAngle = previousAngle else { return }

        // Calculate angle delta, handling wrap-around
        var angleDelta = currentAngle - prevAngle

        // Handle wrap-around at ±π boundary
        if angleDelta > .pi {
            angleDelta -= 2 * .pi
        } else if angleDelta < -.pi {
            angleDelta += 2 * .pi
        }

        // Accumulate rotation
        accumulatedRotation += angleDelta
        accumulatedRotation = max(0, accumulatedRotation)  // Don't go negative

        previousAngle = currentAngle

        // Convert accumulated rotation to amount
        let rotations = accumulatedRotation / (2 * .pi)
        let newAmount = rotations * dialRange
        draft.setAmount(max(0, newAmount))
    }

    /// Called when drag ends
    private func endDrag() {
        previousAngle = nil
    }

    // MARK: - View Components (matching watch app)

    private func budgetHeader(fitWidth: CGFloat) -> some View {
        VStack(spacing: 4) {
            Text("MONTHLY BUDGET")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Color.secondaryLabel)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text(monthlyBudget, format: .currency(code: currencyCode))
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(Color.primaryText)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(maxWidth: fitWidth)
    }

    private func amountDisplay(fitWidth: CGFloat) -> some View {
        VStack(spacing: 6) {
            if selectedAmount > 0 {
                Text(selectedAmount, format: .currency(code: currencyCode))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(wouldGoOverBudget ? Color.red : Color.primaryText)
                    .minimumScaleFactor(0.3)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedAmount)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "hand.draw.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.primaryBlue)

                    Text("Drag to add")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.secondaryLabel)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: fitWidth)
    }

    private var statsRow: some View {
        HStack(spacing: 16) {
            StatBadgeView(
                label: "LEFT",
                value: projectedRemaining,
                currencyCode: currencyCode,
                color: wouldGoOverBudget ? .red : Color.primaryBlue
            )

            StatBadgeView(
                label: "SPENT",
                value: currentSpent,
                currencyCode: currencyCode,
                color: Color.secondaryLabel
            )
        }
    }

    private var actionButtons: some View {
        Group {
            if selectedAmount > 0 {
                HStack(spacing: 12) {
                    // Clear button
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            draft.setAmount(0)
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.secondaryLabel)
                            .frame(width: 48, height: 48)
                            .background(
                                Circle()
                                    .fill(Color.border)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Supporting Views for Perimeter Card

private struct StatBadgeView: View {
    let label: String
    let value: Double
    let currencyCode: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(Color.secondaryLabel)

            Text(value, format: .currency(code: currencyCode))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.border)
        )
    }
}

// MARK: - App Perimeter Progress Bar (scaled from watch app ratios)

private struct AppPerimeterProgressBar: View {
    let committedProgress: Double
    let totalProgress: Double
    let isOverBudget: Bool
    let indicatorProgress: Double
    let cornerRadius: CGFloat
    let lineWidth: CGFloat
    let rect: CGRect  // The exact rect where the perimeter is drawn

    // Adjusted corner radius for the stroke center line
    private var adjustedCornerRadius: CGFloat {
        max(cornerRadius - lineWidth / 2, 0)
    }

    var body: some View {
        ZStack {
            // Background track - draw in exact rect coordinates
            AppPerimeterShape(cornerRadius: adjustedCornerRadius, startProgress: 0, endProgress: 1, rect: rect)
                .stroke(
                    Color.primaryBlue.opacity(0.12),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

            // Progress strokes
            if isOverBudget {
                AppPerimeterShape(cornerRadius: adjustedCornerRadius, startProgress: 0, endProgress: 1, rect: rect)
                    .stroke(
                        Color.red,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
            } else {
                // Committed spending (darker blue)
                if committedProgress > 0 {
                    AppPerimeterShape(cornerRadius: adjustedCornerRadius, startProgress: 0, endProgress: min(max(committedProgress, 0), 1), rect: rect)
                        .stroke(
                            Color.primaryBlue,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: committedProgress)
                }

                // Pending spending (lighter blue)
                if totalProgress > committedProgress {
                    AppPerimeterShape(cornerRadius: adjustedCornerRadius, startProgress: committedProgress, endProgress: min(max(totalProgress, 0), 1), rect: rect)
                        .stroke(
                            Color.primaryBlue.opacity(0.4),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: totalProgress)
                }
            }

            // Indicator dot - NO animation so it stays locked to the perimeter
            // (animation would interpolate position in a straight line, not along the path)
            if indicatorProgress > 0 {
                AppPerimeterIndicator(
                    cornerRadius: adjustedCornerRadius,
                    progress: indicatorProgress,
                    rect: rect,
                    dotSize: lineWidth + 4,
                    fillColor: Color.primaryText
                )
            }
        }
    }
}

private struct AppPerimeterIndicator: View {
    let cornerRadius: CGFloat
    let progress: Double
    let rect: CGRect
    let dotSize: CGFloat
    var fillColor: Color = Color.primaryText

    var body: some View {
        Circle()
            .fill(fillColor)
            .frame(width: dotSize, height: dotSize)
            .position(pointOnPerimeter(progress: progress, in: rect, cornerRadius: cornerRadius))
    }

    private func pointOnPerimeter(progress: Double, in rect: CGRect, cornerRadius: CGFloat) -> CGPoint {
        let cr = min(cornerRadius, min(rect.width, rect.height) / 2)
        let straightSections = 2 * (rect.width - 2 * cr) + 2 * (rect.height - 2 * cr)
        let cornerArcs = 2 * .pi * cr
        let totalLength = straightSections + cornerArcs

        let wrappedProgress = progress.truncatingRemainder(dividingBy: 1.0)
        let targetDistance = wrappedProgress * totalLength

        let topHalf = (rect.width - 2 * cr) / 2
        let cornerLength = (.pi / 2) * cr

        var distance = targetDistance

        // Top edge (from center to right)
        if distance <= topHalf {
            return CGPoint(x: rect.midX + distance, y: rect.minY)
        }
        distance -= topHalf

        // Top-right corner
        if distance <= cornerLength {
            let angle = -(.pi / 2) + (distance / cr)
            return CGPoint(
                x: rect.maxX - cr + cr * cos(angle),
                y: rect.minY + cr + cr * sin(angle)
            )
        }
        distance -= cornerLength

        // Right edge
        let rightEdge = rect.height - 2 * cr
        if distance <= rightEdge {
            return CGPoint(x: rect.maxX, y: rect.minY + cr + distance)
        }
        distance -= rightEdge

        // Bottom-right corner
        if distance <= cornerLength {
            let angle: CGFloat = 0 + (distance / cr)
            return CGPoint(
                x: rect.maxX - cr + cr * cos(angle),
                y: rect.maxY - cr + cr * sin(angle)
            )
        }
        distance -= cornerLength

        // Bottom edge
        let bottomEdge = rect.width - 2 * cr
        if distance <= bottomEdge {
            return CGPoint(x: rect.maxX - cr - distance, y: rect.maxY)
        }
        distance -= bottomEdge

        // Bottom-left corner
        if distance <= cornerLength {
            let angle = (.pi / 2) + (distance / cr)
            return CGPoint(
                x: rect.minX + cr + cr * cos(angle),
                y: rect.maxY - cr + cr * sin(angle)
            )
        }
        distance -= cornerLength

        // Left edge
        let leftEdge = rect.height - 2 * cr
        if distance <= leftEdge {
            return CGPoint(x: rect.minX, y: rect.maxY - cr - distance)
        }
        distance -= leftEdge

        // Top-left corner
        if distance <= cornerLength {
            let angle: CGFloat = .pi + (distance / cr)
            return CGPoint(
                x: rect.minX + cr + cr * cos(angle),
                y: rect.minY + cr + cr * sin(angle)
            )
        }
        distance -= cornerLength

        // Back to top center
        return CGPoint(x: rect.minX + cr + distance, y: rect.minY)
    }
}

private struct AppPerimeterShape: Shape {
    let cornerRadius: CGFloat
    var startProgress: Double
    var endProgress: Double
    let rect: CGRect  // Explicit rect to draw in (ignores the rect passed to path)

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(startProgress, endProgress) }
        set {
            startProgress = newValue.first
            endProgress = newValue.second
        }
    }

    func path(in _: CGRect) -> Path {
        // Use our explicit rect, not the one passed by SwiftUI
        let fullPath = createRoundedRectPath(in: rect)
        return fullPath.trimmedPath(from: startProgress, to: endProgress)
    }

    private func createRoundedRectPath(in rect: CGRect) -> Path {
        var path = Path()
        let minDimension = min(rect.width, rect.height)
        let cr = min(cornerRadius, minDimension / 2)

        path.move(to: CGPoint(x: rect.midX, y: rect.minY))

        path.addLine(to: CGPoint(x: rect.maxX - cr, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - cr, y: rect.minY + cr),
            radius: cr,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cr))
        path.addArc(
            center: CGPoint(x: rect.maxX - cr, y: rect.maxY - cr),
            radius: cr,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        path.addLine(to: CGPoint(x: rect.minX + cr, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + cr, y: rect.maxY - cr),
            radius: cr,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cr))
        path.addArc(
            center: CGPoint(x: rect.minX + cr, y: rect.minY + cr),
            radius: cr,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )

        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))

        return path
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
    var title: String = ""
    var note: String = ""

    var amount: Double {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        return cachedNumberFormatter.number(from: trimmed)?.doubleValue ?? 0
    }
    var isValid: Bool { amount > 0 && !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    mutating func setAmount(_ value: Double) {
        amountText = cachedNumberFormatter.string(from: NSNumber(value: max(0, value))) ?? ""
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
        transactions.filter { cachedCalendar.isDate($0.date, equalTo: selectedMonth, toGranularity: .month) }
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
struct MonthSummaryCard: View {
    let month: Date
    let spent: Double
    let limit: Double
    let remaining: Double

    private var progress: Double {
        Self.progress(for: spent, limit: limit)
    }

    static func progress(for spent: Double, limit: Double) -> Double {
        guard limit.isFinite, spent.isFinite, limit > 0 else { return 0 }

        let ratio = spent / limit
        guard ratio.isFinite else { return 0 }

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
                    Text(spent, format: .currency(code: cachedCurrencyCode))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Text("Monthly limit")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                    Text(limit, format: .currency(code: cachedCurrencyCode))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)

                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 72, height: 1)

                    Text(remaining >= 0 ? "Remaining" : "Over")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    Text(abs(remaining), format: .currency(code: cachedCurrencyCode))
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
                    selectedMonth = cachedCalendar.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
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
                    selectedMonth = cachedCalendar.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
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
                Text(transaction.displayTitle)
                    .font(.headline)
                    .lineLimit(1)

                if transaction.hasTitle {
                    Text(transaction.category)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                if transaction.hasNotes {
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

            Text(-transaction.amount, format: .currency(code: cachedCurrencyCode))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color(red: 0.91, green: 0.24, blue: 0.36))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
        )
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

    private var currencySymbol: String { cachedCurrencySymbol }

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
                Text(transaction.displayTitle)
                    .font(.headline)
                if transaction.hasTitle {
                    Text(transaction.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if transaction.hasNotes {
                    Text(transaction.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(-transaction.amount, format: .currency(code: cachedCurrencyCode))
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
