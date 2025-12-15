import SwiftUI
import SwiftData
import WatchKit

/// Main budget overview screen with Digital Crown-controlled amount input.
/// Fast scrolling = dollar increments, slow/precise scrolling = cent increments.
struct BudgetOverviewView: View {
    let settings: BudgetSettings
    let categories: [String]
    let onAddTransaction: (Double, String) -> Void

    @Query private var transactions: [Transaction]

    @State private var selectedAmount: Double = 0
    @State private var showingCategoryPicker = false
    @FocusState private var isCrownFocused: Bool

    // Crown velocity tracking for adaptive step sizes
    @State private var crownValue: Double = 0
    @State private var lastCrownValue: Double = 0
    @State private var lastCrownTime: Date = .now

    private let calendar = Calendar.current
    private let currencyCode = Locale.current.currency?.identifier ?? "USD"

    // Velocity thresholds for step size selection (lower = more responsive)
    private let fastScrollThreshold: Double = 8.0   // rotations per second
    private let mediumScrollThreshold: Double = 3.0

    // MARK: - Computed Properties

    private var currentMonthTransactions: [Transaction] {
        transactions.filter {
            calendar.isDate($0.date, equalTo: .now, toGranularity: .month)
        }
    }

    private var monthlySpent: Double {
        currentMonthTransactions.reduce(0) { $0 + $1.amount }
    }

    private var remainingBudget: Double {
        settings.monthlyBudget - monthlySpent
    }

    private var isOverBudget: Bool {
        remainingBudget <= 0
    }

    private var wouldGoOverBudget: Bool {
        projectedRemaining < 0
    }

    /// Base progress showing committed spending (what's already spent)
    private var baseProgress: Double {
        guard settings.monthlyBudget > 0 else { return 0 }
        return min(monthlySpent / settings.monthlyBudget, 1.0)
    }

    /// Ring progress showing total spending (committed + pending selection)
    private var ringProgress: Double {
        if wouldGoOverBudget || isOverBudget {
            return 1.0
        }
        guard settings.monthlyBudget > 0 else { return 1.0 }
        return min((monthlySpent + selectedAmount) / settings.monthlyBudget, 1.0)
    }

    /// Indicator shows where pending amount would land on the progress bar
    private var indicatorProgress: Double {
        // Only show indicator when user is entering an amount
        guard selectedAmount > 0 else { return 0 }
        if wouldGoOverBudget {
            let overAmount = (monthlySpent + selectedAmount) - settings.monthlyBudget
            let progress = overAmount.truncatingRemainder(dividingBy: 500) / 500
            return progress == 0 && overAmount > 0 ? 1.0 : progress
        } else {
            return ringProgress
        }
    }

    private var projectedRemaining: Double {
        remainingBudget - selectedAmount
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Ambient background gradient
                backgroundGradient

                // Perimeter progress bar
                PerimeterProgressBar(
                    committedProgress: baseProgress,
                    totalProgress: ringProgress,
                    isOverBudget: wouldGoOverBudget || isOverBudget,
                    indicatorProgress: indicatorProgress
                )

                // Glass content card
                VStack(spacing: 0) {
                    Spacer()

                    // Budget header
                    budgetHeader

                    Spacer().frame(height: 6)

                    // Main amount display
                    amountDisplay

                    Spacer().frame(height: 8)

                    // Stats row
                    statsRow

                    Spacer().frame(height: 10)

                    // Action buttons
                    actionButtons

                    Spacer()
                }
                .padding(.horizontal, 12)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .focusable()
        .focused($isCrownFocused)
        .digitalCrownRotation(
            detent: $crownValue,
            from: -100000,
            through: 100000,
            by: 1.0,
            sensitivity: .medium,
            isContinuous: true,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownValue) { oldValue, newValue in
            handleCrownRotation(oldValue: oldValue, newValue: newValue)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedAmount)
        .sheet(isPresented: $showingCategoryPicker) {
            CategoryPickerView(categories: categories) { selectedCategory in
                onAddTransaction(selectedAmount, selectedCategory)
                selectedAmount = 0
                crownValue = 0
                showingCategoryPicker = false
                WKInterfaceDevice.current().play(.success)
            }
        }
        .onAppear {
            isCrownFocused = true
        }
    }

    // MARK: - Crown Handling

    private func handleCrownRotation(oldValue: Double, newValue: Double) {
        let now = Date()
        let timeDelta = now.timeIntervalSince(lastCrownTime)
        let valueDelta = newValue - lastCrownValue

        // Calculate velocity (detents per second)
        let velocity = timeDelta > 0 ? abs(valueDelta / timeDelta) : 0

        // Determine step size based on velocity
        let stepSize: Double
        if velocity > fastScrollThreshold {
            // Fast scrolling: $5.00 increments
            stepSize = 5.0
        } else if velocity > mediumScrollThreshold {
            // Medium scrolling: $1.00 increments
            stepSize = 1.0
        } else {
            // Slow/precise scrolling: $0.05 increments
            stepSize = 0.05
        }

        // Calculate direction and apply step
        let direction = (newValue - oldValue) > 0 ? 1.0 : -1.0
        let newAmount = selectedAmount + (direction * stepSize)

        // Clamp to valid range
        selectedAmount = max(0, min(newAmount, 10000))

        // Update tracking
        lastCrownValue = newValue
        lastCrownTime = now
    }

    // MARK: - View Components

    // Color palette matching main app exactly
    private static let primaryBlue = Color(red: 0.25, green: 0.55, blue: 1.0)
    private static let primaryText = Color(red: 0.12, green: 0.14, blue: 0.2)
    private static let secondaryLabel = Color(red: 0.45, green: 0.5, blue: 0.58)
    private static let pageBackground = Color(red: 0.96, green: 0.97, blue: 0.99)
    private static let border = Color(red: 0.88, green: 0.91, blue: 0.96)
    private static let negativeTint = Color.red

    private var backgroundGradient: some View {
        // Light background matching main app
        Self.pageBackground
    }

    private var stateColor: Color {
        if wouldGoOverBudget || isOverBudget {
            return Self.negativeTint
        } else {
            return Self.primaryBlue
        }
    }

    private var budgetHeader: some View {
        VStack(spacing: 2) {
            Text("MONTHLY BUDGET")
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Self.secondaryLabel)

            Text(settings.monthlyBudget, format: .currency(code: currencyCode))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Self.primaryText)
        }
    }

    private var amountDisplay: some View {
        VStack(spacing: 4) {
            if selectedAmount > 0 {
                // Selected amount (no glow)
                Text(selectedAmount, format: .currency(code: currencyCode))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(wouldGoOverBudget ? Self.negativeTint : Self.primaryText)
                    .contentTransition(.numericText())
            } else {
                // Prompt to scroll
                VStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Self.primaryBlue)

                    Text("Scroll to add")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Self.secondaryLabel)
                }
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            // Remaining
            StatBadge(
                label: "LEFT",
                value: projectedRemaining,
                currencyCode: currencyCode,
                color: wouldGoOverBudget ? Self.negativeTint : Self.primaryBlue,
                backgroundColor: Self.border
            )

            // Spent
            StatBadge(
                label: "SPENT",
                value: monthlySpent,
                currencyCode: currencyCode,
                color: Self.secondaryLabel,
                backgroundColor: Self.border
            )
        }
    }

    private var actionButtons: some View {
        Group {
            if selectedAmount > 0 {
                HStack(spacing: 10) {
                    // Clear button
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedAmount = 0
                            crownValue = 0
                        }
                        WKInterfaceDevice.current().play(.click)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Self.secondaryLabel)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(Self.border)
                            )
                    }
                    .buttonStyle(.plain)

                    // Add button
                    Button {
                        showingCategoryPicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                            Text("Add")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Self.primaryBlue)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct StatBadge: View {
    let label: String
    let value: Double
    let currencyCode: String
    let color: Color
    var backgroundColor: Color = Color(red: 0.88, green: 0.91, blue: 0.96)

    private static let secondaryLabel = Color(red: 0.45, green: 0.5, blue: 0.58)

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 7, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(Self.secondaryLabel)

            Text(value, format: .currency(code: currencyCode))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(backgroundColor)
        )
    }
}
