import Foundation
import UIKit
import TelegramCore

/// One process-wide settings/accessibility subscription; per-consumer observations are weak.
public final class WhitegramVisualEnvironment {
    public static let shared = WhitegramVisualEnvironment()
    fileprivate static let changed = Notification.Name("WhitegramVisualEnvironmentChanged")

    public private(set) var policy: WhitegramVisualPolicy
    public private(set) var reduceMotion: Bool
    public private(set) var reduceTransparency: Bool
    public private(set) var lowPower: Bool
    public private(set) var active = true
    private var observers: [NSObjectProtocol] = []

    private init() {
        policy = WhitegramVisualPolicy(values: WhitegramPreferences.values(), legacyDefaults: .standard)
        reduceMotion = UIAccessibility.isReduceMotionEnabled
        reduceTransparency = UIAccessibility.isReduceTransparencyEnabled
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        for name in [WhitegramPreferences.updatedNotification, UserDefaults.didChangeNotification,
                     UIAccessibility.reduceMotionStatusDidChangeNotification, UIAccessibility.reduceTransparencyStatusDidChangeNotification,
                     Notification.Name.NSProcessInfoPowerStateDidChange,
                     UIApplication.didBecomeActiveNotification, UIApplication.willResignActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                self?.refresh(notification.name)
            })
        }
    }

    private func refresh(_ name: Notification.Name) {
        let oldPolicy = policy
        let oldState = [reduceMotion, reduceTransparency, lowPower, active]
        policy = WhitegramVisualPolicy(values: WhitegramPreferences.values(), legacyDefaults: .standard)
        reduceMotion = UIAccessibility.isReduceMotionEnabled
        reduceTransparency = UIAccessibility.isReduceTransparencyEnabled
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        if name == UIApplication.willResignActiveNotification { active = false }
        if name == UIApplication.didBecomeActiveNotification { active = true }
        if policy != oldPolicy || oldState != [reduceMotion, reduceTransparency, lowPower, active] {
            NotificationCenter.default.post(name: Self.changed, object: nil)
        }
    }

    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
}

public final class WhitegramVisualObservation {
    private let observer: NSObjectProtocol

    public init(_ changed: @escaping () -> Void) {
        _ = WhitegramVisualEnvironment.shared
        observer = NotificationCenter.default.addObserver(forName: WhitegramVisualEnvironment.changed, object: nil, queue: .main) { _ in changed() }
    }

    deinit { NotificationCenter.default.removeObserver(observer) }
}
