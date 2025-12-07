import WidgetKit
import SwiftUI

// Widget bundle entry point exposing the budget widget
@main
struct BudgetWidgetBundle: WidgetBundle {
    var body: some Widget {
        BudgetWidget()
    }
}
