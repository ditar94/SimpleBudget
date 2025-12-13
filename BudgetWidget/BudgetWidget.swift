import SwiftUI
import WidgetKit
import SwiftData
import AppIntents

// Timeline entry carrying budget details and the quick intent configuration
struct BudgetEntry: TimelineEntry {
    let date: Date
    let remaining: Double
    let monthlyBudget: Double
    let quickIntent: AddExpenseIntent
}

// Provider building the widget timeline from shared SwiftData storage
struct BudgetWidgetProvider: AppIntentTimelineProvider {
    typealias Entry = BudgetEntry
    typealias Intent = AddExpenseIntent

    func placeholder(in context: Context) -> BudgetEntry {
        BudgetEntry(date: .now, remaining: 1500, monthlyBudget: 2000, quickIntent: AddExpenseIntent())
    }

    func snapshot(for configuration: Intent, in context: Context) async -> BudgetEntry {
        BudgetEntry(date: .now, remaining: 1500, monthlyBudget: 2000, quickIntent: configuration)
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<BudgetEntry> {
        let container = try? WidgetModelContainer.shared
        let modelContext = container.map(ModelContext.init)

        let currentMonthTotal: Double
        let settings: BudgetSettings

        if let modelContext, let fetchedSettings = try? modelContext.fetch(FetchDescriptor<BudgetSettings>()).first {
            settings = fetchedSettings
            let transactions = (try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? []
            currentMonthTotal = transactions
                .filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month) }
                .reduce(0) { $0 + $1.amount }
        } else {
            settings = BudgetSettings()
            currentMonthTotal = 0
        }

        let remaining = settings.monthlyBudget - currentMonthTotal
        let now = Date()
        let currentEntry = BudgetEntry(
            date: now,
            remaining: remaining,
            monthlyBudget: settings.monthlyBudget,
            quickIntent: configuration
        )

        // Use a short-lived timeline so widget reloads pick up recent expenses quickly
        let refreshDate = now.addingTimeInterval(30)
        return Timeline(entries: [currentEntry], policy: .after(refreshDate))
    }
}

struct BudgetWidget: Widget {
    let kind: String = "BudgetWidget"

    // Main widget configuration supporting multiple families
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: AddExpenseIntent.self, provider: BudgetWidgetProvider()) { entry in
            BudgetWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Expense")
        .description("Add expenses from your lock screen or Home Screen.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular, .systemSmall, .systemMedium])
    }
}

struct BudgetWidgetView: View {
    let entry: BudgetEntry
    @Environment(\.widgetFamily) private var family

    @AppStorage(BudgetWidgetAmountStore.key, store: BudgetWidgetAmountStore.defaults)
    private var storedAmount: Double = BudgetWidgetAmountStore.defaultAmount

    init(entry: BudgetEntry) {
        self.entry = entry
    }

    private var currencyCode: String { Locale.current.currency?.identifier ?? "USD" }
    private var pendingAmount: Double { storedAmount }
    private var committedSpend: Double { max(entry.monthlyBudget - entry.remaining, 0) }
    private var totalAfterPending: Double { committedSpend + pendingAmount }
    private var overBudgetAmount: Double { max(0, totalAfterPending - entry.monthlyBudget) }
    private var remainingAfterPending: Double { entry.remaining - pendingAmount }
    private var spendingProgress: Double {
        min(max(0, entry.monthlyBudget - entry.remaining) / max(entry.monthlyBudget, 1), 1)
    }

    private var quickIntent: AddExpenseIntent {
        let intent = entry.quickIntent
        intent.amount = pendingAmount
        return intent
    }

    private func adjustStoredAmount(by delta: Double) {
        storedAmount = max(0, storedAmount + delta)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // Compact UI summarizing remaining budget and launching quick add intent
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

        let backgroundColor = family == .systemSmall ? remainingBackground : Color.clear

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

    // MARK: - Layouts

    private var systemSmallView: some View {
        ZStack {
            remainingBackground

            VStack(spacing: 8) {
                Text("Remaining Budget:")
                    .font(.caption.weight(.semibold))
                Text(entry.remaining, format: .currency(code: currencyCode))
                    .font(.title3.monospacedDigit().weight(.bold))
            }
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            .padding()
        }
    }

    private var systemMediumView: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow
            budgetProgressSection
            remainingRow
            controlGrid
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.14))
        )
        .padding(8)
    }

    private var headerRow: some View {
        HStack {
            Text("Monthly Budget")
                .font(.callout.weight(.semibold))
            Spacer()
            Text(entry.monthlyBudget, format: .currency(code: currencyCode))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
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
                .frame(height: 12)
                .clipShape(Capsule())
            }
            .frame(height: 14)
            .animation(.easeOut(duration: 0.12), value: totalAfterPending)

            HStack(spacing: 8) {
                if isOverBudget {
                    Text("Overbudget by \(overBudgetAmount, format: .currency(code: currencyCode))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.red)
                } else {
                    Text("Committed: \(committedSpend, format: .currency(code: currencyCode))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Pending: \(pendingAmount, format: .currency(code: currencyCode))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var remainingRow: some View {
        HStack {
            Text("Remaining Budget:")
                .font(.subheadline.weight(.semibold))
            Spacer()
            if #available(iOS 17.0, *) {
                Text(remainingAfterPending, format: .currency(code: currencyCode))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(remainingAfterPending >= 0 ? Color.primary : Color.red)
                    .contentTransition(.numericText(value: remainingAfterPending))
                    .animation(.easeOut(duration: 0.12), value: remainingAfterPending)
            } else {
                Text(remainingAfterPending, format: .currency(code: currencyCode))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(remainingAfterPending >= 0 ? Color.primary : Color.red)
            }
        }
    }

    private var controlGrid: some View {
        HStack(alignment: .center, spacing: 14) {
            adjustmentGrid(deltas: [-20, -10, -5, -1, -0.25, -0.05])
                .frame(maxWidth: .infinity)
            addButton
                .frame(maxWidth: .infinity)
            adjustmentGrid(deltas: [0.05, 0.25, 1, 5, 10, 20])
                .frame(maxWidth: .infinity)
        }
    }

    private func adjustmentGrid(deltas: [Double]) -> some View {
        VStack(spacing: 10) {
            adjustmentRow(deltas: Array(deltas.prefix(3)))
            adjustmentRow(deltas: Array(deltas.suffix(3)))
        }
    }

    private func adjustmentRow(deltas: [Double]) -> some View {
        HStack(spacing: 8) {
            ForEach(deltas, id: \.self) { delta in
                adjustmentButton(delta: delta)
            }
        }
    }

    @ViewBuilder
    private func adjustmentButton(delta: Double) -> some View {
        let label = Text(formattedDeltaLabel(for: delta))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

        if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
            Button(intent: AdjustQuickAmountIntent(delta: delta)) {
                label
            }
            .buttonStyle(.borderedProminent)
            .tint(adjustmentTint(for: delta))
            .frame(height: 40)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .simultaneousGesture(TapGesture().onEnded {
                adjustStoredAmount(by: delta)
            })
        } else {
            Button(action: {
                adjustStoredAmount(by: delta)
            }) {
                label
            }
            .buttonStyle(.borderedProminent)
            .tint(adjustmentTint(for: delta))
            .frame(height: 40)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func formattedDeltaLabel(for delta: Double) -> String {
        let absolute = abs(delta)
        let sign = delta < 0 ? "-" : ""

        if absolute < 1 {
            let cents = Int((absolute * 100).rounded())
            return "\(sign)\(cents)¢"
        }

        let wholeDollars = Int(absolute.rounded())
        return "\(sign)$\(wholeDollars)"
    }

    private func adjustmentTint(for delta: Double) -> Color {
        delta < 0 ? .red : .blue
    }

    @ViewBuilder
    private var addButton: some View {
        if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
            VStack(spacing: 10) {
                Button(intent: quickIntent) {
                    Text("+")
                        .font(.system(size: 32, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
                .buttonStyle(.borderedProminent)
                .frame(height: 80)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button(action: {
                    storedAmount = 0
                    WidgetCenter.shared.reloadAllTimelines()
                }) {
                    Text("Clear")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .frame(height: 34)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        } else {
            Text("Requires latest OS for quick add")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }


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

    // MARK: - Components

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

    private var adjustmentStep: Double {
        switch family {
        case .accessoryInline, .accessoryCircular:
            return 1
        default:
            return 1
        }
    }

    private var remainingBackground: Color {
        entry.remaining >= 0 ? Color.green : Color.red
    }

    @ViewBuilder
    private var primaryActionRow: some View {
        HStack(spacing: 14) {
            adjustmentControls(font: .title2, weight: .semibold, spacing: 10)
            quickAddControl(compact: true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

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
                // Reset the quick amount after adding an expense so selector returns to 0
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

#Preview(as: .systemMedium) {
    BudgetWidget()
} timeline: {
    BudgetEntry(date: .now, remaining: 300, monthlyBudget: 300, quickIntent: AddExpenseIntent())
}
