import SwiftUI
import SwiftData

/// Transaction list view with liquid glass aesthetic.
struct TransactionListView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]

    let onDelete: (Transaction) -> Void

    private let calendar = Calendar.current
    private let currencyCode = Locale.current.currency?.identifier ?? "USD"

    private var currentMonthTransactions: [Transaction] {
        allTransactions.filter {
            calendar.isDate($0.date, equalTo: .now, toGranularity: .month)
        }
    }

    // Color palette matching main app exactly
    private static let primaryBlue = Color(red: 0.25, green: 0.55, blue: 1.0)
    private static let primaryText = Color(red: 0.12, green: 0.14, blue: 0.2)
    private static let secondaryLabel = Color(red: 0.45, green: 0.5, blue: 0.58)
    private static let pageBackground = Color(red: 0.96, green: 0.97, blue: 0.99)
    private static let border = Color(red: 0.88, green: 0.91, blue: 0.96)

    var body: some View {
        ZStack {
            // Light background matching main app
            Self.pageBackground
                .ignoresSafeArea()

            if currentMonthTransactions.isEmpty {
                emptyStateView
            } else {
                transactionList
            }
        }
        .navigationTitle("History")
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(Self.primaryBlue.opacity(0.1))
                    .frame(width: 50, height: 50)

                Image(systemName: "tray")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Self.primaryBlue)
            }

            VStack(spacing: 4) {
                Text("No Expenses")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Self.primaryText)

                Text("This Month")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Self.secondaryLabel)
            }
        }
    }

    private var transactionList: some View {
        List {
            ForEach(currentMonthTransactions, id: \.persistentModelID) { transaction in
                TransactionRowView(transaction: transaction)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            onDelete(transaction)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Transaction Row

struct TransactionRowView: View {
    let transaction: Transaction

    private let currencyCode = Locale.current.currency?.identifier ?? "USD"

    // Color palette matching main app exactly
    private static let primaryBlue = Color(red: 0.25, green: 0.55, blue: 1.0)
    private static let primaryText = Color(red: 0.12, green: 0.14, blue: 0.2)
    private static let secondaryLabel = Color(red: 0.45, green: 0.5, blue: 0.58)
    private static let cardBackground = Color(red: 0.96, green: 0.97, blue: 0.99)
    private static let border = Color(red: 0.88, green: 0.91, blue: 0.96)

    var body: some View {
        HStack(spacing: 10) {
            // Category icon
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.15))
                    .frame(width: 24, height: 24)

                Image(systemName: iconForCategory(transaction.category))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(categoryColor)
            }

            // Title and time
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.displayTitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Self.primaryText)
                    .lineLimit(1)

                Text(transaction.date, style: .relative)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(Self.secondaryLabel)
            }

            Spacer()

            // Amount
            Text(transaction.amount, format: .currency(code: currencyCode))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Self.primaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Self.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Self.border, lineWidth: 0.5)
                )
        )
    }

    private var categoryColor: Color {
        colorForCategory(transaction.category)
    }

    private func iconForCategory(_ category: String) -> String {
        switch category.lowercased() {
        case "food":
            return "fork.knife"
        case "transport":
            return "car.fill"
        case "entertainment":
            return "ticket.fill"
        case "bills":
            return "doc.text.fill"
        case "shopping":
            return "bag.fill"
        case "other":
            return "ellipsis.circle.fill"
        default:
            return "tag.fill"
        }
    }

    private func colorForCategory(_ category: String) -> Color {
        switch category.lowercased() {
        case "food":
            return .orange
        case "transport":
            return Self.primaryBlue
        case "entertainment":
            return .purple
        case "bills":
            return Color(red: 0.91, green: 0.24, blue: 0.36) // Match app's negative tint
        case "shopping":
            return .pink
        case "other":
            return Color(red: 0.45, green: 0.5, blue: 0.58) // Match app's secondary gray
        default:
            return Self.primaryBlue
        }
    }
}
