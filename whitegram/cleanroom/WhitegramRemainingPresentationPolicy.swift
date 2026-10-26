import Foundation

public enum WhitegramRemainingBadgeSurface { case post, chatList, chatHeader, profile }

public enum WhitegramRemainingPresentationPolicy {
    // TelegramCore 3.2, 0x2b68e4: an explicit grant overrides the legacy text/role inference.
    public static func hasGrantedBadge(granted: Bool?, role: String?, badgeText: String?, verificationText: String?) -> Bool {
        if let granted { return granted }
        if let role, !role.isEmpty, role != "beta_tester" { return true }
        return !(badgeText ?? "").isEmpty || !(verificationText ?? "").isEmpty
    }

    public static func showsBadge(granted: Bool, hidden: Bool, surface: WhitegramRemainingBadgeSurface) -> Bool {
        return granted && (surface == .profile || !hidden)
    }

    // TelegramUI 3.2, 0x1839048: suppression precedes the incoming style lookup.
    public static func allowsCustomMessageStyle(incoming: Bool, hidden: Bool, excluded: Bool, supportedMedia: Bool) -> Bool {
        return !excluded && supportedMedia && !(incoming && hidden)
    }

    // Despite its old menu case name, the 3.2 selector writes appBadgeName, not a color boolean.
    public static func appBadgeName(_ stored: String?) -> String {
        guard let stored, !stored.isEmpty else { return "WGBadgePrimary" }
        return stored
    }
}

/// A screen-owned bridge. Backend factories and UIKit are outside TelegramCore.
public final class WhitegramRemainingBadgeBinding {
    public typealias Fetch = (Int64, Int64, @escaping (Bool) -> Void) -> (() -> Void)
    public static var fetch: Fetch?
    public static let invalidated = Notification.Name("WhitegramRemainingBadgeInvalidated")
    public var updated: (() -> Void)?
    private var cancelRequest: (() -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var identity: (account: Int64, user: Int64)?
    private var generation = 0
    private var value = false
    private let lock = NSLock()

    public init() {
        for name in [WhitegramPreferences.updatedNotification, Self.invalidated] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] event in
                let account = event.userInfo?["accountId"] as? Int64
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if name == Self.invalidated {
                        guard let identity = self.identity, account == nil || account == identity.account else { return }
                        self.reset()
                        self.update(accountId: identity.account, userId: identity.user)
                    }
                    self.updated?()
                }
            })
        }
    }

    deinit {
        cancelRequest?()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    public func update(accountId: Int64, userId: Int64?) {
        precondition(Thread.isMainThread)
        guard let userId, userId > 0, accountId > 0 else { reset(); return }
        if identity?.account == accountId, identity?.user == userId { return }
        reset()
        lock.lock()
        identity = (accountId, userId)
        lock.unlock()
        let generation = self.generation
        cancelRequest = Self.fetch?(accountId, userId) { [weak self] granted in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == generation else { return }
                self.lock.lock()
                let changed = self.value != granted
                self.value = granted
                self.lock.unlock()
                if changed { self.updated?() }
            }
        }
    }

    public func showsBadge(accountId: Int64, userId: Int64?, surface: WhitegramRemainingBadgeSurface) -> Bool {
        lock.lock()
        let matches = identity?.account == accountId && identity?.user == userId
        let granted = value
        lock.unlock()
        return matches && WhitegramRemainingPresentationPolicy.showsBadge(granted: granted,
            hidden: WhitegramPreferences.bool("hideWhitegramUserBadge"), surface: surface)
    }

    private func reset() {
        generation += 1
        cancelRequest?()
        cancelRequest = nil
        lock.lock()
        identity = nil
        value = false
        lock.unlock()
    }
}
