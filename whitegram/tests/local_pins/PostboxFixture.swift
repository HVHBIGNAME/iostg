import SwiftSignalKit

public struct PeerId: Hashable, Comparable {
    private let value: Int64
    public init(_ value: Int64) { self.value = value }
    public func toInt64() -> Int64 { value }
    public static func <(lhs: PeerId, rhs: PeerId) -> Bool { lhs.value < rhs.value }
}
public enum PeerGroupId: Hashable {
    case root, group(Int32)
    public var rawValue: Int32 { if case let .group(id) = self { return id }; return 0 }
}
public enum PinnedItemId: Equatable { case peer(PeerId) }
public protocol Peer { var id: PeerId { get } }
public struct MessageIndex: Comparable, Hashable {
    public let id: PeerId
    public let timestamp: Int
    public init(id: PeerId, timestamp: Int) { self.id = id; self.timestamp = timestamp }
    public static func <(lhs: MessageIndex, rhs: MessageIndex) -> Bool {
        lhs.timestamp == rhs.timestamp ? lhs.id < rhs.id : lhs.timestamp < rhs.timestamp
    }
}
public struct ChatListIndex: Comparable, Hashable {
    public let pinningIndex: UInt16?
    public let messageIndex: MessageIndex
    public init(pinningIndex: UInt16?, messageIndex: MessageIndex) { self.pinningIndex = pinningIndex; self.messageIndex = messageIndex }
    public static func <(lhs: ChatListIndex, rhs: ChatListIndex) -> Bool {
        if let l = lhs.pinningIndex, let r = rhs.pinningIndex, l != r { return l > r }
        if (lhs.pinningIndex == nil) != (rhs.pinningIndex == nil) { return lhs.pinningIndex == nil }
        return lhs.messageIndex < rhs.messageIndex
    }
}
public final class PreferencesEntry {
    private let value: Any
    public init(_ value: Any) { self.value = value }
    public func get<T>(_ type: T.Type) -> T? { value as? T }
}
public final class Transaction {
    public var peers: [PeerId: Peer] = [:]
    public var indices: [PeerId: (PeerGroupId, ChatListIndex)] = [:]
    public var preferences: [Int: PreferencesEntry] = [:]
    public var cloud: [Int32: [PinnedItemId]] = [:]
    public init() {}
    public func getPeer(_ id: PeerId) -> Peer? { peers[id] }
    public func getPeerChatListIndex(_ id: PeerId) -> (PeerGroupId, ChatListIndex)? { indices[id] }
    public func getPreferencesEntry(key: Int) -> PreferencesEntry? { preferences[key] }
    public func getPinnedItemIds(groupId: PeerGroupId) -> [PinnedItemId] { cloud[groupId.rawValue] ?? [] }
}
public final class Postbox {
    public let fixture = Transaction()
    public init() {}
    public func transaction<T>(_ body: @escaping (Transaction) -> T) -> Signal<T, NoError> {
        Signal { subscriber in subscriber.putNext(body(self.fixture)); return ActionDisposable {} }
    }
}
public struct ChatListFilterPredicate {
    public let includePeerIds: Set<PeerId>
    public let excludePeerIds: Set<PeerId>
    public let pinnedPeerIds: [PeerId]
    public let includeAdditionalPeerGroupIds: [PeerGroupId]
    public let include: (Peer, Bool, Bool, Bool, Bool?) -> Bool
    public init(includePeerIds: Set<PeerId>, excludePeerIds: Set<PeerId>, pinnedPeerIds: [PeerId], messageTagSummary: Int?, includeAdditionalPeerGroupIds: [PeerGroupId], include: @escaping (Peer, Bool, Bool, Bool, Bool?) -> Bool) {
        self.includePeerIds = includePeerIds; self.excludePeerIds = excludePeerIds; self.pinnedPeerIds = pinnedPeerIds
        self.includeAdditionalPeerGroupIds = includeAdditionalPeerGroupIds; self.include = include
    }
}
