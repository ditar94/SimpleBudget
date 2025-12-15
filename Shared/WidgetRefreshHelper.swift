import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

enum WidgetRefreshHelper {
    /// Debounce interval in seconds to coalesce rapid refresh requests
    private static let debounceInterval: TimeInterval = 0.3

    /// Serial queue for thread-safe debounce handling
    private static let debounceQueue = DispatchQueue(label: "com.whitesnek.simplebudget.widget.debounce")

    /// Pending work item for debounced refresh
    private static var pendingRefresh: DispatchWorkItem?

    /// Reloads all widget timelines with debouncing to prevent excessive refreshes.
    /// Multiple calls within the debounce interval will be coalesced into a single refresh.
    static func reloadAllTimelines() {
        #if canImport(WidgetKit)
        if #available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *) {
            debounceQueue.async {
                // Cancel any pending refresh
                pendingRefresh?.cancel()

                // Create new debounced work item
                let workItem = DispatchWorkItem {
                    WidgetCenter.shared.reloadAllTimelines()
                }
                pendingRefresh = workItem

                // Execute after debounce interval
                DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
            }
        }
        #endif
    }

    /// Immediately reloads all widget timelines without debouncing.
    /// Use this when you need guaranteed immediate refresh (e.g., after user-initiated actions).
    static func reloadAllTimelinesImmediately() {
        #if canImport(WidgetKit)
        if #available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *) {
            debounceQueue.async {
                pendingRefresh?.cancel()
                pendingRefresh = nil
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
    }
}
