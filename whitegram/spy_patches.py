"""Account-explicit observed presence/read-date consumers, staged atomically."""

from source_patches import SourcePatches
from online_history_patches import PEERS

READ_STATS = "submodules/TelegramCore/Sources/TelegramEngine/Messages/MessageReadStats.swift"
TITLES = {
    "submodules/TelegramUI/Components/ChatTitleView/Sources/ChatTitleView.swift": ("self", "peer.id", "userPresence", False),
    "submodules/TelegramUI/Components/ChatTitleView/Sources/ChatTitleComponent.swift": ("component", "peer.id", "userPresence", False),
    "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoData.swift": ("", "userPeerId", "presence", True),
}
SPY_RUNTIME_FILES = {
    name + ".swift": "submodules/TelegramCore/Sources/" + name + ".swift"
    for name in ("WhitegramSpyStore", "WhitegramSpyRuntime")
}


def stage_spy_patches(patches):
    for next_function, method, values in (
        ("updatePeerPresencesClean", "recordUsers", "users: peerPresences"),
        ("updatePeerPresenceLastActivities", "recordPresences", "statuses: peerPresences.mapValues { $0.status }"),
    ):
        # The closing brace is stable with or without the online-history hooks.
        before = f"}}\n\nfunc {next_function}("
        hook = f"    WhitegramSpyRuntime.{method}(transaction: transaction, accountPeerId: accountPeerId, {values}, acceptedPeerIds: Set(parsedPresences.keys))\n"
        after = hook + before
        if f"WhitegramSpyRuntime.{method}(" in patches.read(PEERS) and after not in patches.read(PEERS):
            raise ValueError("spy: partial presence hook")
        patches.replace("trackLastOnline", PEERS, before, after)

    before = "        if id.peerId.namespace == Namespaces.Peer.CloudUser {\n"
    after = before + "            if let date = WhitegramSpyRuntime.savedReadDate(accountPeerId: account.peerId, id: id) {\n                return .single(MessageReadStats(reactionCount: 0, peers: [EnginePeer(peer)], readTimestamps: [peer.id: date]))\n            }\n"
    patches.replace("saveReadDates", READ_STATS, before, after)
    before = "                    let date = outboxReadDateData.date\n"
    patches.replace("saveReadDates", READ_STATS, before, before + "                    WhitegramSpyRuntime.recordReadDate(accountPeerId: account.peerId, id: id, timestamp: date)\n")

    for path, (owner, peer, presence, expanded) in TITLES.items():
        suffix = ", expanded: true" if expanded else ""
        before = f"presence: EnginePeer.Presence({presence}), relativeTo: Int32(timestamp){suffix})"
        # ChatTitleView retains an AccountContext; the component exposes context.
        context = "context" if not owner else f"{owner}.context"
        after = f"presence: EnginePeer.Presence(WhitegramSpyRuntime.displayPresence({presence}, accountPeerId: {context}.account.peerId, peerId: {peer}, now: Int32(timestamp))), relativeTo: Int32(timestamp){suffix})"
        patches.replace("trackLastOnline", path, before, after)
    for path, marker, count in [(PEERS, "WhitegramSpyRuntime.", 2), (READ_STATS, "WhitegramSpyRuntime.", 2)] + [(path, "WhitegramSpyRuntime.displayPresence(", 1) for path in TITLES]:
        if patches.read(path).count(marker) != count:
            raise ValueError(f"spy: {path}: unexpected consumer inventory")


def apply_spy_patches(root):
    patches = SourcePatches(root)
    stage_spy_patches(patches)
    return patches.write()
