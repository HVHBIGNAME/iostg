import Foundation

/// Display cannot import TelegramCore. The presentation-layer relay supplies the
/// current account-profile value and the low-level renderers observe this signal.
public enum WhitegramClassicStyle {
    public static let changedNotification = Notification.Name("WhitegramClassicStyleChanged")
    private static let lock = NSLock()
    private static var value = false
    public static var enabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    public static func setEnabled(_ enabled: Bool) {
        lock.lock()
        let changed = value != enabled
        value = enabled
        lock.unlock()
        if changed { NotificationCenter.default.post(name: changedNotification, object: nil) }
    }

    public static func tabHeight(landscape: Bool, safeBottom: Double) -> Double {
        return (landscape ? 34.0 : 49.0) + max(0, safeBottom)
    }

    public static func navigationHeight(original: Double) -> Double { return enabled ? min(original, 44.0) : original }
}

public final class WhitegramClassicObserver {
    private let token: NSObjectProtocol
    public init(_ changed: @escaping () -> Void) {
        token = NotificationCenter.default.addObserver(forName: WhitegramClassicStyle.changedNotification, object: nil, queue: .main) { _ in changed() }
    }
    deinit { NotificationCenter.default.removeObserver(token) }
}
