import Foundation

/// Helpers for working with the shared app group container.
/// Ensures that processes only attempt to read from the shared preferences
/// domain when the container is available and the preferences directory exists.
enum AppGroupContainer {
    /// Lazily constructed shared defaults, falling back to `.standard` when the
    /// app group container is not accessible to the current process.
    static let sharedDefaults: UserDefaults = {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppIdentifiers.appGroup) else {
            return .standard
        }

        // Ensure the preferences directory exists before handing the suite off
        // to UserDefaults. This avoids cfprefsd complaints about missing
        // containers when the suite is first touched.
        let preferencesURL = containerURL.appendingPathComponent("Library/Preferences", isDirectory: true)
        try? FileManager.default.createDirectory(at: preferencesURL, withIntermediateDirectories: true)

        return UserDefaults(suiteName: AppIdentifiers.appGroup) ?? .standard
    }()
}
