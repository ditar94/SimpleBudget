import WidgetKit
import SwiftUI
import SwiftData

/// Timeline entry for budget complications
struct BudgetComplicationEntry: TimelineEntry {
    let date: Date
    let remaining: Double
    let monthlyBudget: Double
    let spent: Double

    var progress: Double {
        guard monthlyBudget > 0 else { return 0 }
        return min(spent / monthlyBudget, 1.0)
    }

    var isOverBudget: Bool {
        remaining < 0
    }
}

/// Timeline provider for budget complications
struct BudgetComplicationProvider: TimelineProvider {
    private let calendar = Calendar.current

    func placeholder(in context: Context) -> BudgetComplicationEntry {
        BudgetComplicationEntry(
            date: .now,
            remaining: 350,
            monthlyBudget: 500,
            spent: 150
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (BudgetComplicationEntry) -> Void) {
        let entry = fetchCurrentEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BudgetComplicationEntry>) -> Void) {
        let entry = fetchCurrentEntry()

        // Refresh every 15 minutes
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
        completion(timeline)
    }

    private func fetchCurrentEntry() -> BudgetComplicationEntry {
        let container = WatchModelContainer.shared
        let context = ModelContext(container)

        // Fetch settings
        var settingsDescriptor = FetchDescriptor<BudgetSettings>()
        settingsDescriptor.fetchLimit = 1
        let settings = (try? context.fetch(settingsDescriptor).first) ?? BudgetSettings()

        // Fetch current month transactions
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!

        let predicate = #Predicate<Transaction> { transaction in
            transaction.date >= startOfMonth
        }
        var transactionDescriptor = FetchDescriptor<Transaction>(predicate: predicate)
        transactionDescriptor.propertiesToFetch = [\.amount]

        let transactions = (try? context.fetch(transactionDescriptor)) ?? []
        let spent = transactions.reduce(0) { $0 + $1.amount }
        let remaining = settings.monthlyBudget - spent

        return BudgetComplicationEntry(
            date: now,
            remaining: remaining,
            monthlyBudget: settings.monthlyBudget,
            spent: spent
        )
    }
}

/// Budget complication widget for watch faces
struct BudgetComplication: Widget {
    let kind: String = "BudgetComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BudgetComplicationProvider()) { entry in
            BudgetComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Budget")
        .description("Shows your remaining budget for the month.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular
        ])
    }
}

/// View for rendering budget complications in different families
struct BudgetComplicationView: View {
    @Environment(\.widgetFamily) var family
    let entry: BudgetComplicationEntry

    private let currencyCode = Locale.current.currency?.identifier ?? "USD"

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryCorner:
            cornerView
        case .accessoryInline:
            inlineView
        case .accessoryRectangular:
            rectangularView
        default:
            circularView
        }
    }

    // MARK: - Circular Complication

    private var circularView: some View {
        ZStack {
            // Progress ring
            AccessoryWidgetBackground()

            Gauge(value: entry.progress) {
                EmptyView()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(entry.isOverBudget ? .red : .green)

            // Center text
            VStack(spacing: 0) {
                Text(shortCurrencyString(entry.remaining))
                    .font(.system(size: 14, weight: .bold))
                    .minimumScaleFactor(0.6)
                Text("left")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Corner Complication

    private var cornerView: some View {
        ZStack {
            AccessoryWidgetBackground()

            Text(shortCurrencyString(entry.remaining))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(entry.isOverBudget ? .red : .primary)
                .widgetCurvesContent()
        }
    }

    // MARK: - Inline Complication

    private var inlineView: some View {
        HStack(spacing: 4) {
            Image(systemName: entry.isOverBudget ? "exclamationmark.triangle.fill" : "dollarsign.circle.fill")
            Text("Remaining: \(shortCurrencyString(entry.remaining))")
        }
    }

    // MARK: - Rectangular Complication

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Budget")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(shortCurrencyString(entry.remaining))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(entry.isOverBudget ? .red : .green)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.gray.opacity(0.3))
                        .frame(height: 4)

                    Capsule()
                        .fill(entry.isOverBudget ? .red : .green)
                        .frame(width: geometry.size.width * entry.progress, height: 4)
                }
            }
            .frame(height: 4)

            HStack {
                Text("Spent: \(shortCurrencyString(entry.spent))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("of \(shortCurrencyString(entry.monthlyBudget))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func shortCurrencyString(_ value: Double) -> String {
        let absValue = abs(value)
        let sign = value < 0 ? "-" : ""

        if absValue >= 1000 {
            return "\(sign)$\(Int(absValue / 1000))k"
        } else {
            return "\(sign)$\(Int(absValue))"
        }
    }
}

#Preview("Circular", as: .accessoryCircular) {
    BudgetComplication()
} timeline: {
    BudgetComplicationEntry(date: .now, remaining: 350, monthlyBudget: 500, spent: 150)
    BudgetComplicationEntry(date: .now, remaining: -50, monthlyBudget: 500, spent: 550)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    BudgetComplication()
} timeline: {
    BudgetComplicationEntry(date: .now, remaining: 350, monthlyBudget: 500, spent: 150)
}

#Preview("Inline", as: .accessoryInline) {
    BudgetComplication()
} timeline: {
    BudgetComplicationEntry(date: .now, remaining: 350, monthlyBudget: 500, spent: 150)
}
