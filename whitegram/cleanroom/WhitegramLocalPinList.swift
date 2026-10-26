import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext

private func whitegramPinItem(_ item: EngineChatList.Item, pinned: Bool) -> EngineChatList.Item {
    guard case let .chatList(index) = item.index else { return item }
    // Only a presentation flag. The actual ordering lives in an independent Int rank.
    return EngineChatList.Item(
        id: item.id, index: .chatList(ChatListIndex(pinningIndex: pinned ? 0 : nil, messageIndex: index.messageIndex)),
        messages: item.messages, readCounters: item.readCounters, isMuted: item.isMuted,
        draft: item.draft, threadData: item.threadData, renderedPeer: item.renderedPeer,
        presence: item.presence, hasUnseenMentions: item.hasUnseenMentions,
        hasUnseenReactions: item.hasUnseenReactions, hasUnseenPollVotes: item.hasUnseenPollVotes,
        forumTopicData: item.forumTopicData, topForumTopicItems: item.topForumTopicItems,
        hasFailed: item.hasFailed, isContact: item.isContact, autoremoveTimeout: item.autoremoveTimeout,
        storyStats: item.storyStats, displayAsTopicList: item.displayAsTopicList,
        isPremiumRequiredToMessage: item.isPremiumRequiredToMessage, mediaDraftContentType: item.mediaDraftContentType
    )
}

private func whitegramProjectPins(base: ChatListNodeViewUpdate, state: WhitegramLocalPinState, order: [Int64], loaded: EngineChatList) -> ChatListNodeViewUpdate {
    let pinned = Set(order)
    let hidden = Set(state.hidden)
    let ordinary = base.list.items.filter { item in
        if case let .chatList(index) = item.index { return index.pinningIndex == nil }
        return false
    }
    var items = base.list.items.filter { item in
        let id = item.renderedPeer.peerId.toInt64()
        return !pinned.contains(id) && !hidden.contains(id)
    }
    // Cloud pins hidden locally belong at their real chronological position, even
    // when the server only supplies them in its first (pinned) page.
    for item in loaded.items where hidden.contains(item.renderedPeer.peerId.toInt64()) {
        let item = whitegramPinItem(item, pinned: false)
        let aboveLower = !base.list.hasEarlier || ordinary.first.map { item.index >= $0.index } == true
        let belowUpper = !base.list.hasLater || ordinary.last.map { item.index <= $0.index } == true
        if aboveLower && belowUpper { items.append(item) }
    }
    // Server-unpinned rows regain chronological order rather than staying in the pin block.
    items.sort { $0.index < $1.index }
    var ranks: [EnginePeer.Id: Int] = [:]
    if !base.list.hasLater {
        let loadedById = Dictionary(loaded.items.map { ($0.renderedPeer.peerId.toInt64(), $0) }, uniquingKeysWith: { first, _ in first })
        for (rank, id) in order.enumerated().reversed() {
            guard let item = loadedById[id] else { continue }
            items.append(whitegramPinItem(item, pinned: true))
            ranks[item.renderedPeer.peerId] = rank
        }
    }
    let result = EngineChatList(items: items, groupItems: base.list.groupItems,
        additionalItems: base.list.additionalItems, hasEarlier: base.list.hasEarlier,
        hasLater: base.list.hasLater, isLoading: base.list.isLoading)
    result.whitegramLocalPinRanks = ranks
    result.whitegramLocalPinBase = base.list
    return ChatListNodeViewUpdate(list: result, type: base.type, scrollPosition: base.scrollPosition)
}

private func whitegramLoadLocalPins(update: ChatListNodeViewUpdate, account: Account, pinLocation: TogglePeerChatPinnedLocation, shouldLoadCanMessagePeer: Bool) -> Signal<ChatListNodeViewUpdate, NoError> {
    return WhitegramLocalPins.projection(account: account, location: pinLocation)
    |> mapToSignal { projection -> Signal<ChatListNodeViewUpdate, NoError> in
        guard let (state, order) = projection else { return .single(update) }
        let fetchIds = (update.list.hasLater ? [] : order) + state.hidden
        if fetchIds.isEmpty {
            return .single(whitegramProjectPins(base: update, state: state, order: order, loaded: update.list))
        }
        let peerIds = Set(fetchIds.map { EnginePeer.Id($0) })
        // An independent include-only view fetches old dialogs outside the main page.
        // No local peer enters pinnedPeerIds (that path converts ranks to UInt16).
        let predicate = ChatListFilterPredicate(includePeerIds: [], excludePeerIds: [], pinnedPeerIds: [],
            messageTagSummary: nil, includeAdditionalPeerGroupIds: [Namespaces.PeerGroup.archive],
            include: { peer, _, _, _, _ in peerIds.contains(peer.id) })
        var first = true
        return account.viewTracker.tailChatListView(groupId: .root, filterPredicate: predicate,
            count: peerIds.count + 1, shouldLoadCanMessagePeer: shouldLoadCanMessagePeer)
        |> mapToSignal { view, _ -> Signal<ChatListNodeViewUpdate, NoError> in
            let loaded = ChatListNodeViewUpdate(list: EngineChatList(view, accountPeerId: account.peerId), type: .Generic, scrollPosition: nil)
            return chatListNodeViewUpdateWithCommunitySummaries(account: account, update: loaded)
        }
        |> mapToSignal { loaded -> Signal<ChatListNodeViewUpdate, NoError> in
            // Recheck membership on every off-page update, including moves/deletion.
            return WhitegramLocalPins.projection(account: account, location: pinLocation)
            |> map { current -> ChatListNodeViewUpdate in
                guard let (currentState, currentOrder) = current else { return update }
                let projected = whitegramProjectPins(base: update, state: currentState, order: currentOrder, loaded: loaded.list)
                defer { first = false }
                return ChatListNodeViewUpdate(list: projected.list, type: first ? update.type : .Generic, scrollPosition: first ? update.scrollPosition : nil)
            }
        }
    }
}

func whitegramLocalPinView(chatListLocation: ChatListControllerLocation, location: ChatListNodeLocation, account: Account, shouldLoadCanMessagePeer: Bool) -> Signal<ChatListNodeViewUpdate, NoError> {
    guard case let .chatList(group) = chatListLocation else {
        return chatListViewForLocation(chatListLocation: chatListLocation, location: location, account: account, shouldLoadCanMessagePeer: shouldLoadCanMessagePeer)
    }
    let pinLocation: TogglePeerChatPinnedLocation = location.filter.map { .filter($0.id) } ?? .group(group._asGroup())
    return WhitegramLocalPins.changes(accountId: account.id.int64)
    |> mapToSignal { enabled -> Signal<ChatListNodeViewUpdate, NoError> in
        if !enabled {
            return chatListViewForLocation(chatListLocation: chatListLocation, location: location, account: account, shouldLoadCanMessagePeer: shouldLoadCanMessagePeer)
        }
        return WhitegramLocalPins.projection(account: account, location: pinLocation)
        |> mapToSignal { initial -> Signal<ChatListNodeViewUpdate, NoError> in
            // Retain ordinary rows even when this window originally contained only pins.
            let additionalCount = (initial?.1.count ?? 0) + (initial?.0.hidden.count ?? 0)
            let base = chatListViewForLocation(chatListLocation: chatListLocation, location: location, account: account, shouldLoadCanMessagePeer: shouldLoadCanMessagePeer, whitegramAdditionalCount: additionalCount)
            return base |> mapToSignal { update -> Signal<ChatListNodeViewUpdate, NoError> in
                return whitegramLoadLocalPins(update: update, account: account, pinLocation: pinLocation, shouldLoadCanMessagePeer: shouldLoadCanMessagePeer)
            }
        }
    }
}
