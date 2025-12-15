import SwiftUI

/// Category selection view matching main app aesthetic.
struct CategoryPickerView: View {
    let categories: [String]
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    // Color palette matching main app exactly
    private static let primaryBlue = Color(red: 0.25, green: 0.55, blue: 1.0)
    private static let secondaryLabel = Color(red: 0.45, green: 0.5, blue: 0.58)
    private static let pageBackground = Color(red: 0.96, green: 0.97, blue: 0.99)
    private static let border = Color(red: 0.88, green: 0.91, blue: 0.96)

    var body: some View {
        NavigationStack {
            ZStack {
                // Light background matching main app
                Self.pageBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(categories, id: \.self) { category in
                            CategoryButton(
                                category: category,
                                icon: iconForCategory(category),
                                color: colorForCategory(category)
                            ) {
                                onSelect(category)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Self.secondaryLabel)
                            .frame(width: 24, height: 24)
                            .background(
                                Circle()
                                    .fill(Self.border)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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
            return Color(red: 0.91, green: 0.24, blue: 0.36)
        case "shopping":
            return .pink
        case "other":
            return Color(red: 0.45, green: 0.5, blue: 0.58)
        default:
            return Self.primaryBlue
        }
    }
}

// MARK: - Category Button

struct CategoryButton: View {
    let category: String
    let icon: String
    let color: Color
    let action: () -> Void

    // Color palette matching main app
    private static let primaryText = Color(red: 0.12, green: 0.14, blue: 0.2)
    private static let secondaryLabel = Color(red: 0.45, green: 0.5, blue: 0.58)
    private static let cardBackground = Color(red: 0.96, green: 0.97, blue: 0.99)
    private static let border = Color(red: 0.88, green: 0.91, blue: 0.96)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Icon
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 28, height: 28)

                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(color)
                }

                // Category name
                Text(category)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Self.primaryText)

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Self.secondaryLabel)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Self.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Self.border, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CategoryPickerView(categories: BudgetSettings.defaultCategories) { category in
        print("Selected: \(category)")
    }
}
