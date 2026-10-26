import Foundation
import TelegramCore

/// Reuses the existing authorized profile endpoint. No new protocol or membership inference.
private final class WhitegramRemainingBadgeRequest {
    private let client: WhitegramBackendClient
    private let service: WhitegramProfileService
    private let userId: Int64
    private let completion: (Bool) -> Void
    private var task: WhitegramBackendTask?
    private var timer: Timer?
    private var session: WhitegramBackendSession?
    private var nextRefresh = Date.distantPast
    private var cancelled = false

    init(accountId: Int64, userId: Int64, completion: @escaping (Bool) -> Void) {
        self.client = WhitegramBackendClient(userId: accountId)
        self.service = WhitegramProfileService(client: client)
        self.userId = userId
        self.completion = completion
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        refresh()
    }

    func cancel() {
        cancelled = true
        task?.cancel()
        task = nil
        timer?.invalidate()
        timer = nil
    }

    private func currentSession() -> WhitegramBackendSession? {
        do {
            guard let value = try client.sessions.load(userId: client.userId) else { return nil }
            try value.validate(userId: client.userId, now: client.now())
            try client.access.require(userId: client.userId, path: WhitegramProfileResource.badge.path, now: client.now())
            return value
        } catch { return nil }
    }

    private func tick() {
        guard !cancelled else { return }
        guard let current = currentSession(), session == nil || session == current else {
            completion(false)
            cancel()
            return
        }
        if task == nil, nextRefresh <= client.now() { refresh() }
    }

    private func refresh() {
        guard !cancelled else { return }
        guard let session = currentSession() else { completion(false); cancel(); return }
        self.session = session
        nextRefresh = client.now().addingTimeInterval(30)
        task = service.fetch(WhitegramProfileBadge.self, resource: .badge, userId: userId) { [weak self] result in
            guard let self, !cancelled else { return }
            task = nil
            guard currentSession() == session else { completion(false); cancel(); return }
            switch result {
            case let .success(badge):
                let granted = WhitegramRemainingPresentationPolicy.hasGrantedBadge(granted: badge.granted, role: badge.role,
                    badgeText: badge.badgeText, verificationText: badge.verificationText)
                completion(granted)
            case .failure:
                completion(false)
            }
        }
    }
}

private var remainingBadgeObservers: [NSObjectProtocol] = []

private final class WhitegramRemainingBadgeSubscriptions {
    static let shared = WhitegramRemainingBadgeSubscriptions()
    private struct Key: Hashable { let account: Int64; let user: Int64 }
    private final class Entry {
        var request: WhitegramRemainingBadgeRequest?
        var listeners: [UUID: (Bool) -> Void] = [:]
        var granted = false
    }
    private var entries: [Key: Entry] = [:]

    func subscribe(account: Int64, user: Int64, completion: @escaping (Bool) -> Void) -> (() -> Void) {
        let key = Key(account: account, user: user)
        let token = UUID()
        let entry: Entry
        if let existing = entries[key] {
            entry = existing
            entry.listeners[token] = completion
            completion(entry.granted)
        } else {
            entry = Entry()
            entry.listeners[token] = completion
            entries[key] = entry
            entry.request = WhitegramRemainingBadgeRequest(accountId: account, userId: user) { [weak entry] granted in
                guard let entry else { return }
                entry.granted = granted
                for listener in Array(entry.listeners.values) { listener(granted) }
            }
        }
        return { [weak self, weak entry] in
            let remove = {
                guard let self, let entry else { return }
                entry.listeners.removeValue(forKey: token)
                if entry.listeners.isEmpty {
                    entry.request?.cancel()
                    if self.entries[key] === entry { self.entries.removeValue(forKey: key) }
                }
            }
            if Thread.isMainThread { remove() } else { DispatchQueue.main.async(execute: remove) }
        }
    }

    func invalidate(account: Int64) {
        for key in Array(entries.keys) where key.account == account {
            entries.removeValue(forKey: key)?.request?.cancel()
        }
    }
}

public func whitegramInstallRemainingPresentation() {
    precondition(Thread.isMainThread)
    guard remainingBadgeObservers.isEmpty else { return }
    WhitegramRemainingBadgeBinding.fetch = { account, user, completion in
        return WhitegramRemainingBadgeSubscriptions.shared.subscribe(account: account, user: user, completion: completion)
    }
    for name in [WhitegramBackendClient.sessionUpdated, WhitegramBackendAccessStore.updated, WhitegramProfileService.updated] {
        remainingBadgeObservers.append(whitegramServiceObserve(name) { event in
            let key = name == WhitegramProfileService.updated ? "accountId" : "userId"
            guard let account = event.userInfo?[key] as? Int64 else { return }
            WhitegramRemainingBadgeSubscriptions.shared.invalidate(account: account)
            NotificationCenter.default.post(name: WhitegramRemainingBadgeBinding.invalidated, object: nil, userInfo: ["accountId": account])
        })
    }
}
