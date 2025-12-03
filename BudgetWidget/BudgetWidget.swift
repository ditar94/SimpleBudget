import SwiftUI
import WidgetKit
import SwiftData

struct BudgetEntry: TimelineEntry {
    let date: Date
    let remaining: Double
    let monthlyBudget: Double
    let quickIntent: AddExpenseIntent
}

struct BudgetWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BudgetEntry {
        BudgetEntry(date: .now, remaining: 1500, monthlyBudget: 2000, quickIntent: AddExpenseIntent())
    }

    func snapshot(for configuration: AddExpenseIntent, in context: Context, completion: @escaping (BudgetEntry) -> Void) {
        completion(BudgetEntry(date: .now, remaining: 1500, monthlyBudget: 2000, quickIntent: configuration))
    }

    func timeline(for configuration: AddExpenseIntent, in context: Context, completion: @escaping (Timeline<BudgetEntry>) -> Void) {
        let container = try? WidgetModelContainer.shared
        let modelContext = container.map(ModelContext.init)

        let currentMonthTotal: Double
        let settings: BudgetSettings

        if let modelContext, let fetchedSettings = try? modelContext.fetch(FetchDescriptor<BudgetSettings>()).first {
            settings = fetchedSettings
            let transactions = (try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? []
            currentMonthTotal = transactions
                .filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month) }
                .reduce(0) { $0 + ($1.type == .expense ? $1.amount : -$1.amount) }
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

        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct BudgetWidget: Widget {
    let kind: String = "BudgetWidget"

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

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Label("Budget", systemImage: "creditcard")
                    .font(.headline)
                Spacer()
                Text(entry.monthlyBudget, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                    .font(.caption)
            }
            ProgressView(value: min(max(0, entry.monthlyBudget - entry.remaining) / max(entry.monthlyBudget, 1), 1))
                .tint(entry.remaining >= 0 ? Color.blue : Color.red)
            HStack {
                Text(entry.remaining >= 0 ? "Remaining" : "Over")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(entry.remaining, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(entry.remaining >= 0 ? Color.primary : Color.red)
            }
            Button(intent: entry.quickIntent) {
                Label("Add expense", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

#Preview(as: .systemSmall) {
    BudgetWidget()
} timeline: {
    BudgetEntry(date: .now, remaining: 1200, monthlyBudget: 2000, quickIntent: AddExpenseIntent())
}
