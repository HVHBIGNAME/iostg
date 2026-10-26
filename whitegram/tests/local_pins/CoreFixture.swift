// Explicit Telegram API fixtures; the actual local-pin runtime and shared preferences compile alongside these.
import Postbox
import SwiftSignalKit

public struct RecordId { public let int64: Int64; public init(_ id: Int64) { int64 = id } }
public final class TelegramCommunity: Peer {
    public let id: PeerId
    public let collapsedInDialogs: Bool?
    public init(id: PeerId, collapsed: Bool) { self.id = id; collapsedInDialogs = collapsed }
}
public struct TestPeer: Peer { public let id: PeerId; public init(_ id: PeerId) { self.id = id } }
public enum Namespaces { public enum PeerGroup { public static let archive = PeerGroupId.group(1) } }
public enum PreferencesKeys { public static let chatListFilters = 1 }
public struct IncludePeers { public var pinnedPeers: [PeerId] = [] }
public struct FilterData { public var includePeers = IncludePeers() }
public enum ChatListFilter {
    case filter(Int32, String, String?, FilterData)
    public var id: Int32 { switch self { case let .filter(id, _, _, _): return id } }
    public init(_ id: Int32) { self = .filter(id, "test", nil, FilterData()) }
}
public struct ChatListFiltersState { public var filters: [ChatListFilter]; public init(_ ids: [Int32]) { filters = ids.map(ChatListFilter.init) } }
public enum TogglePeerChatPinnedLocation { case group(PeerGroupId), filter(Int32) }
public enum TogglePeerChatPinnedResult { case done, localPinError, limitExceeded(count: Int, limit: Int) }
public enum EnginePeer { public typealias Id = PeerId }
public struct EngineRenderedPeer {
    public let peerId: PeerId
    public init(_ id: PeerId) { peerId = id }
}
public final class EngineChatList {
    public enum Group: Equatable {
        case root, archive
        public func _asGroup() -> PeerGroupId { self == .root ? .root : Namespaces.PeerGroup.archive }
    }
    public struct Item {
        public enum Index: Comparable {
            case chatList(ChatListIndex), forum
            public static func <(lhs: Index, rhs: Index) -> Bool {
                if case let .chatList(l) = lhs, case let .chatList(r) = rhs { return l < r }; return false
            }
        }
        public let id: PeerId
        public let index: Index
        public let messages: [Int]
        public let readCounters: Int?
        public let isMuted: Bool
        public let draft: String?
        public let threadData: Int?
        public let renderedPeer: EngineRenderedPeer
        public let presence: Int?
        public let hasUnseenMentions: Bool
        public let hasUnseenReactions: Bool
        public let hasUnseenPollVotes: Bool
        public let forumTopicData: Int?
        public let topForumTopicItems: [Int]
        public let hasFailed: Bool
        public let isContact: Bool
        public let autoremoveTimeout: Int32?
        public let storyStats: Int?
        public let displayAsTopicList: Bool
        public let isPremiumRequiredToMessage: Bool
        public let mediaDraftContentType: Int?
        public init(id: PeerId, index: Index, messages: [Int] = [7], readCounters: Int? = 4, isMuted: Bool = false, draft: String? = "draft", threadData: Int? = nil, renderedPeer: EngineRenderedPeer, presence: Int? = nil, hasUnseenMentions: Bool = true, hasUnseenReactions: Bool = true, hasUnseenPollVotes: Bool = false, forumTopicData: Int? = nil, topForumTopicItems: [Int] = [], hasFailed: Bool = true, isContact: Bool = true, autoremoveTimeout: Int32? = nil, storyStats: Int? = 8, displayAsTopicList: Bool = false, isPremiumRequiredToMessage: Bool = false, mediaDraftContentType: Int? = nil) {
            self.id = id; self.index = index; self.messages = messages; self.readCounters = readCounters; self.isMuted = isMuted
            self.draft = draft; self.threadData = threadData; self.renderedPeer = renderedPeer; self.presence = presence
            self.hasUnseenMentions = hasUnseenMentions; self.hasUnseenReactions = hasUnseenReactions; self.hasUnseenPollVotes = hasUnseenPollVotes
            self.forumTopicData = forumTopicData; self.topForumTopicItems = topForumTopicItems; self.hasFailed = hasFailed; self.isContact = isContact
            self.autoremoveTimeout = autoremoveTimeout; self.storyStats = storyStats; self.displayAsTopicList = displayAsTopicList
            self.isPremiumRequiredToMessage = isPremiumRequiredToMessage; self.mediaDraftContentType = mediaDraftContentType
        }
    }
    public var whitegramLocalPinRanks: [PeerId: Int] = [:]
    public var whitegramLocalPinBase: EngineChatList?
    public let items: [Item]
    public let groupItems: [Int]
    public let additionalItems: [Int]
    public let hasEarlier: Bool
    public let hasLater: Bool
    public let isLoading: Bool
    public init(items: [Item], groupItems: [Int] = [], additionalItems: [Int] = [], hasEarlier: Bool = false, hasLater: Bool = false, isLoading: Bool = false) {
        self.items = items; self.groupItems = groupItems; self.additionalItems = additionalItems
        self.hasEarlier = hasEarlier; self.hasLater = hasLater; self.isLoading = isLoading
    }
    public convenience init(_ view: FixtureView, accountPeerId: PeerId) { self.init(items: view.items) }
}
public struct FixtureView { public let items: [EngineChatList.Item] }
public final class ViewTracker {
    public var allItems: [EngineChatList.Item] = []
    public var requestedIds: Set<PeerId> = []
    public var pinRanksPassed = 0
    public var requestedCount = 0
    public init() {}
    public func tailChatListView(groupId: PeerGroupId, filterPredicate: ChatListFilterPredicate?, count: Int, shouldLoadCanMessagePeer: Bool) -> Signal<(FixtureView, Int), NoError> {
        let items = allItems.filter { filterPredicate?.include(TestPeer($0.renderedPeer.peerId), false, false, false, nil) ?? true }
        requestedIds = Set(items.map { $0.renderedPeer.peerId }); requestedCount = count
        pinRanksPassed = filterPredicate?.pinnedPeerIds.count ?? 0
        return .single((FixtureView(items: Array(items.prefix(count))), 0))
    }
}
public final class Account {
    public let id: RecordId
    public let peerId = PeerId(900)
    public let postbox = Postbox()
    public let viewTracker = ViewTracker()
    public init(_ id: Int64) { self.id = RecordId(id) }
}
