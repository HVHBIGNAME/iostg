import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext

@main
enum RuntimeTests {
    static var checks = 0
    static func check(_ condition: Bool, _ name: String) { checks += 1; if !condition { fatalError(name) } }
    static func value<T>(_ signal: Signal<T, NoError>) -> T {
        var result: T?
        let disposable = signal.start { result = $0 }
        disposable.dispose()
        return result!
    }
    static func item(_ id: Int64, timestamp: Int, pin: UInt16? = nil) -> EngineChatList.Item {
        EngineChatList.Item(id: PeerId(id), index: .chatList(ChatListIndex(pinningIndex: pin, messageIndex: MessageIndex(id: PeerId(id), timestamp: timestamp))), renderedPeer: EngineRenderedPeer(PeerId(id)))
    }
    static func main() throws {
        let account = Account(456789)
        let store = WhitegramLocalPinStore.shared
        store.reset(accountId: account.id.int64)
        defer { store.reset(accountId: account.id.int64) }
        check(WhitegramPreferences.set(true, for: "unlimitedPinnedChats"), "enable")
        let transaction = account.postbox.fixture
        for id: Int64 in [1, 2, 3, 4] {
            transaction.peers[PeerId(id)] = TestPeer(PeerId(id))
            transaction.indices[PeerId(id)] = (.root, ChatListIndex(pinningIndex: nil, messageIndex: MessageIndex(id: PeerId(id), timestamp: Int(id))))
        }
        transaction.cloud[0] = [.peer(PeerId(1)), .peer(PeerId(2))]
        transaction.preferences[PreferencesKeys.chatListFilters] = PreferencesEntry(ChatListFiltersState([7]))
        let cloud = transaction.cloud
        if case .done = value(WhitegramLocalPins.toggle(account: account, location: .group(.root), itemId: .peer(PeerId(3)))) {} else { fatalError("toggle") }
        check(WhitegramLocalPins.itemIds(account: account, transaction: transaction, location: .group(.root)) == [.peer(PeerId(3)), .peer(PeerId(1)), .peer(PeerId(2))], "engine reads effective pins")
        check(transaction.cloud == cloud, "pin makes no cloud mutation")
        baseFixture = EngineChatList(items: [item(4, timestamp: 100), item(2, timestamp: 10, pin: 1), item(1, timestamp: 20, pin: 0)], groupItems: [7], additionalItems: [8], hasEarlier: true)
        account.viewTracker.allItems = [item(3, timestamp: -1000), item(4, timestamp: 100), item(2, timestamp: 10), item(1, timestamp: 20)]
        var updates: [ChatListNodeViewUpdate] = []
        let view = whitegramLocalPinView(chatListLocation: .chatList(.root), location: .initial(filter: nil), account: account, shouldLoadCanMessagePeer: false)
        let disposable = view.start { updates.append($0) }
        var result = updates.last!.list
        check(result.items.map { $0.renderedPeer.peerId.toInt64() } == [4, 2, 1, 3], "fetches off-page old peer and orders mixed pins")
        check(result.whitegramLocalPinRanks[PeerId(3)] == 0, "independent rank")
        check(result.items.last!.draft == "draft" && result.items.last!.readCounters == 4 && result.items.last!.hasFailed && result.items.last!.storyStats == 8, "keeps native row data")
        check(result.whitegramLocalPinBase === baseFixture, "keeps unmodified pagination cursor source")
        check(result.groupItems == [7] && result.additionalItems == [8] && result.hasEarlier, "keeps archive ads pagination")
        check(additionalWindow == 3, "window compensates removed pins")
        check(account.viewTracker.pinRanksPassed == 0 && account.viewTracker.requestedCount == 4, "no UInt16 loading ranks")
        let expected: [PinnedItemId] = [.peer(PeerId(3)), .peer(PeerId(1)), .peer(PeerId(2))]
        check(WhitegramLocalPins.reorder(account: account, transaction: transaction, location: .group(.root), itemIds: Array(expected.reversed()), expected: expected), "mixed reorder commits")
        result = updates.last!.list
        check(result.items.map { $0.id.toInt64() } == [4, 3, 1, 2], "live reorder refresh")
        check(!WhitegramLocalPins.reorder(account: account, transaction: transaction, location: .group(.root), itemIds: expected, expected: expected), "stale reorder refuses")
        check(transaction.cloud == cloud, "reorder does not sync")
        check(WhitegramPreferences.set(false, for: "unlimitedPinnedChats"), "disable")
        check(updates.last!.list === baseFixture, "disable restores exact base")
        check(try store.state(accountId: account.id.int64, scope: .group(0)).local == [3], "disable retains store")
        if case .localPinError = value(WhitegramLocalPins.toggle(account: account, location: .group(.root), itemId: .peer(PeerId(3)))) {} else { fatalError("inflight toggle must refuse disable") }
        check(!WhitegramLocalPins.reorder(account: account, transaction: transaction, location: .group(.root), itemIds: expected, expected: expected), "inflight reorder refuses disable")
        check(WhitegramPreferences.set(true, for: "unlimitedPinnedChats"), "re-enable")
        check(updates.last!.list.whitegramLocalPinRanks[PeerId(2)] == 0, "restores saved reorder")
        disposable.dispose()
        let count = updates.count
        check(WhitegramPreferences.set(false, for: "unlimitedPinnedChats"), "post disposal change")
        check(updates.count == count, "observer disposal")
        check(WhitegramPreferences.set(true, for: "unlimitedPinnedChats"), "enable scope checks")
        let topBase = baseFixture
        baseFixture = EngineChatList(items: topBase.items + [item(3, timestamp: -1000)], hasEarlier: true, hasLater: true)
        let older = value(whitegramLocalPinView(chatListLocation: .chatList(.root), location: .navigation(filter: nil), account: account, shouldLoadCanMessagePeer: false)).list
        check(older.items.map { $0.id.toInt64() } == [4] && older.whitegramLocalPinRanks.isEmpty, "older page excludes pins instead of repeating them")
        check(older.whitegramLocalPinBase === baseFixture && older.hasLater, "older page retains real navigation anchors")
        baseFixture = topBase
        if case .done = value(WhitegramLocalPins.toggle(account: account, location: .group(.root), itemId: .peer(PeerId(1)))) {} else { fatalError("hide cloud pin") }
        let hiddenTop = value(whitegramLocalPinView(chatListLocation: .chatList(.root), location: .initial(filter: nil), account: account, shouldLoadCanMessagePeer: false)).list
        check(!hiddenTop.items.contains(where: { $0.id == PeerId(1) }), "old cloud-unpinned row does not jump ahead of intervening pages")
        baseFixture = EngineChatList(items: [item(4, timestamp: 10), item(5, timestamp: 30)], hasEarlier: true, hasLater: true)
        let hiddenOlder = value(whitegramLocalPinView(chatListLocation: .chatList(.root), location: .navigation(filter: nil), account: account, shouldLoadCanMessagePeer: false)).list
        check(hiddenOlder.items.map { $0.id.toInt64() } == [4, 1, 5], "locally hidden cloud pin is fetched into its chronological older page")
        check(hiddenOlder.whitegramLocalPinRanks.isEmpty, "locally unpinned row is ordinary")
        baseFixture = topBase
        if case .done = value(WhitegramLocalPins.toggle(account: account, location: .group(.root), itemId: .peer(PeerId(1)))) {} else { fatalError("restore cloud pin") }
        transaction.indices[PeerId(3)] = (Namespaces.PeerGroup.archive, transaction.indices[PeerId(3)]!.1)
        check(!WhitegramLocalPins.itemIds(account: account, transaction: transaction, location: .group(.root)).contains(.peer(PeerId(3))), "group move hides local root pin")
        if case .done = value(WhitegramLocalPins.toggle(account: account, location: .group(Namespaces.PeerGroup.archive), itemId: .peer(PeerId(3)))) {} else { fatalError("archive pin") }
        baseFixture = EngineChatList(items: [], hasEarlier: true)
        let archive = value(whitegramLocalPinView(chatListLocation: .chatList(.archive), location: .initial(filter: nil), account: account, shouldLoadCanMessagePeer: false)).list
        check(archive.items.map { $0.id.toInt64() } == [3], "archive independently loads off-page local pin")
        check(try store.state(accountId: account.id.int64, scope: .group(0)).local == [3], "archive operation preserves root scope")
        if case .done = value(WhitegramLocalPins.toggle(account: account, location: .filter(7), itemId: .peer(PeerId(3)))) {} else { fatalError("filter pin") }
        check(WhitegramLocalPins.itemIds(account: account, transaction: transaction, location: .filter(7)) == [.peer(PeerId(3))], "filter explicit pin includes archived peer")
        let folder = value(whitegramLocalPinView(chatListLocation: .chatList(.root), location: .initial(filter: ChatListFilter(7)), account: account, shouldLoadCanMessagePeer: false)).list
        check(folder.items.map { $0.id.toInt64() } == [3], "folder view projects explicit local pin outside its base")
        if case .localPinError = value(WhitegramLocalPins.toggle(account: account, location: .filter(8), itemId: .peer(PeerId(3)))) {} else { fatalError("deleted filter") }
        transaction.indices.removeValue(forKey: PeerId(3))
        check(WhitegramLocalPins.itemIds(account: account, transaction: transaction, location: .filter(7)).isEmpty, "deleted peer hidden")
        check(transaction.cloud == cloud, "scope actions do not mutate server")
        try WhitegramPreferences.setUsesSeparateSettings(true, accountId: 456790)
        check(WhitegramPreferences.activateAccount(456790) && WhitegramPreferences.set(false, for: "unlimitedPinnedChats"), "switch to separately configured account")
        check(WhitegramLocalPins.enabled(accountId: account.id.int64) && !WhitegramLocalPins.enabled(accountId: 456790), "runtime reads explicit account preference rather than active account")
        let corrupt = Data("invalid".utf8)
        UserDefaults.standard.set(corrupt, forKey: WhitegramLocalPinStore.key(accountId: account.id.int64))
        if case .localPinError = value(WhitegramLocalPins.toggle(account: account, location: .group(.root), itemId: .peer(PeerId(4)))) {} else { fatalError("corruption must surface error") }
        check(UserDefaults.standard.data(forKey: WhitegramLocalPinStore.key(accountId: account.id.int64)) == corrupt, "runtime corruption preserves bytes")
        print("\(checks) actual local-pin runtime/list checks passed against explicit API fixtures")
    }
}
