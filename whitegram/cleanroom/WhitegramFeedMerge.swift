import Foundation

public struct WhitegramFeedKey: Hashable, Comparable {
    public let peer: Int64
    public let id: Int32
    public let timestamp: Int32

    public init(peer: Int64, id: Int32, timestamp: Int32) {
        self.peer = peer
        self.id = id
        self.timestamp = timestamp
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
        if lhs.peer != rhs.peer { return lhs.peer < rhs.peer }
        return lhs.id < rhs.id
    }
}

/// A k-way merge must stop at an empty, non-exhausted channel, not append another
/// channel's older page and insert newer posts above it on the next request.
public struct WhitegramFeedMerge {
    public enum Step: Equatable {
        case fetch([Int64])
        case post(WhitegramFeedKey)
        case end
    }
    private struct Stream {
        var keys: [WhitegramFeedKey] = []
        var offset: Int32 = 0
        var exhausted = false
    }
    private var streams: [Int64: Stream] = [:]
    private var emitted: Set<String> = []

    public init(peers: [Int64]) {
        for peer in peers { streams[peer] = Stream() }
    }

    public func offset(peer: Int64) -> Int32 { return streams[peer]?.offset ?? 0 }

    @discardableResult
    public mutating func accept(peer: Int64, keys: [WhitegramFeedKey], nextOffset: Int32?, exhausted: Bool) throws -> [WhitegramFeedKey] {
        guard var stream = streams[peer], stream.keys.isEmpty, !stream.exhausted else { throw MergeError.invalidPage }
        guard keys.allSatisfy({ $0.peer == peer && $0.id > 0 }) else { throw MergeError.invalidPage }
        if !exhausted {
            guard let nextOffset, nextOffset > 0, stream.offset == 0 || nextOffset < stream.offset else { throw MergeError.nonAdvancingPage }
        }
        var seen = Set<String>()
        stream.keys = keys.sorted(by: >).filter { key in
            let identity = Self.identity(key)
            return !emitted.contains(identity) && seen.insert(identity).inserted
        }
        stream.offset = nextOffset ?? stream.offset
        stream.exhausted = exhausted
        streams[peer] = stream
        return stream.keys
    }

    public mutating func next() -> Step {
        let missing = streams.filter { $0.value.keys.isEmpty && !$0.value.exhausted }.map(\.key).sorted()
        if !missing.isEmpty { return .fetch(missing) }
        guard let key = streams.values.compactMap({ $0.keys.first }).max() else { return .end }
        streams[key.peer]?.keys.removeFirst()
        emitted.insert(Self.identity(key))
        return .post(key)
    }

    private static func identity(_ key: WhitegramFeedKey) -> String { return "\(key.peer):\(key.id)" }
    public enum MergeError: Error { case invalidPage, nonAdvancingPage }
}
