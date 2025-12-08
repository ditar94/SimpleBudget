import Foundation

/// Cross-process signaling helpers used by the app and its extensions to notify
/// each other when the shared SwiftData store has been modified.
enum CrossProcessNotifier {
    static let darwinNotificationName = CFNotificationName("com.whitesnek.simplebudget.datastore.changed" as CFString)
    static let versionDefaultsKey = "datastore_change_version"

    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: AppIdentifiers.appGroup) ?? .standard
    }

    /// Broadcasts a change signal to all processes sharing the app group.
    static func signalDataChange() {
        let token = Date().timeIntervalSince1970
        sharedDefaults.set(token, forKey: versionDefaultsKey)
        sharedDefaults.synchronize()

        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, darwinNotificationName, nil, nil, true)
    }

    /// Reads the last published change token from the shared defaults.
    static func latestChangeToken() -> TimeInterval? {
        sharedDefaults.object(forKey: versionDefaultsKey) as? TimeInterval
    }
}

/// Lightweight wrapper around Darwin notification observers so we can attach
/// Swift closures to cross-process notifications.
final class DarwinNotificationObserver {
    private let name: CFNotificationName
    private let handler: @MainActor () -> Void
    private var isObserving = false

    init(name: CFNotificationName, handler: @escaping @MainActor () -> Void) {
        self.name = name
        self.handler = handler
    }

    func start() {
        guard !isObserving else { return }
        let center = CFNotificationCenterGetDarwinNotifyCenter()

        CFNotificationCenterAddObserver(center, Unmanaged.passUnretained(self).toOpaque(), { _, observer, _, _, _ in
            guard let observer else { return }
            let instance = Unmanaged<DarwinNotificationObserver>.fromOpaque(observer).takeUnretainedValue()
            Task { @MainActor in
                instance.handler()
            }
        }, name, nil, .deliverImmediately)

        isObserving = true
    }

    func stop() {
        guard isObserving else { return }
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveObserver(center, Unmanaged.passUnretained(self).toOpaque(), name, nil)
        isObserving = false
    }

    deinit {
        stop()
    }
}
