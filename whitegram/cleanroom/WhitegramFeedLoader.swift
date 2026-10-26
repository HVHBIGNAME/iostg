import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import AccountContext

/// Main-queue scheduler; at most four channel-history requests are in flight.
final class WhitegramFeedLoader {
    struct State {
        var posts: [Message] = []
        var channels = 0
        var loading = false
        var ended = false
        var error: String?
    }
    private let context: AccountContext
    private var discovery: Disposable?
    private var requests: [Int64: MetaDisposable] = [:]
    private var merge = WhitegramFeedMerge(peers: [])
    private var buffered: [WhitegramFeedKey: Message] = [:]
    private var generation = 0
    private var targetCount = 0
    private var suspended = true
    private(set) var state = State()
    var updated: ((State) -> Void)?

    init(context: AccountContext) { self.context = context }
    deinit { self.discovery?.dispose(); self.requests.values.forEach { $0.dispose() } }

    func refresh() {
        self.cancel()
        self.suspended = false
        self.state = State()
        self.buffered.removeAll()
        self.state.loading = true
        self.targetCount = 30
        let generation = self.generation
        self.updated?(self.state)
        self.discovery = (WhitegramFeedHistory.channels(account: self.context.account) |> deliverOnMainQueue).start(next: { [weak self] channels in
            guard let self, self.generation == generation else { return }
            self.discovery = nil
            self.state.channels = channels.count
            self.merge = WhitegramFeedMerge(peers: channels.map { $0.id.toInt64() })
            self.pump()
        })
    }

    func loadMore() {
        guard !self.state.ended, !self.state.loading else { return }
        self.suspended = false
        self.state.error = nil
        self.targetCount = self.state.posts.count + 30
        self.pump()
    }

    func suspend() {
        self.cancel()
        self.suspended = true
        self.state.loading = false
        self.updated?(self.state)
    }

    func resume() {
        self.suspended = false
        if self.state.channels == 0 && !self.state.ended { self.refresh() }
        else if self.state.posts.count < self.targetCount && self.state.error == nil { self.pump() }
    }

    private func cancel() {
        self.generation += 1
        self.discovery?.dispose()
        self.discovery = nil
        self.requests.values.forEach { $0.dispose() }
        self.requests.removeAll()
    }

    private func pump() {
        guard !self.suspended, self.state.error == nil else { return }
        self.state.loading = self.state.posts.count < self.targetCount && !self.state.ended
        while self.state.loading {
            switch self.merge.next() {
            case let .post(key):
                if let message = self.buffered.removeValue(forKey: key) { self.state.posts.append(message) }
                self.state.loading = self.state.posts.count < self.targetCount
            case .end:
                self.state.ended = true
                self.state.loading = false
            case let .fetch(peers):
                for peer in peers where self.requests[peer] == nil {
                    if self.requests.count >= 4 { break }
                    self.fetch(peer: peer)
                }
                self.updated?(self.state)
                return
            }
        }
        self.updated?(self.state)
    }

    private func fetch(peer: Int64) {
        let generation = self.generation
        let disposable = MetaDisposable()
        self.requests[peer] = disposable
        disposable.set((WhitegramFeedHistory.page(account: self.context.account, peerId: PeerId(peer), offset: self.merge.offset(peer: peer))
        |> deliverOnMainQueue).start(next: { [weak self] page in
            guard let self, generation == self.generation else { return }
            self.requests.removeValue(forKey: peer)?.dispose()
            let pairs = page.messages.map { (WhitegramFeedKey(peer: peer, id: $0.id.id, timestamp: $0.timestamp), $0) }
            do {
                let accepted = Set(try self.merge.accept(peer: peer, keys: pairs.map { $0.0 }, nextOffset: page.nextOffset, exhausted: page.exhausted))
                for (key, message) in pairs where accepted.contains(key) { self.buffered[key] = message }
                self.pump()
            } catch { self.failed("Channel history did not advance. Pull to refresh or retry.") }
        }, error: { [weak self] error in
            guard let self, generation == self.generation else { return }
            self.failed("Could not load a channel: \(error). Retry to continue in chronological order.")
        }))
    }

    private func failed(_ message: String) {
        self.cancel()
        self.state.loading = false
        self.state.error = message
        self.updated?(self.state)
    }
}
