"""Independent client-interface hooks for the assembled Telegram 13 source pin.

Runtime installation is owned by the caller. Staging validates exact anchors;
the writing wrapper additionally preserves byte preimages and rolls back I/O failures.
"""

from dataclasses import dataclass
import os
from pathlib import Path
import tempfile

from source_patches import SourcePatches


CORE = "submodules/TelegramCore/Sources/"
PRESENTATION = "submodules/TelegramPresentationData/Sources/"
LIST = "submodules/ChatListUI/Sources/Node/"
TITLE = "submodules/TelegramUI/Components/ChatTitleView/Sources/"
PEER = "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/"
REACTIONS = "submodules/Components/ReactionButtonListComponent/Sources/"

CLIENT_INTERFACE_RUNTIME_FILES = {
    "WhitegramClientInterfacePolicy.swift": CORE + "Settings/WhitegramClientInterfacePolicy.swift",
    "WhitegramClientInterfaceSettings.swift": CORE + "Settings/WhitegramClientInterfaceSettings.swift",
    "WhitegramClientInterfaceTheme.swift": PRESENTATION + "WhitegramClientInterfaceTheme.swift",
    "WhitegramClientInterfaceReactionGlow.swift": REACTIONS + "WhitegramClientInterfaceReactionGlow.swift",
    "WhitegramClientInterfaceProfileUpdates.swift": PEER + "WhitegramClientInterfaceProfileUpdates.swift",
    "WhitegramLocalPremiumPolicy.swift": CORE + "Settings/WhitegramLocalPremiumPolicy.swift",
    "WhitegramLocalPremiumPresentation.swift": CORE + "Settings/WhitegramLocalPremiumPresentation.swift",
    "WhitegramLocalPremiumController.swift": "submodules/SettingsUI/Sources/WhitegramLocalPremiumController.swift",
    "WhitegramAccountStripOrder.swift": CORE + "Settings/WhitegramAccountStripOrder.swift",
    "WhitegramAccountStripItem.swift": PEER + "WhitegramAccountStripItem.swift",
}

# True means a functional consumer is supplied, not proven original visual parity.
CLIENT_INTERFACE_BOOLEAN_CAPABILITIES = {
    "newChatListUI": True,
    "newChatHeaderStyle": True,
    "classicInterface": False,  # Header material only; the full 11.15 shell is unresolved.
    "oledMode": True,
    "reactionButtonGlow": True,
    "roundProfileButtons": True,
    "localPremium": True,  # Self-profile presentation and local editor only.
    "unlimitedPinnedChats": False,
}

CLIENT_INTERFACE_REQUIRED_DEPENDENCIES = {}  # Existing targets already import all used modules.
CLIENT_INTERFACE_REQUIRED_BINDINGS = {
    "localPremium": "WhitegramLocalPremiumController(context: context)",
}


@dataclass(frozen=True)
class ClientInterfaceEdit:
    feature: str
    path: str
    before: str
    after: str
    count: int = 1


def client_interface_edits() -> tuple[ClientInterfaceEdit, ...]:
    edits = []

    def edit(feature, path, before, after, count=1):
        edits.append(ClientInterfaceEdit(feature, path, before, after, count))

    item = LIST + "ChatListItem.swift"
    anchor = "        return { item, params, first, last, firstWithHeader, nextIsPinned, nextHasActiveRevealControls in\n"
    edit("newChatListUI", item, anchor, anchor + """            let whitegramInterface = WhitegramClientInterfaceSettings.current
            let whitegramOriginalParams = params
            let whitegramCards: Bool
            if case let .peer(peerData) = item.content {
                whitegramCards = whitegramInterface.cards && !item.editing && !item.interaction.isInlineMode && !item.useCommunityViewLayout && peerData.customMessageListData == nil
            } else {
                whitegramCards = false
            }
            let params = whitegramCards ? ListViewItemLayoutParams(width: params.width, leftInset: params.leftInset + 8.0, rightInset: params.rightInset + 8.0, availableHeight: params.availableHeight, isStandalone: params.isStandalone) : params
""")
    anchor = "                    strongSelf.layoutParams = (item, first, last, firstWithHeader, nextIsPinned, nextHasActiveRevealControls, params, countersSize)\n"
    edit("newChatListUI", item, anchor, anchor.replace(", params, countersSize)", ", whitegramOriginalParams, countersSize)"))
    anchor = "            let rawContentRect = CGRect(origin: CGPoint(x: 2.0, y: layoutOffset + rawContentTopInset), size: CGSize(width: rawContentWidth, height: itemHeight - 12.0 - 9.0))\n"
    edit("newChatListUI", item, anchor, "            if whitegramCards { itemHeight += 6.0 }\n" + anchor)
    anchor = "                    strongSelf.separatorNode.isHidden = hideCommunitySeparator\n"
    edit("newChatListUI", item, anchor, "                    strongSelf.separatorNode.isHidden = hideCommunitySeparator || whitegramCards\n")
    anchor = "                    transition.updateFrame(node: strongSelf.backgroundNode, frame: CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: CGSize(width: layout.contentSize.width, height: itemHeight)))\n"
    edit("newChatListUI", item, anchor, """                    let whitegramCardFrame = whitegramCards ? whitegramInterface.cardFrame(width: Double(layout.contentSize.width), height: Double(itemHeight), leftInset: Double(params.leftInset - 8.0), rightInset: Double(params.rightInset - 8.0)) : CGRect(origin: .zero, size: CGSize(width: layout.contentSize.width, height: itemHeight))
                    transition.updateFrame(node: strongSelf.backgroundNode, frame: whitegramCardFrame)
                    transition.updateCornerRadius(node: strongSelf.backgroundNode, cornerRadius: whitegramCards ? 12.0 : 0.0)
""")
    anchor = "                    if animated {\n                        transition.updateBackgroundColor(node: strongSelf.backgroundNode, color: backgroundColor)\n"
    edit("newChatListUI", item, anchor, "                    let whitegramBackgroundColor = whitegramCards && backgroundColor == .clear ? item.presentationData.theme.list.itemBlocksBackgroundColor : backgroundColor\n" + anchor.replace("color: backgroundColor)", "color: whitegramBackgroundColor)"))
    anchor = "                        strongSelf.backgroundNode.backgroundColor = backgroundColor\n"
    edit("newChatListUI", item, anchor, "                        strongSelf.backgroundNode.backgroundColor = whitegramBackgroundColor\n")
    anchor = "                    transition.updateCornerRadius(node: strongSelf.highlightedBackgroundNode, cornerRadius: strongSelf.isRevealOptionsActive ? 26.0 : 0.0)\n"
    edit("newChatListUI", item, anchor, """                    if whitegramCards { strongSelf.highlightedBackgroundNode.frame = whitegramCardFrame.offsetBy(dx: strongSelf.revealOffset, dy: 0.0) }
                    transition.updateCornerRadius(node: strongSelf.highlightedBackgroundNode, cornerRadius: strongSelf.isRevealOptionsActive ? 26.0 : (whitegramCards ? 12.0 : 0.0))
""")
    # A new presentation identity makes the list diff update recycled rows even when only a flag changed.
    node = LIST + "ChatListNode.swift"
    anchor = "            combineLatest(self.statePromise.get(), WhitegramAppearanceSettings.signal()) |> map { value, _ in value },\n"
    edit("client-interface-live-list", node, anchor, """            combineLatest(self.statePromise.get(), WhitegramAppearanceSettings.signal(), WhitegramClientInterfaceSettings.signal()) |> map { value, _, _ in
                var value = value
                let data = value.presentationData
                value.presentationData = ChatListPresentationData(theme: data.theme, fontSize: data.fontSize, strings: data.strings, dateTimeFormat: data.dateTimeFormat, nameSortOrder: data.nameSortOrder, nameDisplayOrder: data.nameDisplayOrder, disableAnimations: data.disableAnimations)
                return value
            },
""")

    title = TITLE + "ChatTitleView.swift"
    anchor = "    private var validLayout: CGSize?\n"
    edit("newChatHeaderStyle", title, anchor, anchor + "    private var whitegramInterfaceDisposable: Disposable?\n")
    anchor = "        super.init(frame: CGRect())\n"
    edit("newChatHeaderStyle", title, anchor, anchor + """        self.whitegramInterfaceDisposable = (WhitegramClientInterfaceSettings.signal() |> deliverOnMainQueue).start(next: { [weak self] _ in
            guard let self, let size = self.validLayout else { return }
            let _ = self.updateLayout(availableSize: size, transition: .immediate)
        })
""")
    anchor = "    @objc private func buttonPressed() {\n"
    edit("newChatHeaderStyle", title, anchor, "    deinit { self.whitegramInterfaceDisposable?.dispose() }\n\n" + anchor)
    anchor = "        let titleInfoSpacing: CGFloat = 0.0\n"
    edit("newChatHeaderStyle", title, anchor, "        let titleInfoSpacing: CGFloat = WhitegramClientInterfaceSettings.current.updatedHeader ? 2.0 : 0.0\n")
    anchor = "            titleFrame.origin.x = max(titleFrame.origin.x, leftIconWidth)\n"
    edit("newChatHeaderStyle", title, anchor, "            titleFrame.origin.x = WhitegramClientInterfaceSettings.current.updatedHeader ? max(20.0, leftIconWidth) : max(titleFrame.origin.x, leftIconWidth)\n")
    anchor = "        componentTransition.setFrame(view: self.backgroundView, frame: backgroundFrame)\n"
    edit("classicInterface-header", title, anchor, "        self.backgroundView.isHidden = WhitegramClientInterfaceSettings.current.headerWithoutGlass\n" + anchor)
    component = TITLE + "ChatTitleComponent.swift"
    anchor = "        private weak var state: EmptyComponentState?\n"
    edit("newChatHeaderStyle", component, anchor, anchor + "        private var whitegramInterfaceObserver: NSObjectProtocol?\n")
    anchor = "            self.contentContainer.addGestureRecognizer(recognizer)\n"
    edit("newChatHeaderStyle", component, anchor, anchor + """            self.whitegramInterfaceObserver = NotificationCenter.default.addObserver(forName: WhitegramPreferences.updatedNotification, object: nil, queue: .main) { [weak self] _ in
                self?.state?.updated(transition: .immediate)
            }
""")
    anchor = "        @objc private func onTapGesture(_ recognizer: TapLongTapOrDoubleTapGestureRecognizer) {\n"
    edit("newChatHeaderStyle", component, anchor, "        deinit { if let observer = self.whitegramInterfaceObserver { NotificationCenter.default.removeObserver(observer) } }\n\n" + anchor)
    anchor = "            if component.displayBackground {\n"
    edit("classicInterface-header", component, anchor, "            if component.displayBackground && !WhitegramClientInterfaceSettings.current.headerWithoutGlass {\n")
    anchor = "            let titleFrame = CGRect(origin: CGPoint(x: titleLeftIconsWidth + floor((containerFrame.width - titleSize.width - titleLeftIconsWidth - titleRightIconsWidth) * 0.5), y: floor((containerFrame.height - contentSize.height) * 0.5)), size: titleSize)\n"
    edit("newChatHeaderStyle", component, anchor, "            let titleFrame = CGRect(origin: CGPoint(x: titleLeftIconsWidth + (WhitegramClientInterfaceSettings.current.updatedHeader ? containerSideInset : floor((containerFrame.width - titleSize.width - titleLeftIconsWidth - titleRightIconsWidth) * 0.5)), y: floor((containerFrame.height - contentSize.height) * 0.5)), size: titleSize)\n")
    anchor = "            let subtitleFrame = CGRect(origin: CGPoint(x: floor((containerFrame.width - subtitleSize.width) * 0.5), y: titleFrame.maxY), size: subtitleSize)\n"
    edit("newChatHeaderStyle", component, anchor, "            let subtitleFrame = CGRect(origin: CGPoint(x: WhitegramClientInterfaceSettings.current.updatedHeader ? titleFrame.minX : floor((containerFrame.width - subtitleSize.width) * 0.5), y: titleFrame.maxY + (WhitegramClientInterfaceSettings.current.updatedHeader ? 2.0 : 0.0)), size: subtitleSize)\n")

    theme = PRESENTATION + "MakePresentationTheme.swift"
    anchor = "\n    return theme\n}"
    edit("oledMode", theme, anchor, "\n    return whitegramClientInterfaceTheme(theme)\n}", count=3)
    data = PRESENTATION + "PresentationData.swift"
    anchor = "    return combineLatest(accountManager.sharedData(keys: [SharedDataKeys.localizationSettings, ApplicationSpecificSharedDataKeys.presentationThemeSettings, ApplicationSpecificSharedDataKeys.contactSynchronizationSettings]), systemUserInterfaceStyle)\n"
    edit("oledMode-live-refresh", data, anchor, "    return combineLatest(combineLatest(accountManager.sharedData(keys: [SharedDataKeys.localizationSettings, ApplicationSpecificSharedDataKeys.presentationThemeSettings, ApplicationSpecificSharedDataKeys.contactSynchronizationSettings]), WhitegramClientInterfaceSettings.signal()) |> map { data, _ in data }, systemUserInterfaceStyle)\n")

    reaction = REACTIONS + "ReactionButtonListComponent.swift"
    anchor = "    fileprivate func apply(layout: Layout, animation: ListViewItemUpdateAnimation, arguments: ReactionButtonsAsyncLayoutContainer.Arguments) {\n"
    edit("reactionButtonGlow", reaction, anchor, "    private let whitegramInterfaceGlow = WhitegramClientInterfaceReactionGlow()\n\n" + anchor)
    anchor = "        self.buttonNode.update(layout: layout.backgroundLayout)\n"
    edit("reactionButtonGlow", reaction, anchor, anchor + """        self.whitegramInterfaceGlow.update(layer: self.buttonNode.layer, color: UIColor(argb: layout.backgroundLayout.colors.foreground), isTag: layout.spec.component.isTag)
""")

    settings = PEER + "PeerInfoSettingsItems.swift"
    anchor = "    var result: [(AnyHashable, [PeerInfoScreenItem])] = []\n    for section in SettingsSection.allCases {"
    edit("roundProfileButtons", settings, anchor, """    if WhitegramClientInterfaceSettings.current.accountStrip {
        let accounts = data.globalSettings?.accountsAndPeers ?? []
        var allAccounts = accounts
        if let peer = data.peer, !allAccounts.contains(where: { $0.0.account.id == context.account.id }) {
            allAccounts.insert((context, peer, 0), at: 0)
        }
        let actions = (items[.edit] ?? []).compactMap { $0 as? PeerInfoScreenActionItem } + (items[.accounts] ?? []).compactMap { $0 as? PeerInfoScreenActionItem }
        items[.edit] = [WhitegramAccountStripItem(accounts: allAccounts, actions: actions, interaction: interaction)]
        items[.accounts] = []
    }

""" + anchor)
    # Route the profile buttons to a real local editor, avoiding stock server update paths.
    anchor = "    if case let .user(peer) = data.peer, peer.isPremium {\n"
    edit("localPremium", settings, anchor, "    if case let .user(peer) = data.peer, peer.isPremium || WhitegramPreferences.bool(\"localPremium\") {\n")
    actions = PEER + "PeerInfoScreenSettingsActions.swift"
    anchor = "        case .emojiStatus:\n            self.headerNode.invokeDisplayPremiumIntro()\n        case .profileColor:\n            self.interaction.editingOpenNameColorSetup()\n"
    edit("localPremium", actions, anchor, """        case .emojiStatus:
            if WhitegramPreferences.bool("localPremium") { push(WhitegramLocalPremiumController(context: self.context)) }
            else { self.headerNode.invokeDisplayPremiumIntro() }
        case .profileColor:
            if WhitegramPreferences.bool("localPremium") { push(WhitegramLocalPremiumController(context: self.context)) }
            else { self.interaction.editingOpenNameColorSetup() }
""")
    header = PEER + "PeerInfoHeaderNode.swift"
    anchor = "        if self.appliedCustomNavigationContentNode !== self.customNavigationContentNode {\n"
    edit("localPremium", header, anchor, "        let peer = WhitegramLocalPremiumPresentation.peer(peer, accountId: self.context.account.id.int64, accountPeerId: self.context.account.peerId)\n" + anchor)
    screen = PEER + "PeerInfoScreen.swift"
    anchor = "    private func editingOpenNameColorSetup() {\n"
    edit("localPremium", screen, anchor, anchor + """        if self.peerId == self.context.account.peerId, WhitegramPreferences.bool("localPremium") {
            self.controller?.push(WhitegramLocalPremiumController(context: self.context))
            return
        }
""")
    anchor = "            self.headerNode.displayPremiumIntro = { [weak self] sourceView, _, _, _ in\n                guard let strongSelf = self else {\n                    return\n                }\n"
    edit("localPremium", screen, anchor, anchor + """                if WhitegramPreferences.bool("localPremium") {
                    strongSelf.controller?.push(WhitegramLocalPremiumController(context: strongSelf.context))
                    return
                }
""")
    anchor = "            self.headerNode.displayPremiumIntro = { [weak self] sourceView, peerStatus, emojiStatusFileAndPack, white in\n                guard let strongSelf = self, let peer = strongSelf.data?.peer else {\n                    return\n                }\n"
    edit("localPremium", screen, anchor, anchor + """                if peer.id == strongSelf.context.account.peerId, WhitegramPreferences.bool("localPremium") {
                    strongSelf.controller?.push(WhitegramLocalPremiumController(context: strongSelf.context))
                    return
                }
""")
    anchor = "            combineLatest(screenData, WhitegramAppearanceSettings.signal()) |> map { data, _ in data },\n"
    edit("client-interface-live-profile", screen, anchor, "            combineLatest(screenData, WhitegramAppearanceSettings.signal(), WhitegramClientInterfaceSettings.signal(), whitegramClientInterfaceProfileUpdates()) |> map { data, _, _, _ in data },\n")
    return tuple(edits)


def client_interface_patches(patches: SourcePatches) -> None:
    saved = (dict(patches.original), dict(patches.pending), {key: set(value) for key, value in patches.features.items()})
    try:
        for edit in client_interface_edits():
            value = patches.read(edit.path)
            installed = value.count(edit.after)
            if installed and (installed != edit.count or edit.before in value.replace(edit.after, "")):
                raise ValueError(f"{edit.feature}: {edit.path}: mixed or duplicate client-interface hooks")
            patches.replace(edit.feature, edit.path, edit.before, edit.after, count=edit.count)
    except Exception:
        patches.original, patches.pending, patches.features = saved
        raise


def _temporary(path: Path, content: bytes) -> Path:
    descriptor, name = tempfile.mkstemp(prefix=".whitegram-client-", dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, path.stat().st_mode)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise
    return temporary


def apply_client_interface_patches(root: Path) -> dict[str, list[str]]:
    root = Path(root).resolve()
    preimages = {}
    for relative in {edit.path for edit in client_interface_edits()}:
        path = root / relative
        if path.is_symlink() or not path.resolve().is_relative_to(root):
            raise ValueError(f"client-interface target escapes source root: {relative}")
        preimages[relative] = path.read_bytes()
    patches = SourcePatches(root)
    client_interface_patches(patches)
    replacements = {}
    backups = {}
    committed = []
    retain_backups = False
    try:
        for relative, value in patches.pending.items():
            original = preimages[relative]
            if value == patches.original[relative]:
                continue
            newline = "\r\n" if b"\r\n" in original else "\n"
            content = value.replace("\n", newline).encode("utf-8")
            path = root / relative
            replacements[relative] = _temporary(path, content)
            backups[relative] = _temporary(path, original)
        for relative, original in preimages.items():
            if (root / relative).read_bytes() != original:
                raise ValueError(f"client-interface source changed during preflight: {relative}")
        for relative, temporary in replacements.items():
            os.replace(temporary, root / relative)
            committed.append(relative)
    except Exception:
        try:
            for relative in reversed(committed):
                os.replace(backups[relative], root / relative)
        except OSError as rollback_error:
            retain_backups = True
            retained = {relative: str(path) for relative, path in backups.items() if path.exists()}
            raise RuntimeError(f"client-interface rollback failed; retained preimages: {retained}") from rollback_error
        raise
    finally:
        for temporary in replacements.values():
            temporary.unlink(missing_ok=True)
        if not retain_backups:
            for temporary in backups.values():
                temporary.unlink(missing_ok=True)
    return {feature: sorted(paths) for feature, paths in sorted(patches.features.items())}
