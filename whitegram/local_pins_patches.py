"""Exact local-pin overlay hooks for the assembled Telegram 13 source tree."""

import os
import tempfile
from copy import deepcopy
from dataclasses import dataclass
from pathlib import Path

from source_patches import SourcePatches

CORE = "submodules/TelegramCore/Sources/"
LIST = "submodules/ChatListUI/Sources/"
RUNTIME_FILES = {
    "WhitegramLocalPinPolicy.swift": CORE + "Settings/WhitegramLocalPinPolicy.swift",
    "WhitegramLocalPinRuntime.swift": CORE + "Settings/WhitegramLocalPinRuntime.swift",
    "WhitegramLocalPinList.swift": LIST + "Node/WhitegramLocalPinList.swift",
}
LOCAL_PINS_RUNTIME_FILES = RUNTIME_FILES
LOCAL_PINS_REQUIRED_DEPENDENCIES = {}
# UI availability for this local ordering adapter, not device/parity certification.
LOCAL_PINS_BOOLEAN_CAPABILITIES = {"unlimitedPinnedChats": True}


@dataclass(frozen=True)
class LocalPinsEdit:
    feature: str
    path: str
    before: str
    after: str
    count: int = 1


def local_pins_edits() -> tuple[LocalPinsEdit, ...]:
    edits = []

    def edit(feature, path, before, after, count=1):
        edits.append(LocalPinsEdit(feature, path, before, after, count))

    peers = CORE + "TelegramEngine/Peers/TelegramEnginePeers.swift"
    anchor = "        public func toggleItemPinned(location: TogglePeerChatPinnedLocation, itemId: PinnedItemId) -> Signal<TogglePeerChatPinnedResult, NoError> {\n"
    edit("local-pins-toggle", peers, anchor, anchor.replace("itemId: PinnedItemId)", "itemId: PinnedItemId, whitegramLocalOperation: Bool = false)"))
    anchor = "            return _internal_toggleItemPinned(postbox: self.account.postbox, accountPeerId: self.account.peerId, location: location, itemId: itemId)\n"
    edit("local-pins-toggle", peers, anchor, """            if whitegramLocalOperation || WhitegramLocalPins.enabled(accountId: self.account.id.int64) {
                return WhitegramLocalPins.toggle(account: self.account, location: location, itemId: itemId)
            }
""" + anchor)
    anchor = "                return _internal_getPinnedItemIds(transaction: transaction, location: location)\n"
    edit("local-pins-menu", peers, anchor, "                return WhitegramLocalPins.itemIds(account: self.account, transaction: transaction, location: location)\n")
    anchor = "        public func reorderPinnedItemIds(location: TogglePeerChatPinnedLocation, itemIds: [PinnedItemId]) -> Signal<Bool, NoError> {\n"
    edit("local-pins-reorder", peers, anchor, anchor.replace("itemIds: [PinnedItemId])", "itemIds: [PinnedItemId], whitegramExpected: [PinnedItemId]? = nil, whitegramLocalOperation: Bool = false)"))
    anchor = "                return _internal_reorderPinnedItemIds(transaction: transaction, location: location, itemIds: itemIds)\n"
    edit("local-pins-reorder", peers, anchor, """                if whitegramLocalOperation || WhitegramLocalPins.enabled(accountId: self.account.id.int64) {
                    return WhitegramLocalPins.reorder(account: self.account, transaction: transaction, location: location, itemIds: itemIds, expected: whitegramExpected)
                }
""" + anchor)

    toggle = CORE + "TelegramEngine/Peers/TogglePeerChatPinned.swift"
    anchor = "public enum TogglePeerChatPinnedResult {\n    case done\n"
    edit("local-pins-errors", toggle, anchor, anchor + "    case localPinError\n")

    model = CORE + "TelegramEngine/Messages/ChatList.swift"
    anchor = "    public let items: [Item]\n    public let groupItems: [GroupItem]\n"
    edit("local-pins-projection", model, anchor, """    public var whitegramLocalPinRanks: [EnginePeer.Id: Int] = [:]
    public var whitegramLocalPinBase: EngineChatList?
""" + anchor)
    anchor = "    public static func ==(lhs: EngineChatList, rhs: EngineChatList) -> Bool {\n"
    edit("local-pins-projection", model, anchor, anchor + "        if lhs.whitegramLocalPinRanks != rhs.whitegramLocalPinRanks { return false }\n")

    node = LIST + "Node/ChatListNode.swift"
    anchor = "context.engine.peers.toggleItemPinned(location: location, itemId: itemId)"
    edit("local-pins-toggle", node, anchor, "context.engine.peers.toggleItemPinned(location: location, itemId: itemId, whitegramLocalOperation: strongSelf.chatListView?.originalList.whitegramLocalPinBase != nil)")
    anchor = "            return chatListViewForLocation(chatListLocation: location, location: listLocation, account: context.account, shouldLoadCanMessagePeer: shouldLoadCanMessagePeer)\n"
    edit("local-pins-loading", node, anchor, """            let whitegramView: Signal<ChatListNodeViewUpdate, NoError>
            if case .chatList = mode {
                whitegramView = whitegramLocalPinView(chatListLocation: location, location: listLocation, account: context.account, shouldLoadCanMessagePeer: shouldLoadCanMessagePeer)
            } else {
                whitegramView = chatListViewForLocation(chatListLocation: location, location: listLocation, account: context.account, shouldLoadCanMessagePeer: shouldLoadCanMessagePeer)
            }
            return whitegramView
""")
    location = LIST + "Node/ChatListNodeLocation.swift"
    anchor = "private func chatListNodeViewUpdateWithCommunitySummaries(account: Account, update: ChatListNodeViewUpdate) -> Signal<ChatListNodeViewUpdate, NoError> {\n"
    edit("local-pins-loading", location, anchor, anchor.replace("private func", "internal func", 1))
    anchor = "public func chatListViewForLocation(chatListLocation: ChatListControllerLocation, location: ChatListNodeLocation, account: Account, shouldLoadCanMessagePeer: Bool) -> Signal<ChatListNodeViewUpdate, NoError> {\n"
    edit("local-pins-pagination", location, anchor, anchor.replace("shouldLoadCanMessagePeer: Bool)", "shouldLoadCanMessagePeer: Bool, whitegramAdditionalCount: Int = 0)"))
    anchor = "signal = account.viewTracker.tailChatListView(groupId: groupId._asGroup(), filterPredicate: filterPredicate, count: count, shouldLoadCanMessagePeer: shouldLoadCanMessagePeer)"
    edit("local-pins-pagination", location, anchor, anchor.replace("count: count,", "count: count + whitegramAdditionalCount,"))
    anchor = "return account.viewTracker.aroundChatListView(groupId: groupId._asGroup(), filterPredicate: filterPredicate, index: index, count: 80, shouldLoadCanMessagePeer: shouldLoadCanMessagePeer)"
    edit("local-pins-pagination", location, anchor, anchor.replace("count: 80,", "count: 80 + whitegramAdditionalCount,"), count=2)
    anchor = "                let originalList = chatListView.originalList\n"
    edit("local-pins-pagination", node, anchor, "                let originalList = chatListView.originalList.whitegramLocalPinBase ?? chatListView.originalList\n")
    anchor = "range.lastIndex >= originalList.items.count - 5, originalList.hasEarlier"
    edit("local-pins-pagination", node, anchor, "range.lastIndex >= (chatListView.originalList.whitegramLocalPinBase == nil ? originalList.items.count : chatListView.filteredEntries.count) - 5, originalList.hasEarlier")
    anchor = "                    return engine.peers.getPinnedItemIds(location: location)\n                    |> mapToSignal { itemIds -> Signal<Bool, NoError> in\n                        var itemIds = itemIds\n"
    edit("local-pins-reorder", node, anchor, anchor.replace("                        var itemIds", "                        let whitegramExpectedPins = itemIds\n                        var itemIds"))
    anchor = "                            return engine.peers.reorderPinnedItemIds(location: location, itemIds: itemIds)\n"
    edit("local-pins-reorder", node, anchor, anchor.replace("itemIds: itemIds)", "itemIds: itemIds, whitegramExpected: whitegramExpectedPins, whitegramLocalOperation: (transactionOpaqueState as? ChatListOpaqueTransactionState)?.chatListView.originalList.whitegramLocalPinBase != nil)"))
    anchor = """                            switch result {
                            case .done:
                                break
                            case let .limitExceeded(count, _):
"""
    edit("local-pins-errors", node, anchor, anchor.replace("                            case let .limitExceeded", """                            case .localPinError:
                                strongSelf.present?(textAlertController(context: context, title: nil, text: "The local pin could not be saved. The chat may have moved or the local store is unavailable.", actions: [TextAlertAction(type: .defaultAction, title: context.sharedContext.currentPresentationData.with { $0 }.strings.Common_OK, action: {})]))
                            case let .limitExceeded"""))

    menu = LIST + "ChatContextMenus.swift"
    anchor = "            let isPinned = pinnedItemIds.contains(.peer(peerId))\n"
    edit("local-pins-menu", menu, anchor, anchor + "            let whitegramLocalPinMode = WhitegramLocalPins.enabled(accountId: context.account.id.int64)\n")
    anchor = "context.engine.peers.toggleItemPinned(location: location, itemId: .peer(peerId))"
    edit("local-pins-toggle", menu, anchor, "context.engine.peers.toggleItemPinned(location: location, itemId: .peer(peerId), whitegramLocalOperation: whitegramLocalPinMode)")
    anchor = """                                    switch result {
                                    case .done:
                                        f(.default)
                                    case let .limitExceeded(count, _):
"""
    edit("local-pins-errors", menu, anchor, anchor.replace("                                    case let .limitExceeded", """                                    case .localPinError:
                                        f(.default)
                                        chatListController?.present(textAlertController(context: context, title: nil, text: "The local pin could not be saved. The chat may have moved or the local store is unavailable.", actions: [TextAlertAction(type: .defaultAction, title: strings.Common_OK, action: {})]), in: .window(.root))
                                    case let .limitExceeded"""))

    entries = LIST + "Node/ChatListNodeEntries.swift"
    anchor = "    struct PeerEntryData: Equatable {\n        var index: EngineChatList.Item.Index\n"
    edit("local-pins-rank", entries, anchor, anchor + "        var whitegramLocalPinRank: Int?\n")
    anchor = "            displayAsTopicList: Bool\n        ) {\n"
    edit("local-pins-rank", entries, anchor, "            displayAsTopicList: Bool,\n            whitegramLocalPinRank: Int? = nil\n        ) {\n            self.whitegramLocalPinRank = whitegramLocalPinRank\n")
    anchor = "        static func ==(lhs: PeerEntryData, rhs: PeerEntryData) -> Bool {\n"
    edit("local-pins-rank", entries, anchor, anchor + "            if lhs.whitegramLocalPinRank != rhs.whitegramLocalPinRank { return false }\n")
    anchor = "    static func <(lhs: ChatListNodeEntry, rhs: ChatListNodeEntry) -> Bool {\n        return lhs.sortIndex < rhs.sortIndex\n"
    edit("local-pins-rank", entries, anchor, """    static func <(lhs: ChatListNodeEntry, rhs: ChatListNodeEntry) -> Bool {
        if case let .PeerEntry(left) = lhs, case let .PeerEntry(right) = rhs,
           let l = left.whitegramLocalPinRank, let r = right.whitegramLocalPinRank {
            return l > r
        }
        return lhs.sortIndex < rhs.sortIndex
""")
    anchor = "            displayAsTopicList: entry.displayAsTopicList\n        ))\n"
    edit("local-pins-rank", entries, anchor, "            displayAsTopicList: entry.displayAsTopicList,\n            whitegramLocalPinRank: view.whitegramLocalPinRanks[entry.renderedPeer.peerId]\n        ))\n")
    anchor = '    Logger.shared.log("AccountManager", "logoutFromAccount \\(id)")\n    return accountManager.transaction { transaction -> Void in\n'
    edit("local-pins-account-removal", CORE + "Account/AccountManager.swift", anchor,
         anchor + "        WhitegramLocalPinStore.shared.reset(accountId: id.int64)\n")
    anchor = "            return _internal_updateChatListFiltersInteractively(postbox: self.account.postbox, f)\n"
    edit("local-pins-filter-removal", peers, anchor, """            return _internal_updateChatListFiltersInteractively(postbox: self.account.postbox) { current in
                let updated = f(current)
                let retained = Set(updated.map { $0.id })
                let removed = current.filter { !retained.contains($0.id) }
                do {
                    try WhitegramLocalPinStore.shared.removeScopes(accountId: self.account.id.int64, scopes: removed.map { .filter($0.id) })
                } catch {
                    NSLog("Whitegram: could not remove local folder pins (%@)", String(describing: type(of: error)))
                    return current
                }
                return updated
            }
""")
    return tuple(edits)


def local_pins_patches(patches: SourcePatches) -> None:
    saved = deepcopy((patches.original, patches.pending, patches.features))
    try:
        for edit in local_pins_edits():
            value = patches.read(edit.path)
            installed = value.count(edit.after)
            remaining = value.replace(edit.after, "")
            if installed:
                if installed != edit.count or edit.before in remaining:
                    raise ValueError(f"{edit.feature}: mixed/duplicate hook in {edit.path}")
            elif value.count(edit.before) != edit.count:
                raise ValueError(f"{edit.feature}: expected {edit.count} exact anchors in {edit.path}")
            patches.replace(edit.feature, edit.path, edit.before, edit.after, edit.count)
    except Exception:
        patches.original, patches.pending, patches.features = saved
        raise


def _temporary(path: Path, data: bytes) -> Path:
    fd, name = tempfile.mkstemp(prefix=".whitegram-local-pins-", dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, path.stat().st_mode)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise
    return temporary


def apply_local_pins_patches(root: Path) -> dict[str, list[str]]:
    root = Path(root).resolve()
    preimages = {}
    patches = SourcePatches(root)
    for relative in sorted({edit.path for edit in local_pins_edits()}):
        path = root / relative
        if path.is_symlink() or not path.resolve().is_relative_to(root):
            raise ValueError(f"local pins target escapes source root: {relative}")
        data = path.read_bytes()
        preimages[relative] = data
        patches.original[relative] = data.decode("utf-8").replace("\r\n", "\n")
        patches.pending[relative] = patches.original[relative]
    local_pins_patches(patches)
    prepared, backups, committed = {}, {}, []
    retain_backups = False
    try:
        for relative, value in patches.pending.items():
            if value == patches.original[relative]:
                continue
            original = preimages[relative]
            if b"\r\n" in original:
                value = value.replace("\n", "\r\n")
            prepared[relative] = _temporary(root / relative, value.encode("utf-8"))
            backups[relative] = _temporary(root / relative, original)
        for relative, original in preimages.items():
            if (root / relative).read_bytes() != original:
                raise ValueError(f"local pins source changed during preflight: {relative}")
        for relative, temporary in prepared.items():
            os.replace(temporary, root / relative)
            committed.append(relative)
    except Exception:
        try:
            for relative in reversed(committed):
                os.replace(backups[relative], root / relative)
        except OSError as error:
            retain_backups = True
            raise RuntimeError(f"local pins rollback failed; retained preimages: {backups}") from error
        raise
    finally:
        for temporary in prepared.values():
            temporary.unlink(missing_ok=True)
        if not retain_backups:
            for temporary in backups.values():
                temporary.unlink(missing_ok=True)
    return {feature: sorted(paths) for feature, paths in sorted(patches.features.items())}
