import SwiftUI
import SwiftData

/// Main container view with navigation between budget overview and transactions.
struct WatchContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsCollection: [BudgetSettings]
    @Query(sort: \BudgetCategory.name) private var categoryModels: [BudgetCategory]

    private var settings: BudgetSettings {
        settingsCollection.first ?? BudgetSettings()
    }

    private var categories: [String] {
        // Filter categories to only those belonging to current settings and deduplicate
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

    /// Observer for cross-process data change notifications
    @State private var dataChangeObserver: DarwinNotificationObserver?
    @State private var refreshToken = UUID()
    @State private var showingTransactions = false

    var body: some View {
        NavigationStack {
            BudgetOverviewView(
                settings: settings,
                categories: categories,
                onAddTransaction: addTransaction
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingTransactions = true
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                }
            }
            .sheet(isPresented: $showingTransactions) {
                TransactionListView(onDelete: deleteTransaction)
            }
        }
        .id(refreshToken)
        .onAppear {
            bootstrapSettingsIfNeeded()
            startObservingChanges()
        }
        .onDisappear {
            stopObservingChanges()
        }
    }

    private func bootstrapSettingsIfNeeded() {
        if settingsCollection.isEmpty {
            _ = BudgetSettings.bootstrap(in: modelContext)
        }
    }

    private func addTransaction(amount: Double, category: String) {
        let transaction = Transaction(
            title: "",
            amount: amount,
            category: category,
            date: .now,
            notes: ""
        )
        modelContext.insert(transaction)
        try? modelContext.save()

        CrossProcessNotifier.signalDataChange()
        WidgetRefreshHelper.reloadAllTimelines()
    }

    private func deleteTransaction(_ transaction: Transaction) {
        // Fetch the transaction from current context to ensure proper deletion
        let transactionID = transaction.persistentModelID
        var descriptor = FetchDescriptor<Transaction>()
        descriptor.predicate = #Predicate { $0.persistentModelID == transactionID }

        if let transactions = try? modelContext.fetch(descriptor),
           let toDelete = transactions.first {
            modelContext.delete(toDelete)
            try? modelContext.save()

            CrossProcessNotifier.signalDataChange()
            WidgetRefreshHelper.reloadAllTimelines()
        }
    }

    private func startObservingChanges() {
        let observer = DarwinNotificationObserver(
            name: CrossProcessNotifier.darwinNotificationName
        ) {
            handleExternalChange()
        }
        observer.start()
        dataChangeObserver = observer
    }

    private func stopObservingChanges() {
        dataChangeObserver?.stop()
        dataChangeObserver = nil
    }

    private func handleExternalChange() {
        modelContext.rollback()
        refreshToken = UUID()
    }
}
