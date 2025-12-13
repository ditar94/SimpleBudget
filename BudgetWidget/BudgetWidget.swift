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

    /// The user's local currency code (e.g., "USD").
    private var currencyCode: String { Locale.current.currency?.identifier ?? "USD" }
    /// The currently selected amount for a new expense, read from AppStorage.
    private var pendingAmount: Double { storedAmount }
    /// The total amount of expenses already recorded for the current month.
    private var committedSpend: Double { max(entry.monthlyBudget - entry.remaining, 0) }
    /// The projected total spend if the pending amount were added as an expense.
    private var totalAfterPending: Double { committedSpend + pendingAmount }
    /// The amount by which the user will be over budget if the pending amount is added. Returns 0 if not over budget.
    private var overBudgetAmount: Double { max(0, totalAfterPending - entry.monthlyBudget) }
    /// The projected remaining budget after subtracting the pending amount.
    private var remainingAfterPending: Double { entry.remaining - pendingAmount }
    /// The spending progress as a fraction (0.0 to 1.0), used for progress bars.
    private var spendingProgress: Double {
        min(max(0, entry.monthlyBudget - entry.remaining) / max(entry.monthlyBudget, 1), 1)
    }
    
    // MARK: - Intents and Actions

    /// Configures the `AddExpenseIntent` with the current pending amount, making it ready for execution.
    private var quickIntent: AddExpenseIntent {
        let intent = entry.quickIntent
        intent.amount = pendingAmount
        return intent
    }

    /// Modifies the stored pending amount by a given delta and reloads widget timelines to reflect the change.
    private func adjustStoredAmount(by delta: Double) {
        storedAmount = max(0, storedAmount + delta)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Main View Body

    /// The main view body, which switches between different layouts based on the widget family.
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

        // Determine the background styling based on the widget family.
        let backgroundColor: AnyView = {
            if family == .systemSmall {
                return AnyView(remainingBackground)
            } else {
                return AnyView(Color.clear)
            }
        }()

        // Apply the appropriate background modifier based on the OS version.
        if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
            content
                .containerBackground(for: .widget) {
                    backgroundColor
                }
        } else {
            content
                .background(backgroundColor)
        }
    }

    // MARK: - Widget Family Layouts

    /// A compact view for the small system-sized widget, showing the remaining budget.
    private var systemSmallView: some View {
        ZStack {
            remainingBackground

            VStack(spacing: 4) {
                Text("Remaining Budget:")
                    .font(.caption)
                Text(entry.remaining, format: .currency(code: currencyCode))
                    .font(.title2.monospacedDigit().weight(.bold))
            }
            .foregroundStyle(remainingForeground)
            .multilineTextAlignment(.center)
            .padding()
        }
    }

    /// A detailed, interactive view for the medium system-sized widget.
    private var systemMediumView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.22), Color.teal.opacity(0.14)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 8) {
                headerRow
                budgetProgressSection
                remainingRow
                controlGrid
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 14)
        }
        .padding(.horizontal, 4)
    }
    
    /// A view for the rectangular accessory widget family (e.g., on the Lock Screen).
    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Budget")
                    .font(.caption.bold())
                Spacer()
                Text(entry.monthlyBudget, format: .currency(code: currencyCode))
                    .font(.caption2)
            }
            ProgressView(value: spendingProgress)
                .progressViewStyle(.linear)
                .animation(.easeOut(duration: 0.12), value: spendingProgress)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    valueRow(title: "Remain", value: entry.remaining, emphasizeNegative: true, compact: true)
                    valueRow(title: "After", value: remainingAfterPending, emphasizeNegative: true, compact: true)
                }
                Spacer()
                adjustmentControls(font: .caption2)
            }
        }
        .padding(.vertical, 6)
    }

    /// A view for the inline accessory widget family, which displays as a line of text.
    private var accessoryInlineView: some View {
        HStack(spacing: 6) {
            Text("After")
            if #available(iOS 17.0, *) {
                Text(remainingAfterPending, format: .currency(code: currencyCode))
                    .foregroundStyle(remainingAfterPending >= 0 ? Color.primary : Color.red)
                    .contentTransition(.numericText(value: remainingAfterPending))
                    .animation(.easeOut(duration: 0.12), value: remainingAfterPending)
            } else {
                Text(remainingAfterPending, format: .currency(code: currencyCode))
                    .foregroundStyle(remainingAfterPending >= 0 ? Color.primary : Color.red)
            }
            adjustmentControls(font: .caption2, showCurrency: false)
        }
        .font(.caption2)
    }

    /// A view for the circular accessory widget family.
    private var accessoryCircularView: some View {
        ZStack {
            Circle()
                .strokeBorder(.quaternary, lineWidth: 4)
            Circle()
                .trim(from: 0, to: spendingProgress)
                .stroke(entry.remaining >= 0 ? Color.blue : Color.red, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.01), value: spendingProgress)

            VStack(spacing: 2) {
                Text("After")
                    .font(.caption2)
                if #available(iOS 17.0, *) {
                    Text(remainingAfterPending, format: .currency(code: currencyCode))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(remainingAfterPending >= 0 ? Color.primary : Color.red)
                        .contentTransition(.numericText(value: remainingAfterPending))
                        .animation(.easeOut(duration: 0.01), value: remainingAfterPending)
                } else {
                    Text(remainingAfterPending, format: .currency(code: currencyCode))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(remainingAfterPending >= 0 ? Color.primary : Color.red)
                }
            }
        }
        .overlay(alignment: .bottom) {
            adjustmentControls(font: .caption2, showCurrency: false)
                .padding(.bottom, 4)
        }
    }
    
    /// A fallback view for unsupported or default widget families.
    private var primaryWidgetView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Budget", systemImage: "creditcard")
                    .font(.headline)
                Spacer()
                Text(entry.monthlyBudget, format: .currency(code: currencyCode))
                    .font(.caption)
            }

            ProgressView(value: spendingProgress)
                .tint(entry.remaining >= 0 ? Color.blue : Color.red)
                .animation(.easeOut(duration: 0.12), value: spendingProgress)

            VStack(alignment: .leading, spacing: 4) {
                valueRow(title: entry.remaining >= 0 ? "Remaining" : "Over", value: entry.remaining, emphasizeNegative: true)
                valueRow(title: "Remaining after", value: remainingAfterPending, emphasizeNegative: true)
            }

            primaryActionRow
        }
        .padding()
    }


    // MARK: - Medium Widget Components

    /// A reusable component for the medium widget's header, showing the "Monthly Budget" title and amount.
    private var headerRow: some View {
        HStack {
            Text("Monthly Budget")
                .font(.subheadline.weight(.semibold))
                .minimumScaleFactor(0.8)
            Spacer()
            Text(entry.monthlyBudget, format: .currency(code: currencyCode))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    /// A reusable component that displays the budget progress bar, indicating committed and pending spending.
    private var budgetProgressSection: some View {
        let budget = max(entry.monthlyBudget, 1)
        let committedRatio = min(committedSpend / budget, 1)
        let totalRatio = min(totalAfterPending / budget, 1)
        let pendingRatio = max(0, totalRatio - committedRatio)
        let isOverBudget = totalAfterPending > entry.monthlyBudget

        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                let availableWidth = proxy.size.width

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))

                    if isOverBudget {
                        Capsule()
                            .fill(Color.red)
                            .frame(width: availableWidth)
                    } else {
                        if committedRatio > 0 {
                            Capsule()
                                .fill(Color.green)
                                .frame(width: availableWidth * committedRatio)
                        }

                        if pendingRatio > 0 {
                            Capsule()
                                .fill(Color.green.opacity(0.45))
                                .frame(width: availableWidth * pendingRatio)
                                .offset(x: availableWidth * committedRatio)
                        }
                    }
                }
                .frame(height: 10)
                .clipShape(Capsule())
            }
            .frame(height: 12)
            .animation(.easeOut(duration: 0.12), value: totalAfterPending)

            HStack(spacing: 8) {
                if isOverBudget {
                    Text("Overbudget by \(overBudgetAmount, format: .currency(code: currencyCode))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.red)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                } else {
                    Text("Committed: \(committedSpend, format: .currency(code: currencyCode))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                    Spacer()
                    Text("Pending: \(pendingAmount, format: .currency(code: currencyCode))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                }
            }
        }
    }

    /// A reusable component showing the final remaining budget after accounting for pending expenses.
    private var remainingRow: some View {
        HStack {
            Text("Remaining Budget:")
                .font(.subheadline.weight(.semibold))
                .minimumScaleFactor(0.9)
            Spacer()
            if #available(iOS 17.0, *) {
                Text(remainingAfterPending, format: .currency(code: currencyCode))
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(remainingAfterPending >= 0 ? Color.primary : Color.red)
                    .contentTransition(.numericText(value: remainingAfterPending))
                    .animation(.easeOut(duration: 0.12), value: remainingAfterPending)
            } else {
                Text(remainingAfterPending, format: .currency(code: currencyCode))
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(remainingAfterPending >= 0 ? Color.primary : Color.red)
            }
        }
    }

    /// The grid of interactive controls for adjusting the pending amount and adding the expense.
    private var controlGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                adjustmentStepperButton(delta: -1, systemImage: "minus.circle.fill")

                VStack(spacing: 2) {
                    Text("Pending amount")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(pendingAmount, format: .currency(code: currencyCode))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Color.blue)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)

                adjustmentStepperButton(delta: 1, systemImage: "plus.circle.fill")
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.12))
            )

            presetIncrementGrid

            HStack(spacing: 8) {
                addButton
                    .buttonStyle(.borderedProminent)
                    .tint(Color.blue)
                    .frame(maxWidth: .infinity)

                clearButton
                    .buttonStyle(.bordered)
                    .tint(Color.teal)
                    .frame(width: 90)
            }
        }
    }

    /// Presents quick increment buttons for common amounts.
    private var presetIncrementGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(presetIncrements, id: \.self) { increment in
                presetIncrementButton(delta: increment)
            }
        }
        .padding(.horizontal, 2)
    }

    /// Supported preset increment values.
    private var presetIncrements: [Double] { [0.05, 0.25, 1, 5, 10, 25] }

    /// A single preset increment button wired to AdjustQuickAmountIntent.
    @ViewBuilder
    private func presetIncrementButton(delta: Double) -> some View {
        let label = Text(delta, format: .currency(code: currencyCode))

        if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
            Button(intent: AdjustQuickAmountIntent(delta: delta)) {
                label
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.blue.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.teal.opacity(0.4), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                adjustStoredAmount(by: delta)
            })
            .accessibilityLabel("Add \(delta, format: .currency(code: currencyCode))")
        } else {
            Button(action: {
                adjustStoredAmount(by: delta)
            }) {
                label
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.blue.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.teal.opacity(0.4), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(delta, format: .currency(code: currencyCode))")
        }
    }
    
    /// The central "Add" button in the medium widget.
    @ViewBuilder
    private var addButton: some View {
        if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
            Button(intent: quickIntent) {
                Label("Add expense", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Text("Requires latest OS for quick add")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }

    /// The secondary clear action displayed alongside the Add button.
    @ViewBuilder
    private var clearButton: some View {
        if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
            Button(intent: ClearQuickAmountIntent()) {
                Label("Clear", systemImage: "arrow.uturn.left")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .simultaneousGesture(TapGesture().onEnded {
                // This provides immediate UI feedback while the intent runs.
                storedAmount = 0
            })
        }
    }

    /// Creates a single button for adjusting the pending amount by a specific delta.
    @ViewBuilder
    private func adjustmentStepperButton(delta: Double, systemImage: String) -> some View {
        let tint = delta > 0 ? Color.blue : Color.teal

        if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
            Button(intent: AdjustQuickAmountIntent(delta: delta)) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(tint.gradient, in: Circle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                adjustStoredAmount(by: delta)
            })
        } else {
            Button(action: {
                adjustStoredAmount(by: delta)
            }) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(tint.gradient, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Reusable UI Components & Helpers

    /// A reusable view component for displaying a titled value, like "Remaining" and its amount.
    private func valueRow(title: String, value: Double, emphasizeNegative: Bool = false, compact: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(.secondary)
            Spacer()
            if #available(iOS 17.0, *) {
                Text(value, format: .currency(code: currencyCode))
                    .font(compact ? .caption.bold() : .headline.weight(.semibold))
                    .foregroundStyle(emphasizeNegative && value < 0 ? Color.red : Color.primary)
                    .contentTransition(.numericText(value: value))
                    .animation(.easeOut(duration: 0.01), value: value)
            } else {
                Text(value, format: .currency(code: currencyCode))
                    .font(compact ? .caption.bold() : .headline.weight(.semibold))
                    .foregroundStyle(emphasizeNegative && value < 0 ? Color.red : Color.primary)
            }
        }
    }

    /// A set of controls for adjusting the pending amount, used in accessory and primary layouts.
    private func adjustmentControls(font: Font, weight: Font.Weight = .regular, spacing: CGFloat = 6, showCurrency: Bool = true) -> some View {
        return HStack(spacing: spacing) {
            Button(intent: AdjustQuickAmountIntent(delta: -adjustmentStep)) {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.plain)

            if showCurrency {
                if #available(iOS 17.0, *) {
                    Text(pendingAmount, format: .currency(code: currencyCode))
                        .font(font.monospacedDigit())
                        .contentTransition(.numericText(value: pendingAmount))
                        .animation(.easeOut(duration: 0.01), value: pendingAmount)
                } else {
                    Text(pendingAmount, format: .currency(code: currencyCode))
                        .font(font.monospacedDigit())
                }
            } else {
                if #available(iOS 17.0, *) {
                    Text(pendingAmount, format: .number.precision(.fractionLength(0)))
                        .font(font.monospacedDigit())
                        .contentTransition(.numericText(value: pendingAmount))
                        .animation(.easeOut(duration: 0.01), value: pendingAmount)
                } else {
                    Text(pendingAmount, format: .number.precision(.fractionLength(0)))
                        .font(font.monospacedDigit())
                }
            }

            Button(intent: AdjustQuickAmountIntent(delta: adjustmentStep)) {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .font(font)
        .fontWeight(weight)
    }

    /// The increment/decrement step value for adjustment controls, which varies by widget family.
    private var adjustmentStep: Double {
        switch family {
        case .accessoryInline, .accessoryCircular:
            return 1
        default:
            return 1
        }
    }

    /// The tinted card background for the widget, which changes based on whether the budget is positive or overspent.
    private var remainingBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(remainingGradient)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .blendMode(.softLight)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(remainingStroke, lineWidth: 1)
            )
    }

    private var remainingGradient: LinearGradient {
        LinearGradient(
            colors: [
                remainingTint.opacity(0.28),
                remainingTint.opacity(0.14)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var remainingStroke: Color {
        Color.white.opacity(0.22)
    }

    private var remainingTint: Color {
        entry.remaining >= 0 ? Color.green : Color.red
    }

    private var remainingForeground: Color {
        Color.white.opacity(0.92)
    }
    
    /// The primary action row for the default widget layout, containing adjustment and add controls.
    @ViewBuilder
    private var primaryActionRow: some View {
        HStack(spacing: 14) {
            adjustmentControls(font: .title2, weight: .semibold, spacing: 10)
            quickAddControl(compact: true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// The button for quickly adding the pending expense amount.
    @ViewBuilder
    private func quickAddControl(compact: Bool = false) -> some View {
        if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
            Button(intent: quickIntent) {
                Label("Add", systemImage: "plus")
                    .font(compact ? .body.weight(.semibold) : nil)
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: compact ? nil : .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(compact ? .small : .regular)
            .simultaneousGesture(TapGesture().onEnded {
                // Reset the pending amount after adding an expense so the selector returns to 0.
                storedAmount = 0
                WidgetCenter.shared.reloadAllTimelines()
            })
        } else {
            Text("Requires latest OS for quick add")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: compact ? nil : .infinity)
        }
    }
}

// MARK: - Widget Preview

#Preview(as: .systemMedium) {
    BudgetWidget()
} timeline: {
    BudgetEntry(date: .now, remaining: 300, monthlyBudget: 300, quickIntent: AddExpenseIntent())
}
