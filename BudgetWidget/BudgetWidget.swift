import SwiftUI
import WidgetKit
import SwiftData
import AppIntents

// MARK: - Widget Data Structures

/// Defines the data for a single point in the widget's timeline.
/// It includes the current budget status and the configured App Intent for adding an expense.
struct BudgetEntry: TimelineEntry {
    /// The date and time for this timeline entry.
    let date: Date
    /// The remaining budget amount for the current month.
    let remaining: Double
    /// The total monthly budget configured by the user.
    let monthlyBudget: Double
    /// The pre-configured intent for adding a new expense, used by interactive buttons.
    let quickIntent: AddExpenseIntent
}

// MARK: - Widget Timeline Logic

/// Manages the widget's timeline, providing data to the widget view at different points in time.
/// It fetches budget data from the shared SwiftData container to build timeline entries.
struct BudgetWidgetProvider: AppIntentTimelineProvider {
    typealias Entry = BudgetEntry
    typealias Intent = AddExpenseIntent

    /// Provides a generic, placeholder view for the widget, used in contexts like the widget gallery.
    func placeholder(in context: Context) -> BudgetEntry {
        BudgetEntry(date: .now, remaining: 1500, monthlyBudget: 2000, quickIntent: AddExpenseIntent())
    }

    /// Provides a snapshot of the widget's current state for transient displays.
    func snapshot(for configuration: Intent, in context: Context) async -> BudgetEntry {
        BudgetEntry(date: .now, remaining: 1500, monthlyBudget: 2000, quickIntent: configuration)
    }

    /// Creates a timeline of entries, determining when the widget should be updated.
    /// This function fetches the current budget settings and transactions from SwiftData to calculate the remaining budget.
    func timeline(for configuration: Intent, in context: Context) async -> Timeline<BudgetEntry> {
        // Access the shared SwiftData container.
        let container = WidgetModelContainer.shared
        let modelContext = ModelContext(container)

        let currentMonthTotal: Double
        let settings: BudgetSettings

        // Fetch settings and calculate total expenses for the current month.
        if let fetchedSettings = try? modelContext.fetch(FetchDescriptor<BudgetSettings>()).first {
            settings = fetchedSettings
            let transactions = (try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? []
            currentMonthTotal = transactions
                .filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month) }
                .reduce(0) { $0 + $1.amount }
        } else {
            // Use default values if no data is available.
            settings = BudgetSettings()
            currentMonthTotal = 0
        }

        // Calculate the remaining budget.
        let remaining = settings.monthlyBudget - currentMonthTotal
        let now = Date()
        let currentEntry = BudgetEntry(
            date: now,
            remaining: remaining,
            monthlyBudget: settings.monthlyBudget,
            quickIntent: configuration
        )

        // Create a short-lived timeline to ensure the widget updates frequently to reflect new expenses.
        let refreshDate = now.addingTimeInterval(30)
        return Timeline(entries: [currentEntry], policy: .after(refreshDate))
    }
}

// MARK: - Widget Definition

/// The main definition of the budget widget.
/// It specifies the widget's kind, configuration, display name, description, and supported families.
struct BudgetWidget: Widget {
    let kind: String = "BudgetWidget"

    /// Configures the widget, linking it to the App Intent and timeline provider.
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: AddExpenseIntent.self, provider: BudgetWidgetProvider()) { entry in
            BudgetWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Expense")
        .description("Add expenses from your lock screen or Home Screen.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular, .systemSmall, .systemMedium])
    }
}

// MARK: - Main Widget View

/// The primary SwiftUI view that renders the widget's content based on the provided entry and widget family.
struct BudgetWidgetView: View {
    // MARK: - State and Environment
    
    /// The timeline entry containing the data to display.
    let entry: BudgetEntry
    /// The size and style of the widget (e.g., .systemSmall, .accessoryCircular), provided by the environment.
    @Environment(\.widgetFamily) private var family

    /// The pending expense amount, stored in UserDefaults to persist between widget updates.
    @AppStorage(BudgetWidgetAmountStore.key, store: BudgetWidgetAmountStore.defaults)
    private var storedAmount: Double = BudgetWidgetAmountStore.defaultAmount

    init(entry: BudgetEntry) {
        self.entry = entry
    }

    // MARK: - Calculated Properties

    private var currencyCode: String { Locale.current.currency?.identifier ?? "USD" }
    private var pendingAmount: Double { storedAmount }
    private var committedSpend: Double { max(entry.monthlyBudget - entry.remaining, 0) }
    private var totalAfterPending: Double { committedSpend + pendingAmount }
    private var overBudgetAmount: Double { max(0, totalAfterPending - entry.monthlyBudget) }
    private var remainingAfterPending: Double { entry.remaining - pendingAmount }
    private var spendingProgress: Double {
        min(max(0, entry.monthlyBudget - entry.remaining) / max(entry.monthlyBudget, 1), 1)
    }
    
    // MARK: - Intents and Actions

    private var quickIntent: AddExpenseIntent {
        let intent = entry.quickIntent
        intent.amount = pendingAmount
        return intent
    }

    private func adjustStoredAmount(by delta: Double) {
        storedAmount = max(0, storedAmount + delta)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Main View Body

    var body: some View {
        let content = Group {
            switch family {
            case .accessoryInline:
                accessoryInlineView
            case .accessoryCircular:
                accessoryCircularView
            case .accessoryRectangular:
                accessoryRectangularView
            case .systemSmall:
                systemSmallView
            case .systemMedium:
                systemMediumView
            default:
                primaryWidgetView
            }
        }
        
        let background = glassBackground.frame(maxWidth: .infinity, maxHeight: .infinity)

        if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
            content
                .containerBackground(for: .widget) {
                    if family.isSystemFamily {
                        background
                    } else {
                        Color.clear
                    }
                }
        } else {
            content
                .background {
                    if family.isSystemFamily {
                        background
                    } else {
                        Color.clear
                    }
                }
        }
    }

    // MARK: - Widget Family Layouts

    private var systemSmallView: some View {
        VStack(spacing: 6) {
            Text("Remaining")
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(.white.opacity(0.8))

            Text(entry.remaining, format: .currency(code: currencyCode))
                .font(.system(.title, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
        }
        .padding()
    }

    private var systemMediumView: some View {
        HStack(alignment: .top, spacing: 10) {
            // Left column: summary
            VStack(alignment: .center, spacing: 6) {
                headerRowCompact
                budgetProgressSectionCompact
                remainingRowCompact
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            // Right column: controls
            VStack(spacing: 6) {
                amountAdjustmentRow
                presetIncrementGridCompact
                addClearRowCompact
                Spacer(minLength: 0)
            }
            .frame(width: 165)
        }
        .padding(8)
    }
    
    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Budget Remaining")
                .font(.caption.bold())
            ProgressView(value: spendingProgress)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: spendingProgress)

            HStack {
                valueRow(title: "After", value: remainingAfterPending, emphasizeNegative: true, compact: true)
                Spacer()
                adjustmentControls(font: .caption2)
            }
        }
        .padding(.vertical, 6)
    }

    private var accessoryInlineView: some View {
        HStack(spacing: 6) {
            Text("After:")
            if #available(iOS 17.0, *) {
                Text(remainingAfterPending, format: .currency(code: currencyCode))
                    .foregroundStyle(remainingAfterPending >= 0 ? Color.primary : Color.red)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.2, dampingFraction: 0.8), value: remainingAfterPending)
            } else {
                Text(remainingAfterPending, format: .currency(code: currencyCode))
                    .foregroundStyle(remainingAfterPending >= 0 ? Color.primary : Color.red)
            }
            adjustmentControls(font: .caption2, showCurrency: false)
        }
    }

    private var accessoryCircularView: some View {
        ZStack {
            Circle().strokeBorder(.primary.opacity(0.2), lineWidth: 5)
            Circle()
                .trim(from: 0, to: spendingProgress)
                .stroke(entry.remaining >= 0 ? Color.blue : Color.red, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: spendingProgress)
            
            VStack(spacing: 0) {
                Text("After")
                    .font(.caption2)
                if #available(iOS 17.0, *) {
                    Text(remainingAfterPending, format: .currency(code: currencyCode))
                        .font(.system(size: 11, design: .rounded).monospacedDigit().weight(.medium))
                        .foregroundStyle(remainingAfterPending >= 0 ? Color.primary : Color.red)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: remainingAfterPending)
                } else {
                    Text(remainingAfterPending, format: .currency(code: currencyCode))
                        .font(.system(size: 11, design: .rounded).monospacedDigit().weight(.medium))
                        .foregroundStyle(remainingAfterPending >= 0 ? Color.primary : Color.red)
                }
            }
        }
    }
    
    private var primaryWidgetView: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            budgetProgressSection
            remainingRow
            Spacer()
            primaryActionRow
        }
        .padding()
    }

    // MARK: - Medium Widget Components

    private var headerRow: some View {
        HStack {
            Text("Monthly Budget")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
            Spacer()
            Text(entry.monthlyBudget, format: .currency(code: currencyCode))
                .font(.system(.caption, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
    }

    private var budgetProgressSection: some View {
        let budget = max(entry.monthlyBudget, 1)
        let committedRatio = min(committedSpend / budget, 1)
        let totalRatio = min(totalAfterPending / budget, 1)
        let pendingRatio = max(0, totalRatio - committedRatio)
        let isOverBudget = totalAfterPending > entry.monthlyBudget

        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let availableWidth = proxy.size.width
                let committedWidth = availableWidth * committedRatio
                let pendingWidth = availableWidth * pendingRatio
                
                ZStack(alignment: .leading) {
                    Capsule().fill(.black.opacity(0.2))
                    
                    if isOverBudget {
                        Capsule().fill(Theme.negativeGradient)
                    } else {
                        Capsule()
                            .fill(Theme.positiveGradient)
                            .frame(width: committedWidth)
                        
                        Capsule()
                            .fill(Theme.positiveGradient.opacity(0.5))
                            .frame(width: pendingWidth)
                            .offset(x: committedWidth)
                    }
                }
                .frame(height: 12)
            }
            .frame(height: 12)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: totalAfterPending)

            HStack(spacing: 8) {
                let font = Font.system(.caption2, design: .rounded).weight(.medium)
                if isOverBudget {
                    Text("Over by \(overBudgetAmount, format: .currency(code: currencyCode))")
                        .font(font)
                        .foregroundStyle(Theme.negativeTint)
                        .lineLimit(1)
                } else {
                    Text("Spent: \(committedSpend, format: .currency(code: currencyCode))")
                        .font(font)
                    Spacer()
                    Text("Pending: \(pendingAmount, format: .currency(code: currencyCode))")
                        .font(font)
                }
            }
            .foregroundStyle(.white.opacity(0.8))
        }
    }

    private var remainingRow: some View {
        HStack {
            Text("Remaining:")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
            Spacer()
            if #available(iOS 17.0, *) {
                Text(remainingAfterPending, format: .currency(code: currencyCode))
                    .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(remainingAfterPending >= 0 ? .white : Theme.negativeTint)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: remainingAfterPending)
            } else {
                Text(remainingAfterPending, format: .currency(code: currencyCode))
                    .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(remainingAfterPending >= 0 ? .white : Theme.negativeTint)
            }
        }
        .foregroundStyle(.white)
    }

    private var controlGrid: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                adjustmentStepperButton(delta: -1, systemImage: "minus")
                
                Text(pendingAmount, format: .currency(code: currencyCode))
                    .font(.system(.headline, design: .rounded).weight(.bold).monospacedDigit())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                
                adjustmentStepperButton(delta: 1, systemImage: "plus")
            }
            
            presetIncrementGrid
            
            HStack(spacing: 8) {
                addButton
                clearButton
            }
        }
        .foregroundStyle(.white)
    }

    private var presetIncrementGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach([1.0, 5.0, 10.0, 25.0], id: \.self) { presetIncrementButton(delta: $0) }
        }
    }
    
    @ViewBuilder private func presetIncrementButton(delta: Double) -> some View {
        let label = Text(delta, format: .currency(code: currencyCode).precision(.fractionLength(0...2)))
        let intent = AdjustQuickAmountIntent(delta: delta)

        if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
            Button(intent: intent) { label }
            .buttonStyle(GlassTileButtonStyle())
            .simultaneousGesture(TapGesture().onEnded { adjustStoredAmount(by: delta) })
        } else {
            Button(action: { adjustStoredAmount(by: delta) }) { label }
            .buttonStyle(GlassTileButtonStyle())
        }
    }
    
    @ViewBuilder private var addButton: some View {
        if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
            Button(intent: quickIntent) {
                Label("Add Expense", systemImage: "plus")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassButtonStyle(tint: .blue))
            .simultaneousGesture(TapGesture().onEnded { storedAmount = 0 })
        }
    }

    @ViewBuilder private var clearButton: some View {
        if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
            Button(intent: ClearQuickAmountIntent()) {
                Label("Clear", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
            }
            .buttonStyle(GlassButtonStyle(tint: .gray))
            .simultaneousGesture(TapGesture().onEnded { storedAmount = 0 })
        }
    }

    @ViewBuilder private func adjustmentStepperButton(delta: Double, systemImage: String) -> some View {
        let intent = AdjustQuickAmountIntent(delta: delta)
        let label = Image(systemName: systemImage)
            .font(.system(.body, design: .rounded).weight(.bold))
        
        if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
            Button(intent: intent) { label }
                .buttonStyle(GlassCircleButtonStyle(tint: .gray))
                .simultaneousGesture(TapGesture().onEnded { adjustStoredAmount(by: delta) })
        } else {
            Button(action: { adjustStoredAmount(by: delta) }) { label }
                .buttonStyle(GlassCircleButtonStyle(tint: .gray))
        }
    }

    // MARK: - Reusable UI Components & Helpers

    private func valueRow(title: String, value: Double, emphasizeNegative: Bool = false, compact: Bool = false) -> some View {
        HStack {
            Text(title).font(compact ? .caption2 : .caption)
            Spacer()
            let font = compact ? Font.caption.bold() : Font.headline.weight(.semibold)
            let color = emphasizeNegative && value < 0 ? Color.red : Color.primary
            
            if #available(iOS 17.0, *) {
                Text(value, format: .currency(code: currencyCode))
                    .font(font).foregroundStyle(color)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.2, dampingFraction: 0.8), value: value)
            } else {
                Text(value, format: .currency(code: currencyCode))
                    .font(font).foregroundStyle(color)
            }
        }
    }

    private func adjustmentControls(font: Font, weight: Font.Weight = .regular, spacing: CGFloat = 6, showCurrency: Bool = true) -> some View {
        HStack(spacing: spacing) {
            Button(intent: AdjustQuickAmountIntent(delta: -adjustmentStep)) { Image(systemName: "minus.circle.fill") }
            
            let amountText = showCurrency
                ? Text(pendingAmount, format: .currency(code: currencyCode))
                .font(font.monospacedDigit())
                : Text(pendingAmount, format: .number.precision(.fractionLength(0)))
                .font(font.monospacedDigit())
            
            if #available(iOS 17.0, *) {
                amountText.contentTransition(.numericText())
                    .animation(.spring(response: 0.2, dampingFraction: 0.8), value: pendingAmount)
            } else {
                amountText
            }

            Button(intent: AdjustQuickAmountIntent(delta: adjustmentStep)) { Image(systemName: "plus.circle.fill") }
        }
        .buttonStyle(.plain)
        .font(font.weight(weight))
    }

    private var adjustmentStep: Double { family.isAccessoryFamily ? 1 : 5 }

    // MARK: - Glass Background & Theme

    private var glassBackground: some View {
        ZStack {
            // Base aurora effect
            Theme.backgroundGradient.opacity(0.8)
            
            // Blurred shapes for depth
            Circle()
                .fill(Theme.positiveTint.opacity(0.3))
                .frame(width: 200, height: 200)
                .offset(x: -100, y: -80)
                .blur(radius: 80)
            
            Circle()
                .fill(Theme.accentTint.opacity(0.4))
                .frame(width: 150, height: 150)
                .offset(x: 100, y: 50)
                .blur(radius: 60)
            
            // Material layer for the "glass" effect
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(.ultraThinMaterial)
            
            // Border
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(Theme.strokeGradient, lineWidth: 1.5)
        }
        .blendMode(.plusLighter) // Using blendMode can be heavy, but creates nice effects
        .background(Theme.backgroundGradient)
        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
    }

    @ViewBuilder private var primaryActionRow: some View {
        HStack(spacing: 14) {
            adjustmentControls(font: .title2, weight: .semibold, spacing: 10)
            quickAddControl()
        }
    }

    @ViewBuilder private func quickAddControl() -> some View {
        if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
            Button(intent: quickIntent) {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(GlassButtonStyle(tint: .blue))
            .simultaneousGesture(TapGesture().onEnded { storedAmount = 0 })
        }
    }
}

// MARK: - Medium Widget Compact Components
extension BudgetWidgetView {
    private var headerRowCompact: some View {
        VStack(spacing: 6) {
            Text("Monthly Budget")
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            //Spacer()
            Text(entry.monthlyBudget, format: .currency(code: currencyCode))
                .font(.system(.caption2, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
    }

    private var budgetProgressSectionCompact: some View {
        let budget = max(entry.monthlyBudget, 1)
        let committed = max(entry.monthlyBudget - entry.remaining, 0)
        let total = committed + pendingAmount
        let committedRatio = min(committed / budget, 1)
        let totalRatio = min(total / budget, 1)
        let pendingRatio = max(0, totalRatio - committedRatio)
        let isOverBudget = total > entry.monthlyBudget

        return VStack(alignment: .center, spacing: 4) {
            GeometryReader { proxy in
                let availableWidth = proxy.size.width
                let barHeight: CGFloat = 8
                let committedWidth = availableWidth * committedRatio
                let pendingWidth = availableWidth * pendingRatio

                ZStack(alignment: .leading) {
                    Capsule().fill(.black.opacity(0.2))
                    if isOverBudget {
                        Capsule().fill(Theme.negativeGradient)
                    } else {
                        Capsule()
                            .fill(Theme.positiveGradient)
                            .frame(width: committedWidth)
                        Capsule()
                            .fill(Theme.positiveGradient.opacity(0.5))
                            .frame(width: pendingWidth)
                            .offset(x: committedWidth)
                    }
                }
                .frame(height: barHeight)
            }
            .frame(height: 8)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: total)

            VStack(spacing: 6) {
                let font = Font.system(.caption2, design: .rounded).weight(.medium)
                if isOverBudget {
                    Text("Over by \(max(0, total - entry.monthlyBudget), format: .currency(code: currencyCode))")
                        .font(font)
                        .foregroundStyle(Theme.negativeTint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    Text("Spent: \(committed, format: .currency(code: currencyCode))")
                        .font(font)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                   // Spacer(minLength: 4)
                    Text("Pending: \(pendingAmount, format: .currency(code: currencyCode))")
                        .font(font)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .foregroundStyle(.white.opacity(0.8))
        }
    }

    private var remainingRowCompact: some View {
        VStack(spacing: 6) {
            Text("Remaining:")
                .font(.system(.footnote, design: .rounded).weight(.semibold))
            //Spacer()
            if #available(iOS 17.0, *) {
                Text(remainingAfterPending, format: .currency(code: currencyCode))
                    .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(remainingAfterPending >= 0 ? .white : Theme.negativeTint)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: remainingAfterPending)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text(remainingAfterPending, format: .currency(code: currencyCode))
                    .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(remainingAfterPending >= 0 ? .white : Theme.negativeTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .foregroundStyle(.white)
    }

    private var amountAdjustmentRow: some View {
        HStack(spacing: 4) {
            VStack {
                centAdjustmentButton(delta: -0.05, tint: Theme.negativeTint)
                centAdjustmentButton(delta: -0.25, tint: Theme.negativeTint)
                
            }

            Text(pendingAmount, format: .currency(code: currencyCode))
                .font(.system(.footnote, design: .rounded).weight(.bold).monospacedDigit())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            VStack {
                centAdjustmentButton(delta: 0.05, tint: Theme.positiveTint)
                centAdjustmentButton(delta: 0.25, tint: Theme.positiveTint)
            }
        }
        .foregroundStyle(.white)
    }

    private var presetIncrementGridCompact: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 2)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach([1.0, 5.0, 10.0, 25.0], id: \.self) { presetIncrementButtonCompact(delta: $0) }
        }
    }

    @ViewBuilder private func presetIncrementButtonCompact(delta: Double) -> some View {
        let label = Text(delta, format: .currency(code: currencyCode).precision(.fractionLength(0...2)))
            .font(.system(.caption2, design: .rounded).weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        let intent = AdjustQuickAmountIntent(delta: delta)

        if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
            Button(intent: intent) { label }
                .buttonStyle(GlassTileButtonStyleCompact())
                .simultaneousGesture(TapGesture().onEnded { adjustStoredAmount(by: delta) })
        } else {
            Button(action: { adjustStoredAmount(by: delta) }) { label }
                .buttonStyle(GlassTileButtonStyleCompact())
        }
    }

    @ViewBuilder private func centAdjustmentButton(delta: Double, tint: Color) -> some View {
        let intent = AdjustQuickAmountIntent(delta: delta)
        let cents = Int(abs(delta * 100))
        let label = Text("\(cents)¢")

        if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
            Button(intent: intent) { label }
                .buttonStyle(SmallGlassPillButtonStyle(tint: tint))
                .simultaneousGesture(TapGesture().onEnded { adjustStoredAmount(by: delta) })
        } else {
            Button(action: { adjustStoredAmount(by: delta) }) { label }
                .buttonStyle(SmallGlassPillButtonStyle(tint: tint))
        }
    }

    @ViewBuilder private var addClearRowCompact: some View {
        HStack(spacing: 6) {
            if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
                Button(intent: quickIntent) {
                    Label("Add", systemImage: "plus")
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyleCompact(tint: .blue))
                .simultaneousGesture(TapGesture().onEnded { storedAmount = 0 })

                Button(intent: ClearQuickAmountIntent()) {
                    Label("Clear", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                }
                .buttonStyle(GlassButtonStyleCompact(tint: .gray))
                .simultaneousGesture(TapGesture().onEnded { storedAmount = 0 })
            }
        }
    }
}
// MARK: - UI Theme & Styles

fileprivate enum Theme {
    static let accentTint = Color(red: 0.5, green: 0.2, blue: 1.0)
    static let positiveTint = Color.red
    static let negativeTint = Color(red: 1.0, green: 0.3, blue: 0.3)
    
    static let backgroundGradient = LinearGradient(
        colors: [Color(red: 0.1, green: 0.0, blue: 0.3), Color(red: 0.3, green: 0.1, blue: 0.4)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let positiveGradient = LinearGradient(
        colors: [.cyan, .green], startPoint: .leading, endPoint: .trailing
    )
    static let negativeGradient = LinearGradient(
        colors: [.orange, .red], startPoint: .leading, endPoint: .trailing
    )
    static let strokeGradient = LinearGradient(
        colors: [.white.opacity(0.4), .white.opacity(0.1)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

fileprivate struct GlassButtonStyle: ButtonStyle {
    var tint: Color = .accentColor
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 8)
            .frame(minWidth: 44)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tint.opacity(configuration.isPressed ? 0.5 : 0.3))
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(tint, lineWidth: 1)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

fileprivate struct GlassCircleButtonStyle: ButtonStyle {
    var tint: Color = .gray

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 36, height: 36)
            .background(
                Circle()
                    .fill(tint.opacity(configuration.isPressed ? 0.4 : 0.2))
                    .overlay(Circle().stroke(tint.opacity(0.5), lineWidth: 1))
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

fileprivate struct GlassTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.black.opacity(configuration.isPressed ? 0.3 : 0.15))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

fileprivate struct GlassButtonStyleCompact: ButtonStyle {
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 6)
            .frame(minWidth: 36)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.opacity(configuration.isPressed ? 0.5 : 0.3))
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(tint, lineWidth: 1)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

fileprivate struct GlassCircleButtonStyleCompact: ButtonStyle {
    var tint: Color = .gray

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 28, height: 28)
            .background(
                Circle()
                    .fill(tint.opacity(configuration.isPressed ? 0.4 : 0.2))
                    .overlay(Circle().stroke(tint.opacity(0.5), lineWidth: 1))
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

fileprivate struct GlassTileButtonStyleCompact: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.caption2, design: .rounded).weight(.semibold))
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.black.opacity(configuration.isPressed ? 0.3 : 0.15))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

fileprivate struct SmallGlassPillButtonStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.caption2, design: .rounded).weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .background(
                Capsule()
                    .fill(tint.opacity(configuration.isPressed ? 0.5 : 0.3))
                    .overlay(Capsule().stroke(tint.opacity(0.5), lineWidth: 1))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

fileprivate extension WidgetFamily {
    var isSystemFamily: Bool {
        #if os(iOS) || os(macOS)
        switch self {
        case .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge:
            return true
        default:
            return false
        }
        #else
        return false
        #endif
    }
    
    var isAccessoryFamily: Bool {
        #if os(iOS) || os(watchOS)
        switch self {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            return true
        default:
            return false
        }
        #else
        return false
        #endif
    }
}


// MARK: - Widget Preview

#Preview(as: .systemSmall) {
    BudgetWidget()
} timeline: {
    
    BudgetEntry(date: .now, remaining: 1250.75, monthlyBudget: 2000, quickIntent: AddExpenseIntent())
    BudgetEntry(date: .now, remaining: -250.00, monthlyBudget: 2000, quickIntent: AddExpenseIntent())
}
