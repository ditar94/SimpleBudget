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
        let entry = BudgetEntry(
            date: .now,
            remaining: remaining,
            monthlyBudget: settings.monthlyBudget,
            quickIntent: configuration
        )

        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
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
    private var remainingAfterPending: Double { entry.remaining - pendingAmount }
    private var spendingProgress: Double {
        min(max(0, entry.monthlyBudget - entry.remaining) / max(entry.monthlyBudget, 1), 1)
    }

    private var quickIntent: AddExpenseIntent {
        var intent = entry.quickIntent
        intent.amount = pendingAmount
        return intent
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
            default:
                primaryWidgetView
            }
        }

        if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
            content
                .containerBackground(for: .widget) {
                    Color.clear
                }
        } else {
            content
                .background(Color.clear)
        }
    }

    // MARK: - Layouts

    private var primaryWidgetView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Budget", systemImage: "creditcard")
                    .font(.headline)
                Spacer()
                Text(entry.monthlyBudget, format: .currency(code: currencyCode))
                    .font(.caption)
            }

            ProgressView(value: spendingProgress)
                .tint(entry.remaining >= 0 ? Color.blue : Color.red)

            VStack(alignment: .leading, spacing: 4) {
                valueRow(title: entry.remaining >= 0 ? "Remaining" : "Over", value: entry.remaining, emphasizeNegative: true)
                valueRow(title: "Remaining after", value: remainingAfterPending, emphasizeNegative: true)
            }

            adjustmentControls(font: .body)

            quickAddControl
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
            Text(remainingAfterPending, format: .currency(code: currencyCode))
                .foregroundStyle(remainingAfterPending >= 0 ? Color.primary : Color.red)
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

            VStack(spacing: 2) {
                Text("After")
                    .font(.caption2)
                Text(remainingAfterPending, format: .currency(code: currencyCode))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(remainingAfterPending >= 0 ? Color.primary : Color.red)
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
            Text(value, format: .currency(code: currencyCode))
                .font(compact ? .caption.bold() : .headline.weight(.semibold))
                .foregroundStyle(emphasizeNegative && value < 0 ? Color.red : Color.primary)
        }
    }

    private func adjustmentControls(font: Font, showCurrency: Bool = true) -> some View {
        return HStack(spacing: 6) {
            Button(intent: AdjustQuickAmountIntent(delta: -adjustmentStep)) {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.plain)

            if showCurrency {
                Text(pendingAmount, format: .currency(code: currencyCode))
                    .font(font.monospacedDigit())
            } else {
                Text(pendingAmount, format: .number.precision(.fractionLength(0)))
                    .font(font.monospacedDigit())
            }

            Button(intent: AdjustQuickAmountIntent(delta: adjustmentStep)) {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .font(font)
    }

    private var adjustmentStep: Double {
        switch family {
        case .accessoryInline, .accessoryCircular:
            return 5
        default:
            return 10
        }
    }

    @ViewBuilder
    private var quickAddControl: some View {
        if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
            Button(intent: quickIntent) {
                Label("Add expense", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .simultaneousGesture(TapGesture().onEnded {
                WidgetCenter.shared.reloadAllTimelines()
            })
        } else {
            Text("Requires latest OS for quick add")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }
}

#Preview(as: .systemSmall) {
    BudgetWidget()
} timeline: {
    BudgetEntry(date: .now, remaining: 1200, monthlyBudget: 2000, quickIntent: AddExpenseIntent())
}
