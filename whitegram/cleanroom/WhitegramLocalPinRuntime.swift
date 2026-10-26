import Foundation
import CoreFoundation
import Postbox
import SwiftSignalKit

public enum WhitegramLocalPins {
    public static func enabled(accountId: Int64) -> Bool {
        do {
            let scope = try WhitegramPreferences.scope(accountId: accountId)
            return try WhitegramPreferences.readProfileForTransfer(scope: scope) { values, _ in
                guard let flag = values["unlimitedPinnedChats"] as? NSNumber,
                      CFGetTypeID(flag) == CFBooleanGetTypeID() else { return false }
                return flag.boolValue
            }
        } catch {
            NSLog("Whitegram local pins: account preferences unavailable (%@)", String(describing: error))
            return false
        }
    }

    public static func scope(_ location: TogglePeerChatPinnedLocation) -> WhitegramLocalPinScope {
        switch location {
        case let .group(id): return .group(id.rawValue)
        case let .filter(id): return .filter(id)
        }
    }

    private static func ids(_ items: [PinnedItemId]) -> [Int64] {
        return items.map { item in
            switch item { case let .peer(id): return id.toInt64() }
        }
    }

    private static func cloudIds(transaction: Transaction, location: TogglePeerChatPinnedLocation) -> [PinnedItemId] {
        switch location {
        case let .group(groupId):
            return transaction.getPinnedItemIds(groupId: groupId)
        case let .filter(filterId):
            let filters = transaction.getPreferencesEntry(key: PreferencesKeys.chatListFilters)?.get(ChatListFiltersState.self)?.filters ?? []
            for filter in filters {
                if case let .filter(id, _, _, data) = filter, id == filterId {
                    return data.includePeers.pinnedPeers.map { .peer($0) }
                }
            }
            return []
        }
    }

    private static func eligible(transaction: Transaction, location: TogglePeerChatPinnedLocation, ids: [Int64]) -> Set<Int64> {
        if case let .filter(id) = location {
            let filters = transaction.getPreferencesEntry(key: PreferencesKeys.chatListFilters)?.get(ChatListFiltersState.self)?.filters ?? []
            guard filters.contains(where: { $0.id == id }) else { return [] }
        }
        return Set(ids.filter { value in
            let id = PeerId(value)
            guard let (group, _) = transaction.getPeerChatListIndex(id), let peer = transaction.getPeer(id) else { return false }
            if let community = peer as? TelegramCommunity, community.collapsedInDialogs != true { return false }
            if case let .group(expected) = location { return group == expected }
            return group == .root || group == Namespaces.PeerGroup.archive
        })
    }

    public static func itemIds(account: Account, transaction: Transaction, location: TogglePeerChatPinnedLocation) -> [PinnedItemId] {
        let server = cloudIds(transaction: transaction, location: location)
        guard enabled(accountId: account.id.int64) else { return server }
        do {
            let state = try WhitegramLocalPinStore.shared.state(accountId: account.id.int64, scope: scope(location))
            let cloud = ids(server)
            let members = eligible(transaction: transaction, location: location, ids: state.local + cloud)
            return state.effective(server: cloud, eligible: members).map { .peer(PeerId($0)) }
        } catch {
            NSLog("Whitegram local pins: store unavailable (%@)", String(describing: error))
            return server
        }
    }

    public static func toggle(account: Account, location: TogglePeerChatPinnedLocation, itemId: PinnedItemId) -> Signal<TogglePeerChatPinnedResult, NoError> {
        return account.postbox.transaction { transaction -> TogglePeerChatPinnedResult in
            do {
                guard enabled(accountId: account.id.int64) else { throw WhitegramLocalPinError.disabled }
                let server = ids(cloudIds(transaction: transaction, location: location))
                let id = ids([itemId])[0]
                try WhitegramLocalPinStore.shared.update(accountId: account.id.int64, scope: scope(location)) { state in
                    try state.toggle(id, server: server, eligible: eligible(transaction: transaction, location: location, ids: state.local + server + [id]))
                }
                return .done
            } catch {
                return .localPinError
            }
        }
    }

    public static func reorder(account: Account, transaction: Transaction, location: TogglePeerChatPinnedLocation, itemIds: [PinnedItemId], expected: [PinnedItemId]?) -> Bool {
        do {
            guard enabled(accountId: account.id.int64), let expected else { return false }
            let server = ids(cloudIds(transaction: transaction, location: location))
            try WhitegramLocalPinStore.shared.update(accountId: account.id.int64, scope: scope(location)) { state in
                try state.reorder(ids(itemIds), expected: ids(expected), server: server,
                    eligible: eligible(transaction: transaction, location: location, ids: state.local + server))
            }
            return true
        } catch {
            NSLog("Whitegram local pins: reorder refused (%@)", String(describing: error))
            return false
        }
    }

    public static func changes(accountId: Int64) -> Signal<Bool, NoError> {
        return Signal { subscriber in
            let center = NotificationCenter.default
            let emit = { subscriber.putNext(enabled(accountId: accountId)) }
            let local = center.addObserver(forName: WhitegramLocalPinStore.updatedNotification, object: nil, queue: nil) { notification in
                if notification.object as? Int64 == accountId { emit() }
            }
            let preferences = center.addObserver(forName: WhitegramPreferences.updatedNotification, object: nil, queue: nil) { _ in emit() }
            emit()
            return ActionDisposable { center.removeObserver(local); center.removeObserver(preferences) }
        }
    }

    public static func projection(account: Account, location: TogglePeerChatPinnedLocation) -> Signal<(WhitegramLocalPinState, [Int64])?, NoError> {
        return account.postbox.transaction { transaction -> (WhitegramLocalPinState, [Int64])? in
            guard enabled(accountId: account.id.int64) else { return nil }
            do {
                let state = try WhitegramLocalPinStore.shared.state(accountId: account.id.int64, scope: scope(location))
                let server = ids(cloudIds(transaction: transaction, location: location))
                let members = eligible(transaction: transaction, location: location, ids: state.local + server)
                var projectedState = state
                let cloud = Set(server)
                projectedState.hidden = state.hidden.filter { cloud.contains($0) && members.contains($0) }
                return (projectedState, state.effective(server: server, eligible: members))
            } catch {
                NSLog("Whitegram local pins: projection unavailable (%@)", String(describing: error))
                return nil
            }
        }
    }
}
