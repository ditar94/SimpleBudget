import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

enum WidgetRefreshHelper {
    static func reloadAllTimelines() {
        #if canImport(WidgetKit)
        if #available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
    }
}
