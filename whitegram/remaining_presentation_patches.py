"""Stage remaining presentation consumers on the assembled Telegram 13.0 overlay.

This module never installs files or edits the parent's preferences/router registries.
"""

from dataclasses import dataclass

from source_patches import SourcePatches

CORE = "submodules/TelegramCore/Sources/"
SETTINGS = "submodules/SettingsUI/Sources/"
PEER = "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/"
ROOT = "submodules/TelegramUI/Sources/TelegramRootController.swift"
APP = "submodules/TelegramUI/Sources/AppDelegate.swift"
LIST = "submodules/ChatListUI/Sources/Node/ChatListItem.swift"
TITLE = "submodules/TelegramUI/Components/ChatTitleView/Sources/ChatTitleView.swift"
BUBBLE = "submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift"
ITEMS = PEER + "PeerInfoProfileItems.swift"
SCREEN = PEER + "PeerInfoScreen.swift"
RUNTIME_FILES = {
    "WhitegramRemainingPresentationPolicy.swift": CORE + "WhitegramRemainingPresentationPolicy.swift",
    "WhitegramRemainingBadgePeer.swift": CORE + "WhitegramRemainingBadgePeer.swift",
    "WhitegramRemainingInformation.swift": SETTINGS + "WhitegramRemainingInformation.swift",
    "WhitegramRemainingBadgeService.swift": SETTINGS + "WhitegramRemainingBadgeService.swift",
    "WhitegramRemainingAppBadge.swift": SETTINGS + "WhitegramRemainingAppBadge.swift",
    "WhitegramRemainingPresentationController.swift": SETTINGS + "WhitegramRemainingPresentationController.swift",
    "WhitegramRemainingProfileItems.swift": PEER + "WhitegramRemainingProfileItems.swift",
}
RESOURCE_FILES = {
    f"tests/remaining_presentation/assets/{name}.imageset/{file}":
        f"submodules/TelegramUI/Images.xcassets/Components/{name}.imageset/{file}"
    for name in ("WGBadgeBlack", "WGBadgeWhite") for file in (name + ".png", "Contents.json")
}


def _replace(patches, feature, path, before, after, count=1):
    value = patches.read(path)
    if after in value and (value.count(after) != count or before in value.replace(after, "")):
        raise ValueError(f"{feature}: {path}: mixed or duplicate remaining presentation anchor")
    patches.replace(feature, path, before, after, count=count)


def _badge_patches(patches):
    feature = "hideWhitegramUserBadge"
    _replace(patches, feature, APP, "        whitegramInstallBackend()\n",
             "        whitegramInstallBackend()\n        whitegramInstallRemainingPresentation()\n")
    _replace(patches, feature, LIST, "    private var cachedDataDisposable = MetaDisposable()\n",
             "    private var cachedDataDisposable = MetaDisposable()\n    private let whitegramRemainingBadge = WhitegramRemainingBadgeBinding()\n")
    anchor = "        self.peerPresenceManager = PeerPresenceStatusManager(update: { [weak self] in\n"
    _replace(patches, feature, LIST, anchor, """        self.whitegramRemainingBadge.updated = { [weak self] in
            guard let self, let params = self.layoutParams else { return }
            let (_, apply) = self.asyncLayout()(params.0, params.6, params.1, params.2, params.3, params.4, params.5)
            apply(false, false)
        }
""" + anchor)
    anchor = "        if item.interaction.activateChatPreview == nil {\n"
    _replace(patches, feature, LIST, anchor, """        self.whitegramRemainingBadge.update(accountId: item.context.account.peerId.id._internalGetInt64Value(),
            userId: WhitegramPreferences.bool("hideWhitegramUserBadge") ? nil : whitegramRemainingBadgeUserId(peer?._asPeer()))

""" + anchor)
    anchor = "        let titleLayout = TextNode.asyncLayout(self.titleNode)\n"
    _replace(patches, feature, LIST, anchor, anchor + "        let whitegramRemainingBadge = self.whitegramRemainingBadge\n")
    anchor = "NSAttributedString(string: displayTitle, font: titleFont, textColor: textColor)"
    _replace(patches, feature, LIST, anchor,
             'NSAttributedString(string: displayTitle + (whitegramRemainingBadge.showsBadge(accountId: account.peerId.id._internalGetInt64Value(), userId: whitegramRemainingBadgeUserId(itemPeer.chatOrMonoforumMainPeer?._asPeer()), surface: .chatList) ? " ✦" : ""), font: titleFont, textColor: textColor)', count=2)

    _replace(patches, feature, TITLE, "    private var pointerInteraction: PointerInteraction?\n",
             "    private var pointerInteraction: PointerInteraction?\n    private let whitegramRemainingBadge = WhitegramRemainingBadgeBinding()\n")
    anchor = "        super.init(frame: CGRect())\n"
    _replace(patches, feature, TITLE, anchor, anchor + """        self.whitegramRemainingBadge.updated = { [weak self] in
            guard let self else { return }
            let content = self.titleContent
            self.titleContent = content
        }
""")
    anchor = "                if self.titleTextNode.segments != segments {\n"
    _replace(patches, feature, TITLE, anchor, """                var whitegramBadgeUserId: Int64?
                if case let .peer(peerView, customTitle, _, _, scheduled, _, _, _, _) = titleContent,
                   customTitle == nil, !scheduled, peerView.peerId != self.context.account.peerId,
                   !peerView.peerId.isRepliesOrVerificationCodes {
                    whitegramBadgeUserId = whitegramRemainingBadgeUserId(peerView.peer)
                }
                if WhitegramPreferences.bool("hideWhitegramUserBadge") { whitegramBadgeUserId = nil }
                self.whitegramRemainingBadge.update(accountId: self.context.account.peerId.id._internalGetInt64Value(), userId: whitegramBadgeUserId)
                if self.whitegramRemainingBadge.showsBadge(accountId: self.context.account.peerId.id._internalGetInt64Value(), userId: whitegramBadgeUserId, surface: .chatHeader) {
                    segments.append(.text(10001, NSAttributedString(string: " ✦", font: titleFont, textColor: titleTheme.rootController.navigationBar.primaryTextColor)))
                }

""" + anchor)

    _replace(patches, feature, BUBBLE, "    private var appliedItem: ChatMessageItem?\n",
             "    private var appliedItem: ChatMessageItem?\n    private let whitegramRemainingBadge = WhitegramRemainingBadgeBinding()\n")
    anchor = "        super.init(rotated: rotated)\n"
    _replace(patches, feature, BUBBLE, anchor, anchor + """        self.whitegramRemainingBadge.updated = { [weak self] in
            guard let item = self?.appliedItem else { return }
            item.controllerInteraction.requestMessageUpdate(item.message.id, false, nil)
        }
""")
    anchor = "        let translateToLanguage = item.associatedData.translateToLanguage\n        var isSummarized = false\n"
    _replace(patches, feature, BUBBLE, anchor, """        let whitegramBadgeUserId = (!isPreview && authorNameString != nil && !WhitegramPreferences.bool("hideWhitegramUserBadge"))
            ? whitegramRemainingBadgeUserId(effectiveAuthor) : nil
        if let name = authorNameString, selfReference.value?.whitegramRemainingBadge.showsBadge(
            accountId: item.context.account.peerId.id._internalGetInt64Value(), userId: whitegramBadgeUserId, surface: .post) == true {
            authorNameString = name + " ✦"
        }

""" + anchor)
    _replace(patches, feature, BUBBLE, "                authorNameColor: authorNameColor,\n",
             "                authorNameColor: authorNameColor,\n                whitegramBadgeUserId: whitegramBadgeUserId,\n")
    _replace(patches, feature, BUBBLE, "        authorNameColor: UIColor?,\n",
             "        authorNameColor: UIColor?,\n        whitegramBadgeUserId: Int64?,\n")
    anchor = "        strongSelf.appliedItem = item\n"
    _replace(patches, feature, BUBBLE, anchor, anchor + "        strongSelf.whitegramRemainingBadge.update(accountId: item.context.account.peerId.id._internalGetInt64Value(), userId: whitegramBadgeUserId)\n")


def _app_badge_patches(patches):
    _replace(patches, "appBadgeColorIsBlack", ROOT, "    private var storyUploadEventsDisposable: Disposable?\n",
             "    private var storyUploadEventsDisposable: Disposable?\n    private var whitegramRemainingAppBadge: WhitegramRemainingAppBadgeBinding?\n")
    anchor = "            self.applicationInFocusDisposable = (context.sharedContext.applicationBindings.applicationIsActive\n"
    _replace(patches, "appBadgeColorIsBlack", ROOT, anchor,
             "            self.whitegramRemainingAppBadge = WhitegramRemainingAppBadgeBinding(context: context)\n" + anchor)


def _scammer_patches(patches):
    _replace(patches, "scammerProtection", ITEMS, "    case community\n    case groupLocation\n", "    case remainingScammerWarning\n    case community\n    case groupLocation\n")
    anchor = "    let noteContextAction: (ASDisplayNode, ContextGesture?, CGPoint?) -> Void = { node, gesture, _ in\n"
    _replace(patches, "scammerProtection", ITEMS, anchor, """    if let item = whitegramRemainingScammerItem(data: data, presentationData: presentationData, interaction: interaction) {
        items[.remainingScammerWarning, default: []].append(item)
    }

""" + anchor)
    anchor = "    private(set) var data: PeerInfoScreenData?\n"
    _replace(patches, "scammerProtection", SCREEN, anchor, anchor + "    private var whitegramRemainingScammerObserver: WhitegramRemainingScammerObserver?\n")
    anchor = "        self.dataDisposable = combineLatest(\n"
    _replace(patches, "scammerProtection", SCREEN, anchor, """        self.whitegramRemainingScammerObserver = WhitegramRemainingScammerObserver { [weak self] in
            self?.requestLayout(animated: false)
        }

""" + anchor)


def remaining_presentation_patches(patches: SourcePatches) -> None:
    _badge_patches(patches)
    _app_badge_patches(patches)
    _scammer_patches(patches)


@dataclass(frozen=True)
class RemainingEdit:
    path: str
    before: str
    after: str
    count: int


def remaining_presentation_edits():
    class Recorder:
        def __init__(self):
            self.edits = []

        def read(self, path):
            return ""

        def replace(self, feature, path, before, after, count=1):
            self.edits.append(RemainingEdit(path, before, after, count))
    recorder = Recorder()
    remaining_presentation_patches(recorder)
    return recorder.edits


def apply_remaining_presentation_patches(root) -> dict[str, list[str]]:
    patches = SourcePatches(root)
    remaining_presentation_patches(patches)
    return patches.write()
