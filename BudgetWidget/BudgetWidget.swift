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

    /// Cached calendar instance for efficient date operations
    private static let calendar = Calendar.current

    /// Creates a timeline of entries, determining when the widget should be updated.
    /// This function fetches the current budget settings and transactions from SwiftData to calculate the remaining budget.
    func timeline(for configuration: Intent, in context: Context) async -> Timeline<BudgetEntry> {
        // Access the shared SwiftData container.
        let container = WidgetModelContainer.shared
        let modelContext = ModelContext(container)

        let currentMonthTotal: Double
        let settings: BudgetSettings

        // Calculate start of current month for predicate filtering
        let now = Date()
        let startOfMonth = Self.calendar.date(from: Self.calendar.dateComponents([.year, .month], from: now))!

        // Fetch settings with limit for efficiency
        var settingsDescriptor = FetchDescriptor<BudgetSettings>()
        settingsDescriptor.fetchLimit = 1

        if let fetchedSettings = try? modelContext.fetch(settingsDescriptor).first {
            settings = fetchedSettings

            // Use predicate to filter transactions at database level (much more efficient)
            let predicate = #Predicate<Transaction> { transaction in
                transaction.date >= startOfMonth
            }
            var transactionDescriptor = FetchDescriptor<Transaction>(predicate: predicate)
            transactionDescriptor.propertiesToFetch = [\.amount]

            let transactions = (try? modelContext.fetch(transactionDescriptor)) ?? []
            currentMonthTotal = transactions.reduce(0) { $0 + $1.amount }
        } else {
            // Use default values if no data is available.
            settings = BudgetSettings()
            currentMonthTotal = 0
        }

        // Calculate the remaining budget.
        let remaining = settings.monthlyBudget - currentMonthTotal
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
        .contentMarginsDisabled()
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
    /// The widget rendering mode (fullColor, accented/tinted, vibrant/clear)
    @Environment(\.widgetRenderingMode) private var renderingMode
    /// The current color scheme (light or dark mode)
    @Environment(\.colorScheme) private var colorScheme

    /// The pending expense amount, stored in UserDefaults to persist between widget updates.
    @AppStorage(BudgetWidgetAmountStore.key, store: BudgetWidgetAmountStore.defaults)
    private var storedAmount: Double = BudgetWidgetAmountStore.defaultAmount

    init(entry: BudgetEntry) {
        self.entry = entry
    }

    // MARK: - Adaptive Colors for Rendering Modes

    /// Whether we're in tinted or clear mode (not full color)
    private var isVibrantMode: Bool {
        if #available(iOS 17.0, *) {
            return renderingMode != .fullColor
        }
        return false
    }

    /// Whether we're in dark mode (only relevant for fullColor mode)
    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    // MARK: - Unified Glass Background (same translucent style for all modes)

    /// Background color for watch area and UI elements - same translucent style in all modes
    /// This creates the frosted glass appearance consistently
    private var glassOverlayBackground: Color {
        Color.white.opacity(0.15)
    }

    // MARK: Watch Content Colors (text and accent colors differ by mode)

    /// Primary text in watch area - vibrant colors in fullColor, white in tinted
    private var watchPrimaryText: Color {
        if isVibrantMode {
            return .white
        } else if isDarkMode {
            return .white
        } else {
            return Theme.primaryText
        }
    }

    /// Secondary text in watch area
    private var watchSecondaryText: Color {
        if isVibrantMode {
            return .white.opacity(0.7)
        } else if isDarkMode {
            return .white.opacity(0.6)
        } else {
            return Theme.secondaryLabel
        }
    }

    /// Accent color in watch area - vibrant blue in fullColor, white in tinted
    private var watchAccent: Color {
        if isVibrantMode {
            return .white
        } else {
            return Theme.primaryBlue
        }
    }

    // MARK: Input Controls Colors (right side of medium widget)

    /// Primary text color for input controls
    private var adaptivePrimaryText: Color {
        if isVibrantMode {
            return .white
        } else if isDarkMode {
            return .white
        } else {
            return Theme.primaryText
        }
    }

    /// Secondary text color for input controls
    private var adaptiveSecondaryText: Color {
        if isVibrantMode {
            return .white.opacity(0.7)
        } else if isDarkMode {
            return .white.opacity(0.6)
        } else {
            return Theme.secondaryLabel
        }
    }

    /// Accent color for input controls - vibrant in fullColor, white in tinted
    private var adaptiveAccent: Color {
        if isVibrantMode {
            return .white
        } else {
            return Theme.primaryBlue
        }
    }

    // MARK: - Cached Static Properties

    /// Cached currency code to avoid repeated Locale.current access
    private static let currencyCode: String = Locale.current.currency?.identifier ?? "USD"

    // MARK: - Calculated Properties

    private var currencyCode: String { Self.currencyCode }
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
        widgetContent
            .modifier(GlassBackgroundModifier())
    }

    @ViewBuilder
    private var widgetContent: some View {
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
}

// MARK: - Glass Background Modifier for Widgets

private struct GlassBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // iOS 26+: Use glassEffect for liquid glass appearance
            content
                .widgetAccentable()
                .containerBackground(for: .widget) {
                    Color.clear.glassEffect()
                }
        } else if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
            // iOS 17-25: Use translucent overlay for glass-like effect
            // Note: True "Clear" mode is user-controlled via Home Screen customization
            content
                .widgetAccentable()
                .containerBackground(for: .widget) {
                    Color.white.opacity(0.15)
                }
        } else {
            content
        }
    }
}

// MARK: - BudgetWidgetView Extension for remaining properties
extension BudgetWidgetView {

    // MARK: - Widget Family Layouts

    // Watch app dimensions for maintaining aspect ratio
    private static let watchWidth: CGFloat = 184
    private static let watchHeight: CGFloat = 224
    private static let watchAspectRatio: CGFloat = watchWidth / watchHeight  // ~0.82

    private func watchScaledSize(for geometry: GeometryProxy) -> CGSize {
        let availableWidth = geometry.size.width
        let availableHeight = geometry.size.height
        if availableWidth / availableHeight > Self.watchAspectRatio {
            let targetHeight = availableHeight
            let targetWidth = targetHeight * Self.watchAspectRatio
            return CGSize(width: targetWidth, height: targetHeight)
        } else {
            let targetWidth = availableWidth
            let targetHeight = targetWidth / Self.watchAspectRatio
            return CGSize(width: targetWidth, height: targetHeight)
        }
    }

    private var systemSmallView: some View {
        GeometryReader { geometry in
            let targetSize = watchScaledSize(for: geometry)

            ZStack {
                // Background for watch-ratio content area - unified translucent glass
                RoundedRectangle(cornerRadius: targetSize.height * 0.27)
                    .fill(glassOverlayBackground)
                    .frame(width: targetSize.width, height: targetSize.height)

                // Perimeter progress bar
                WidgetEdgePerimeterProgressBar(
                    committedProgress: spendingProgress,
                    totalProgress: min(totalAfterPending / max(entry.monthlyBudget, 1), 1),
                    isOverBudget: totalAfterPending > entry.monthlyBudget,
                    isVibrantMode: isVibrantMode
                )
                .frame(width: targetSize.width, height: targetSize.height)

                // Content inside
                VStack(alignment: .center, spacing: 4) {
                    // Budget header
                    Text("MONTHLY BUDGET")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .tracking(1.0)
                        .foregroundStyle(watchSecondaryText)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)

                    Text(entry.monthlyBudget, format: .currency(code: currencyCode))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(watchPrimaryText)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)

                    Spacer().frame(height: 4)

                    // Amount display
                    if pendingAmount > 0 {
                        Text(pendingAmount, format: .currency(code: currencyCode))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(totalAfterPending > entry.monthlyBudget ? Theme.negativeTint : watchPrimaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.3)
                    } else {
                        VStack(spacing: 2) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(watchAccent)

                            Text("Tap to add")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(watchSecondaryText)
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                        }
                    }

                    Spacer().frame(height: 4)

                    // Stats row
                    HStack(spacing: 8) {
                        WidgetStatBadge(
                            label: "LEFT",
                            value: remainingAfterPending,
                            currencyCode: currencyCode,
                            color: remainingAfterPending < 0 ? Theme.negativeTint : watchAccent,
                            compact: true,
                            isVibrantMode: isVibrantMode,
                            isDarkMode: isDarkMode
                        )

                        WidgetStatBadge(
                            label: "SPENT",
                            value: committedSpend,
                            currencyCode: currencyCode,
                            color: watchSecondaryText,
                            compact: true,
                            isVibrantMode: isVibrantMode,
                            isDarkMode: isDarkMode
                        )
                    }
                }
                .frame(width: targetSize.width, height: targetSize.height)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private var systemMediumView: some View {
        HStack(alignment: .center, spacing: 8) {
            // Left column: watch face floating on glass (identical to small widget)
            GeometryReader { geometry in
                let targetSize = watchScaledSize(for: geometry)

                ZStack {
                    // Background for watch-ratio content area - unified translucent glass
                    RoundedRectangle(cornerRadius: targetSize.height * 0.27)
                        .fill(glassOverlayBackground)
                        .frame(width: targetSize.width, height: targetSize.height)

                    // Perimeter progress bar
                    WidgetEdgePerimeterProgressBar(
                        committedProgress: spendingProgress,
                        totalProgress: min(totalAfterPending / max(entry.monthlyBudget, 1), 1),
                        isOverBudget: totalAfterPending > entry.monthlyBudget,
                        isVibrantMode: isVibrantMode
                    )
                    .frame(width: targetSize.width, height: targetSize.height)

                    // Content inside
                    VStack(alignment: .center, spacing: 4) {
                        // Budget header
                        Text("MONTHLY BUDGET")
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .tracking(1.0)
                            .foregroundStyle(watchSecondaryText)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)

                        Text(entry.monthlyBudget, format: .currency(code: currencyCode))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(watchPrimaryText)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)

                        Spacer().frame(height: 4)

                        // Amount display
                        if pendingAmount > 0 {
                            Text(pendingAmount, format: .currency(code: currencyCode))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(totalAfterPending > entry.monthlyBudget ? Theme.negativeTint : watchPrimaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.3)
                        } else {
                            VStack(spacing: 2) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(watchAccent)

                                Text("Tap to add")
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundStyle(watchSecondaryText)
                                    .minimumScaleFactor(0.5)
                                    .lineLimit(1)
                            }
                        }

                        Spacer().frame(height: 4)

                        // Stats row
                        HStack(spacing: 8) {
                            WidgetStatBadge(
                                label: "LEFT",
                                value: remainingAfterPending,
                                currencyCode: currencyCode,
                                color: remainingAfterPending < 0 ? Theme.negativeTint : watchAccent,
                                compact: true,
                                isVibrantMode: isVibrantMode,
                                isDarkMode: isDarkMode
                            )

                            WidgetStatBadge(
                                label: "SPENT",
                                value: committedSpend,
                                currencyCode: currencyCode,
                                color: watchSecondaryText,
                                compact: true,
                                isVibrantMode: isVibrantMode,
                                isDarkMode: isDarkMode
                            )
                        }
                    }
                    .frame(width: targetSize.width, height: targetSize.height)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .frame(maxWidth: .infinity)

            // Right column: controls (on glass - adapts to tinted/clear modes)
            VStack(spacing: 6) {
                amountAdjustmentRowAdaptive
                presetIncrementGridCompactAdaptive
                addClearRowCompactAdaptive
            }
            .frame(width: 170)
            .padding(10)
        }
    }

    private var leftColumnContent: some View {
        VStack(alignment: .center, spacing: 0) {
            // Budget header (matching watch)
            Text("MONTHLY BUDGET")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(Theme.secondaryLabel)

            Text(entry.monthlyBudget, format: .currency(code: currencyCode))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.primaryText)

            Spacer().frame(height: 8)

            // Amount display (matching watch)
            if pendingAmount > 0 {
                if #available(iOS 17.0, *) {
                    Text(pendingAmount, format: .currency(code: currencyCode))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(totalAfterPending > entry.monthlyBudget ? Theme.negativeTint : Theme.primaryText)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: pendingAmount)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                } else {
                    Text(pendingAmount, format: .currency(code: currencyCode))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(totalAfterPending > entry.monthlyBudget ? Theme.negativeTint : Theme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.primaryBlue)

                    Text("Tap to add")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }

            Spacer().frame(height: 8)

            // Stats row (matching watch)
            HStack(spacing: 10) {
                WidgetStatBadge(
                    label: "LEFT",
                    value: remainingAfterPending,
                    currencyCode: currencyCode,
                    color: remainingAfterPending < 0 ? Theme.negativeTint : Theme.primaryBlue,
                    compact: false,
                    isDarkMode: isDarkMode
                )

                WidgetStatBadge(
                    label: "SPENT",
                    value: committedSpend,
                    currencyCode: currencyCode,
                    color: Theme.secondaryLabel,
                    compact: false,
                    isDarkMode: isDarkMode
                )
            }
        }
    }

    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Budget Remaining")
                .font(.caption.bold())
            ProgressView(value: spendingProgress)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: spendingProgress)

            HStack {
                valueRow(title: "", value: entry.remaining, emphasizeNegative: true, compact: true)
//                Spacer()
//                adjustmentControls(font: .caption2)
            }
        }
        .padding(.vertical, 6)
    }

    private var accessoryInlineView: some View {
        HStack(spacing: 6) {
            Text("Remaining:")
            if #available(iOS 17.0, *) {
                Text(entry.remaining, format: .currency(code: currencyCode))
                    .foregroundStyle(entry.remaining >= 0 ? Color.primary : Color.red)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.2, dampingFraction: 0.8), value: entry.remaining)
            } else {
                Text(entry.remaining, format: .currency(code: currencyCode))
                    .foregroundStyle(entry.remaining >= 0 ? Color.primary : Color.red)
            }
            //adjustmentControls(font: .caption2, showCurrency: false)
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
                Text("Budget")
                    .font(.caption2)
                if #available(iOS 17.0, *) {
                    Text(entry.remaining, format: .currency(code: currencyCode))
                        .font(.system(size: 7, design: .rounded).monospacedDigit().weight(.medium))
                        .foregroundStyle(entry.remaining >= 0 ? Color.primary : Color.red)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: entry.remaining)
                } else {
                    Text(entry.remaining, format: .currency(code: currencyCode))
                        .font(.system(size: 7, design: .rounded).monospacedDigit().weight(.medium))
                        .foregroundStyle(entry.remaining >= 0 ? Color.primary : Color.red)
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
                .foregroundStyle(Theme.primaryText)
            Spacer()
            Text(entry.monthlyBudget, format: .currency(code: currencyCode))
                .font(.system(.caption, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.secondaryLabel)
        }
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
                    // Track background matching main app
                    Capsule().fill(Theme.primaryBlue.opacity(0.12))

                    if isOverBudget {
                        Capsule().fill(Theme.negativeGradient)
                    } else {
                        Capsule()
                            .fill(Theme.positiveGradient)
                            .frame(width: committedWidth)

                        Capsule()
                            .fill(Theme.primaryBlue.opacity(0.3))
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
            .foregroundStyle(Theme.secondaryLabel)
        }
    }

    private var remainingRow: some View {
        HStack {
            Text("Remaining:")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            Spacer()
            if #available(iOS 17.0, *) {
                Text(remainingAfterPending, format: .currency(code: currencyCode))
                    .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(remainingAfterPending >= 0 ? Theme.primaryText : Theme.negativeTint)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: remainingAfterPending)
            } else {
                Text(remainingAfterPending, format: .currency(code: currencyCode))
                    .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(remainingAfterPending >= 0 ? Theme.primaryText : Theme.negativeTint)
            }
        }
    }

    private var controlGrid: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                adjustmentStepperButton(delta: -1, systemImage: "minus")

                Text(pendingAmount, format: .currency(code: currencyCode))
                    .font(.system(.headline, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Theme.border, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                adjustmentStepperButton(delta: 1, systemImage: "plus")
            }

            presetIncrementGrid

            HStack(spacing: 8) {
                addButton
                clearButton
            }
        }
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
        }
    }

    @ViewBuilder private func adjustmentStepperButton(delta: Double, systemImage: String) -> some View {
        let intent = AdjustQuickAmountIntent(delta: delta)
        let label = Image(systemName: systemImage)
            .font(.system(.body, design: .rounded).weight(.bold))
        
        if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
            Button(intent: intent) { label }
                .buttonStyle(GlassCircleButtonStyle(tint: .gray))
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
        }
    }
}

// MARK: - Medium Widget Compact Components
extension BudgetWidgetView {
    private var headerRowCompact: some View {
        VStack(spacing: 6) {
            Text("Monthly Budget")
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(entry.monthlyBudget, format: .currency(code: currencyCode))
                .font(.system(.caption2, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.secondaryLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
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
                    Capsule().fill(Theme.primaryBlue.opacity(0.12))
                    if isOverBudget {
                        Capsule().fill(Theme.negativeGradient)
                    } else {
                        Capsule()
                            .fill(Theme.positiveGradient)
                            .frame(width: committedWidth)
                        Capsule()
                            .fill(Theme.primaryBlue.opacity(0.3))
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
                    Text("Pending: \(pendingAmount, format: .currency(code: currencyCode))")
                        .font(font)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .foregroundStyle(Theme.secondaryLabel)
        }
    }

    private var remainingRowCompact: some View {
        VStack(spacing: 6) {
            Text("Remaining:")
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            if #available(iOS 17.0, *) {
                Text(remainingAfterPending, format: .currency(code: currencyCode))
                    .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(remainingAfterPending >= 0 ? Theme.primaryText : Theme.negativeTint)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: remainingAfterPending)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text(remainingAfterPending, format: .currency(code: currencyCode))
                    .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(remainingAfterPending >= 0 ? Theme.primaryText : Theme.negativeTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private var amountAdjustmentRow: some View {
        HStack(spacing: 4) {
            VStack {
                centAdjustmentButton(delta: -0.05, tint: Theme.secondaryLabel)
                centAdjustmentButton(delta: -0.25, tint: Theme.secondaryLabel)
            }

            Text(pendingAmount, format: .currency(code: currencyCode))
                .font(.system(.footnote, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            VStack {
                centAdjustmentButton(delta: 0.05, tint: Theme.primaryBlue)
                centAdjustmentButton(delta: 0.25, tint: Theme.primaryBlue)
            }
        }
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

                Button(intent: ClearQuickAmountIntent()) {
                    Label("Clear", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                }
                .buttonStyle(GlassButtonStyleCompact(tint: .gray))
            }
        }
    }

    // MARK: - Adaptive Control Rows (for vibrant/tinted modes)

    private var amountAdjustmentRowAdaptive: some View {
        HStack(spacing: 4) {
            VStack {
                centAdjustmentButtonAdaptive(delta: -0.05)
                centAdjustmentButtonAdaptive(delta: -0.25)
            }

            Text(pendingAmount, format: .currency(code: currencyCode))
                .font(.system(.footnote, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(adaptivePrimaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.2))
                )
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            VStack {
                centAdjustmentButtonAdaptive(delta: 0.05)
                centAdjustmentButtonAdaptive(delta: 0.25)
            }
        }
    }

    private var presetIncrementGridCompactAdaptive: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 2)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach([1.0, 5.0, 10.0, 25.0], id: \.self) { presetIncrementButtonCompactAdaptive(delta: $0) }
        }
    }

    @ViewBuilder private func presetIncrementButtonCompactAdaptive(delta: Double) -> some View {
        let label = Text(delta, format: .currency(code: currencyCode).precision(.fractionLength(0...2)))
            .font(.system(.caption2, design: .rounded).weight(.semibold))
            .foregroundStyle(adaptivePrimaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        let intent = AdjustQuickAmountIntent(delta: delta)

        if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
            Button(intent: intent) { label }
                .buttonStyle(AdaptiveGlassTileButtonStyle(isVibrantMode: isVibrantMode, isDarkMode: isDarkMode))
        } else {
            Button(action: { adjustStoredAmount(by: delta) }) { label }
                .buttonStyle(AdaptiveGlassTileButtonStyle(isVibrantMode: isVibrantMode, isDarkMode: isDarkMode))
        }
    }

    @ViewBuilder private func centAdjustmentButtonAdaptive(delta: Double) -> some View {
        let intent = AdjustQuickAmountIntent(delta: delta)
        let cents = Int(abs(delta * 100))
        let tint = delta < 0 ? adaptiveSecondaryText : adaptiveAccent
        let label = Text("\(cents)¢")

        if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
            Button(intent: intent) { label }
                .buttonStyle(AdaptiveSmallGlassPillButtonStyle(tint: tint, isVibrantMode: isVibrantMode, isDarkMode: isDarkMode))
        } else {
            Button(action: { adjustStoredAmount(by: delta) }) { label }
                .buttonStyle(AdaptiveSmallGlassPillButtonStyle(tint: tint, isVibrantMode: isVibrantMode, isDarkMode: isDarkMode))
        }
    }

    @ViewBuilder private var addClearRowCompactAdaptive: some View {
        HStack(spacing: 6) {
            if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
                Button(intent: quickIntent) {
                    Label("Add", systemImage: "plus")
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AdaptiveGlassButtonStyleCompact(tint: isVibrantMode ? .white : .blue, isVibrantMode: isVibrantMode, isDarkMode: isDarkMode))

                Button(intent: ClearQuickAmountIntent()) {
                    Label("Clear", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                }
                .buttonStyle(AdaptiveGlassButtonStyleCompact(tint: isVibrantMode ? .white.opacity(0.7) : .gray, isVibrantMode: isVibrantMode, isDarkMode: isDarkMode))
            }
        }
    }
}
// MARK: - UI Theme & Styles (matching main app)

fileprivate enum Theme {
    // Main app color palette
    static let primaryBlue = Color(red: 0.25, green: 0.55, blue: 1.0)
    static let primaryText = Color(red: 0.12, green: 0.14, blue: 0.2)
    static let secondaryLabel = Color(red: 0.45, green: 0.5, blue: 0.58)
    static let pageBackground = Color(red: 0.96, green: 0.97, blue: 0.99)
    static let cardBackground = Color(red: 0.96, green: 0.97, blue: 0.99)
    static let border = Color(red: 0.88, green: 0.91, blue: 0.96)
    static let negativeTint = Color.red

    // Unified with main app
    static let accentTint = primaryBlue
    static let positiveTint = primaryBlue

    // Light background like main app
    static let backgroundGradient = LinearGradient(
        colors: [pageBackground, pageBackground],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    // Progress bar gradient matching main app's dial
    static let positiveGradient = LinearGradient(
        colors: [primaryBlue.opacity(0.5), primaryBlue], startPoint: .leading, endPoint: .trailing
    )
    static let negativeGradient = LinearGradient(
        colors: [Color.red.opacity(0.8), Color.red], startPoint: .leading, endPoint: .trailing
    )
    static let strokeGradient = LinearGradient(
        colors: [border, border],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

// MARK: - Widget Stat Badge (matching watch app)

fileprivate struct WidgetStatBadge: View {
    let label: String
    let value: Double
    let currencyCode: String
    let color: Color
    var compact: Bool = false
    var isVibrantMode: Bool = false
    var isDarkMode: Bool = false

    private var labelColor: Color {
        if isVibrantMode {
            return .white.opacity(0.7)
        } else if isDarkMode {
            return .white.opacity(0.6)
        } else {
            return Theme.secondaryLabel
        }
    }

    var body: some View {
        VStack(spacing: compact ? 2 : 3) {
            Text(label)
                .font(.system(size: compact ? 7 : 8, weight: .semibold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(labelColor)

            Text(value, format: .currency(code: currencyCode))
                .font(.system(size: compact ? 10 : 12, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, compact ? 6 : 10)
        .padding(.vertical, compact ? 5 : 7)
        .background(
            RoundedRectangle(cornerRadius: compact ? 8 : 10)
                .fill(Color.white.opacity(0.15))
        )
    }
}

fileprivate struct GlassButtonStyle: ButtonStyle {
    var tint: Color = Theme.primaryBlue

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.vertical, 8)
            .frame(minWidth: 44)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.8 : 1.0))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

fileprivate struct GlassCircleButtonStyle: ButtonStyle {
    var tint: Color = Theme.secondaryLabel

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.primaryText)
            .frame(width: 36, height: 36)
            .background(
                Circle()
                    .fill(Theme.border)
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

fileprivate struct GlassTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(Theme.primaryText)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.border)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

fileprivate struct GlassButtonStyleCompact: ButtonStyle {
    var tint: Color = Theme.primaryBlue

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.vertical, 6)
            .frame(minWidth: 36)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.8 : 1.0))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

fileprivate struct GlassCircleButtonStyleCompact: ButtonStyle {
    var tint: Color = Theme.secondaryLabel

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.primaryText)
            .frame(width: 28, height: 28)
            .background(
                Circle()
                    .fill(Theme.border)
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

fileprivate struct GlassTileButtonStyleCompact: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.caption2, design: .rounded).weight(.semibold))
            .foregroundStyle(Theme.primaryText)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.8))
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
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.7))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Adaptive Button Styles (unified glass background for all modes)

fileprivate struct AdaptiveGlassTileButtonStyle: ButtonStyle {
    var isVibrantMode: Bool = false
    var isDarkMode: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.2))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

fileprivate struct AdaptiveSmallGlassPillButtonStyle: ButtonStyle {
    var tint: Color
    var isVibrantMode: Bool = false
    var isDarkMode: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.caption2, design: .rounded).weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.2))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

fileprivate struct AdaptiveGlassButtonStyleCompact: ButtonStyle {
    var tint: Color
    var isVibrantMode: Bool = false
    var isDarkMode: Bool = false

    private var foregroundColor: Color {
        if isVibrantMode {
            return tint
        } else {
            return .white
        }
    }

    private var backgroundColor: Color {
        if isVibrantMode {
            return Color.white.opacity(0.25)
        } else {
            return tint.opacity(0.8)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foregroundColor)
            .padding(.vertical, 6)
            .frame(minWidth: 36)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundColor.opacity(configuration.isPressed ? 0.7 : 1.0))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

// MARK: - Widget Perimeter Progress Bar

/// A perimeter progress bar that hugs the edge of the widget (like watch app)
/// Uses watch app ratios: cornerRadius = 27% of size, lineWidth = 3% of size
fileprivate struct WidgetEdgePerimeterProgressBar: View {
    let committedProgress: Double  // Already spent (darker blue)
    let totalProgress: Double       // Total including pending
    let isOverBudget: Bool
    var isVibrantMode: Bool = false

    // Watch app ratio constants (cornerRadius: 54, lineWidth: 6 on ~200pt watch)
    private let cornerRadiusRatio: CGFloat = 0.27  // 54/200
    private let lineWidthRatio: CGFloat = 0.03     // 6/200

    // Always use original colors - we'll use widgetAccentable(false) to preserve them
    private var trackColor: Color {
        Theme.primaryBlue.opacity(0.12)
    }

    private var progressColor: Color {
        isOverBudget ? Theme.negativeTint : Theme.primaryBlue
    }

    private var pendingColor: Color {
        Theme.primaryBlue.opacity(0.4)
    }

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let cornerRadius = size * cornerRadiusRatio
            let lineWidth = max(size * lineWidthRatio, 4) // minimum 4pt for visibility
            let inset = lineWidth / 2
            let adjustedRadius = cornerRadius - inset

            ZStack {
                // Background track hugging edge
                RoundedRectangle(cornerRadius: adjustedRadius)
                    .inset(by: inset)
                    .stroke(
                        trackColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )

                // Progress fill
                if isOverBudget {
                    RoundedRectangle(cornerRadius: adjustedRadius)
                        .inset(by: inset)
                        .stroke(
                            Theme.negativeTint,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                } else {
                    // Committed spending (blue)
                    if committedProgress > 0 {
                        WidgetEdgePerimeterShape(
                            cornerRadius: adjustedRadius,
                            startProgress: 0,
                            endProgress: min(max(committedProgress, 0), 1),
                            inset: inset
                        )
                        .stroke(
                            progressColor,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: committedProgress)
                    }

                    // Pending spending (lighter blue)
                    if totalProgress > committedProgress {
                        WidgetEdgePerimeterShape(
                            cornerRadius: adjustedRadius,
                            startProgress: committedProgress,
                            endProgress: min(max(totalProgress, 0), 1),
                            inset: inset
                        )
                        .stroke(
                            pendingColor,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: totalProgress)
                    }
                }
            }
            .widgetAccentable(false) // Preserve original colors in tinted/clear modes
        }
    }
}

/// Shape for edge-hugging perimeter progress with inset support
fileprivate struct WidgetEdgePerimeterShape: Shape {
    let cornerRadius: CGFloat
    var startProgress: Double
    var endProgress: Double
    let inset: CGFloat

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(startProgress, endProgress) }
        set {
            startProgress = newValue.first
            endProgress = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: inset, dy: inset)
        let fullPath = createRoundedRectPath(in: insetRect)
        return fullPath.trimmedPath(from: startProgress, to: endProgress)
    }

    private func createRoundedRectPath(in rect: CGRect) -> Path {
        var path = Path()
        let cr = min(cornerRadius, min(rect.width, rect.height) / 2)

        // Start at top center
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))

        // Top edge to top-right corner
        path.addLine(to: CGPoint(x: rect.maxX - cr, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - cr, y: rect.minY + cr),
            radius: cr,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )

        // Right edge to bottom-right corner
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cr))
        path.addArc(
            center: CGPoint(x: rect.maxX - cr, y: rect.maxY - cr),
            radius: cr,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        // Bottom edge to bottom-left corner
        path.addLine(to: CGPoint(x: rect.minX + cr, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + cr, y: rect.maxY - cr),
            radius: cr,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        // Left edge to top-left corner
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cr))
        path.addArc(
            center: CGPoint(x: rect.minX + cr, y: rect.minY + cr),
            radius: cr,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )

        // Back to top center
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))

        return path
    }
}

/// A perimeter progress bar that wraps around a rectangular area (with more padding)
/// Uses watch app ratios: cornerRadius = 27% of size, lineWidth = 3% of size
fileprivate struct WidgetPerimeterProgressBar: View {
    let committedProgress: Double  // Already spent (darker blue)
    let totalProgress: Double       // Total including pending
    let isOverBudget: Bool

    // Watch app ratio constants (cornerRadius: 54, lineWidth: 6 on ~200pt watch)
    private let cornerRadiusRatio: CGFloat = 0.27  // 54/200
    private let lineWidthRatio: CGFloat = 0.03     // 6/200

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let cornerRadius = size * cornerRadiusRatio
            let lineWidth = max(size * lineWidthRatio, 3) // minimum 3pt for visibility

            ZStack {
                // Background track
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        Theme.primaryBlue.opacity(0.12),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )

                // Progress fill
                if isOverBudget {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            Theme.negativeTint,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                } else {
                    // Committed spending (darker blue)
                    if committedProgress > 0 {
                        WidgetPerimeterShape(cornerRadius: cornerRadius, startProgress: 0, endProgress: min(max(committedProgress, 0), 1))
                            .stroke(
                                Theme.primaryBlue,
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                            )
                            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: committedProgress)
                    }

                    // Pending spending (lighter blue)
                    if totalProgress > committedProgress {
                        WidgetPerimeterShape(cornerRadius: cornerRadius, startProgress: committedProgress, endProgress: min(max(totalProgress, 0), 1))
                            .stroke(
                                Theme.primaryBlue.opacity(0.4),
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                            )
                            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: totalProgress)
                    }
                }
            }
        }
    }
}

/// Shape that traces a rounded rectangle perimeter for progress indication
fileprivate struct WidgetPerimeterShape: Shape {
    let cornerRadius: CGFloat
    var startProgress: Double
    var endProgress: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(startProgress, endProgress) }
        set {
            startProgress = newValue.first
            endProgress = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let fullPath = createRoundedRectPath(in: rect)
        return fullPath.trimmedPath(from: startProgress, to: endProgress)
    }

    private func createRoundedRectPath(in rect: CGRect) -> Path {
        var path = Path()
        let cr = min(cornerRadius, min(rect.width, rect.height) / 2)

        // Start at top center
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))

        // Top edge to top-right corner
        path.addLine(to: CGPoint(x: rect.maxX - cr, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - cr, y: rect.minY + cr),
            radius: cr,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )

        // Right edge to bottom-right corner
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cr))
        path.addArc(
            center: CGPoint(x: rect.maxX - cr, y: rect.maxY - cr),
            radius: cr,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        // Bottom edge to bottom-left corner
        path.addLine(to: CGPoint(x: rect.minX + cr, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + cr, y: rect.maxY - cr),
            radius: cr,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        // Left edge to top-left corner
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cr))
        path.addArc(
            center: CGPoint(x: rect.minX + cr, y: rect.minY + cr),
            radius: cr,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )

        // Back to top center
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))

        return path
    }
}


// MARK: - Widget Preview

#Preview(as: .systemMedium) {
    BudgetWidget()
} timeline: {
    
    BudgetEntry(date: .now, remaining: 1250.75, monthlyBudget: 2000, quickIntent: AddExpenseIntent())
    BudgetEntry(date: .now, remaining: -250.00, monthlyBudget: 2000, quickIntent: AddExpenseIntent())
}
