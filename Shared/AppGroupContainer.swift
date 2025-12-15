import Foundation

/// Helpers for working with the shared app group container.
/// Ensures that processes only attempt to read from the shared preferences
/// domain when the container is available and the preferences directory exists.
enum AppGroupContainer {
    /// Lock for thread-safe lazy initialization
    private static let initLock = NSLock()
    private static var _sharedDefaults: UserDefaults?

    /// Lazily constructed shared defaults, falling back to `.standard` when the
    /// app group container is not accessible to the current process.
    /// Note: The CFPrefs warning about kCFPreferencesAnyUser is a known iOS quirk
    /// with app group UserDefaults - it's harmless and doesn't affect functionality.
    static var sharedDefaults: UserDefaults {
        initLock.lock()
        defer { initLock.unlock() }

        if let existing = _sharedDefaults {
            return existing
        }

        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppIdentifiers.appGroup) else {
            _sharedDefaults = .standard
            return .standard
        }

        // Ensure the preferences directory exists before handing the suite off
        // to UserDefaults. This avoids cfprefsd complaints about missing
        // containers when the suite is first touched.
        let preferencesURL = containerURL.appendingPathComponent("Library/Preferences", isDirectory: true)
        try? FileManager.default.createDirectory(at: preferencesURL, withIntermediateDirectories: true)

        let defaults = UserDefaults(suiteName: AppIdentifiers.appGroup) ?? .standard
        _sharedDefaults = defaults
        return defaults
    }
}
