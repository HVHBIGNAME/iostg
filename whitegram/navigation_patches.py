"""Local navigation/background hooks for the assembled Telegram 13.0 source.

Staging only: navigation_patches(SourcePatches). The wrapper is intentionally the
same write contract as the parent overlay; it does not install runtime files.
"""

from dataclasses import dataclass
from pathlib import Path

from source_patches import SourcePatches


CORE = "submodules/TelegramCore/Sources/Settings/"
PRESENTATION = "submodules/TelegramPresentationData/Sources/"
SETTINGS = "submodules/SettingsUI/Sources/"
UI = "submodules/TelegramUI/Sources/"
PEER = "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/"
TABS = "submodules/TabBarUI/Sources/"

RUNTIME_FILES = {
    "WhitegramNavigationPolicy.swift": CORE + "WhitegramNavigationPolicy.swift",
    "WhitegramBackgroundStore.swift": CORE + "WhitegramBackgroundStore.swift",
    "WhitegramBackgroundView.swift": PRESENTATION + "WhitegramBackgroundView.swift",
    "WhitegramBackgroundController.swift": SETTINGS + "WhitegramBackgroundController.swift",
    "WhitegramNavigationPreviewController.swift": SETTINGS + "WhitegramNavigationPreviewController.swift",
    "WhitegramNavigationTabAccess.swift": TABS + "WhitegramNavigationTabAccess.swift",
    "WhitegramNavigationRoot.swift": UI + "WhitegramNavigationRoot.swift",
}

BOOLEAN_CAPABILITIES = {
    "separateProfileTab": True,
    "hideBottomTabBar": True,
    "videoBackgroundInProfile": True,
    "showPostsFeed": False,
    "classicInterface": False,
}

REQUIRED_DEPENDENCIES = {
    "submodules/SettingsUI/BUILD": ("//submodules/TabBarUI:TabBarUI",),
}


@dataclass(frozen=True)
class NavigationEdit:
    feature: str
    path: str
    before: str
    after: str


def navigation_edits() -> tuple[NavigationEdit, ...]:
    edits = []

    def edit(feature, path, before, after):
        edits.append(NavigationEdit(feature, path, before, after))

    root = UI + "TelegramRootController.swift"
    anchor = "    public var rootTabController: TabBarController?\n"
    edit("navigation-root", root, anchor, anchor + "    private lazy var whitegramNavigation = WhitegramNavigationRootState(context: self.context)\n    private var whitegramNavigationObserver: NSObjectProtocol?\n")
    anchor = "            self.whiteGramTabSettingsObserver = NotificationCenter.default.addObserver(forName: WhiteGramTabSettings.updatedNotification, object: nil, queue: .main, using: { [weak self] _ in\n"
    edit("navigation-live-refresh", root, anchor, """            self.whitegramNavigationObserver = NotificationCenter.default.addObserver(forName: WhitegramPreferences.updatedNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self, self.whitegramNavigation.needsUpdate else { return }
                self.updateRootControllers(showCallsTab: self.currentShowCallsTab)
            }
""" + anchor)
    anchor = "        self.permissionsDisposable?.dispose()\n"
    edit("navigation-live-refresh", root, anchor, "        if let observer = self.whitegramNavigationObserver { NotificationCenter.default.removeObserver(observer) }\n" + anchor)
    anchor = "        tabBarController.setControllers(controllers, selectedIndex: restoreSettignsController != nil ? (controllers.count - 1) : (controllers.count - 2))\n"
    edit("separateProfileTab", root, anchor, "        self.whitegramNavigation.apply(to: tabBarController, base: controllers, preferred: restoreSettignsController != nil ? accountSettingsController : chatListController, chats: chatListController, parent: self)\n")
    anchor = "        rootTabController.setControllers(controllers, selectedIndex: nil)\n"
    edit("separateProfileTab", root, anchor, "        self.whitegramNavigation.apply(to: rootTabController, base: controllers, preferred: nil, chats: self.chatListController!, parent: self)\n")
    # Existing deep links still target Settings explicitly, even with two PeerInfo tabs.
    anchor = "        if let index = rootTabController.controllers.firstIndex(where: { $0 is PeerInfoScreenImpl }) {\n"
    # Two intentionally distinct surrounding anchors, one for icon settings and one for edit settings.
    for following in ("        let themeController = themeSettingsController", "        if edit {"):
        before = anchor + "            rootTabController.selectedIndex = index\n        }\n        \n" + following
        edit("settings-deep-links", root, before, before.replace("$0 is PeerInfoScreenImpl", "$0 === self.accountSettingsController"))

    tabs = TABS + "TabBarController.swift"
    anchor = "    private var suppressTabSelectionUntil: Double = 0.0\n"
    edit("hideBottomTabBar", tabs, anchor, anchor + """    private var whitegramRequestedTabBarHidden = false
    private let whitegramTabAccess = WhitegramNavigationTabAccess()
    public var whitegramRestoreTabBar: (() -> Void)?
    public var whitegramPersistentTabBarHidden = false {
        didSet {
            guard self.isNodeLoaded else { return }
            self.tabBarControllerNode.tabBarHidden = self.whitegramRequestedTabBarHidden || self.whitegramPersistentTabBarHidden
            self.updateLayout(transition: .immediate)
        }
    }
""")
    anchor = "        self.tabBarControllerNode.tabBarHidden = value\n"
    edit("hideBottomTabBar", tabs, anchor, "        self.whitegramRequestedTabBarHidden = value\n        self.tabBarControllerNode.tabBarHidden = value || self.whitegramPersistentTabBarHidden\n")
    anchor = "        self.updateSelectedIndex()\n        self.tabBarControllerNode.whitegramAppearanceUpdated = { [weak self] in\n"
    edit("hideBottomTabBar", tabs, anchor, "        self.tabBarControllerNode.tabBarHidden = self.whitegramRequestedTabBarHidden || self.whitegramPersistentTabBarHidden\n" + anchor)
    anchor = "                    updatedLayout.intrinsicInsets.bottom = tabBarHeight\n"
    edit("hideBottomTabBar", tabs, anchor, "                    if !strongSelf.tabBarControllerNode.tabBarHidden { updatedLayout.intrinsicInsets.bottom = tabBarHeight }\n")
    anchor = "            if !self.tabBarControllerNode.tabBarHidden {\n                updatedLayout.intrinsicInsets.bottom = bottomInset\n"
    edit("hideBottomTabBar", tabs, anchor, "            if !self.tabBarControllerNode.tabBarHidden || currentController.toolbar != nil {\n                updatedLayout.intrinsicInsets.bottom = bottomInset\n")
    anchor = "            currentController.containerLayoutUpdated(updatedLayout, transition: transition)\n        }\n    }\n\n    public func updateControllerLayout(controller: ViewController) {\n"
    edit("hidden-tab-access", tabs, anchor, """            currentController.containerLayoutUpdated(updatedLayout, transition: transition)
        }
        self.whitegramTabAccess.update(host: self.displayNode.view, layout: layout, controllers: self.controllers, selected: self.selectedIndex,
            enabled: self.whitegramPersistentTabBarHidden && !self.whitegramRequestedTabBarHidden && self.currentController?.toolbar == nil && self.currentController?.tabBarSearchState?.isActive != true,
            select: { [weak self] index in self?.selectedIndex = index }, restore: { [weak self] in self?.whitegramRestoreTabBar?() })
    }

    public func updateControllerLayout(controller: ViewController) {
""")

    node = TABS + "TabBarContollerNode.swift"  # Upstream spelling.
    anchor = "            tabBarComponentView.isUserInteractionEnabled = !isCompactSearchActive\n"
    edit("hideBottomTabBar", node, anchor, """            tabBarComponentView.isHidden = self.tabBarHidden
            tabBarComponentView.accessibilityElementsHidden = self.tabBarHidden
            tabBarComponentView.isUserInteractionEnabled = !self.tabBarHidden && !isCompactSearchActive
""")
    anchor = "        transition.updateFrame(node: self.disabledOverlayNode, frame: tabBarFrame)\n"
    edit("hideBottomTabBar", node, anchor, "        self.disabledOverlayNode.isHidden = self.tabBarHidden\n" + anchor)
    anchor = "        if isCompactSearchActive {\n            return panelsBottomInset\n"
    edit("hideBottomTabBar", node, anchor, """        if self.tabBarHidden {
            return params.toolbar == nil ? params.layout.intrinsicInsets.bottom : params.layout.size.height - toolbarFrame.minY
        }
""" + anchor)
    anchor = "    func frameForControllerTab(at index: Int) -> CGRect? {\n"
    edit("hideBottomTabBar", node, anchor, anchor + "        if self.tabBarHidden { return nil }\n")

    peer = PEER + "PeerInfoScreen.swift"
    anchor = "                    strongSelf.tabBarItem.title = title\n"
    edit("separateProfileTab", peer, anchor, "                    strongSelf.tabBarItem.title = strongSelf.isMyProfile ? \"Profile\" : title\n")
    anchor = "                    strongSelf.tabBarItem.image = image\n                    strongSelf.tabBarItem.selectedImage = selectedImage\n"
    edit("separateProfileTab", peer, anchor, """                    strongSelf.tabBarItem.image = strongSelf.isMyProfile ? UIImage(systemName: "person.crop.circle") : image
                    strongSelf.tabBarItem.selectedImage = strongSelf.isMyProfile ? UIImage(systemName: "person.crop.circle.fill") : selectedImage
""")
    anchor = "                    strongSelf.tabBarItem.animationName = isAvatar || reduceMotion ? nil : \"TabSettings\"\n                    strongSelf.tabBarItem.ringSelection = isAvatar\n                    strongSelf.tabBarItem.badgeValue = badgeValue\n"
    edit("separateProfileTab", peer, anchor, """                    strongSelf.tabBarItem.animationName = strongSelf.isMyProfile || isAvatar || reduceMotion ? nil : "TabSettings"
                    strongSelf.tabBarItem.ringSelection = !strongSelf.isMyProfile && isAvatar
                    strongSelf.tabBarItem.badgeValue = strongSelf.isMyProfile ? nil : badgeValue
""")
    anchor = "    override public func viewDidAppear(_ animated: Bool) {\n        super.viewDidAppear(animated)\n"
    edit("video-background-lifecycle", peer, anchor, anchor + "        self.controllerNode.headerNode.whitegramBackground.setVisible(true)\n")
    anchor = "    override public func viewWillDisappear(_ animated: Bool) {\n        super.viewWillDisappear(animated)\n"
    edit("video-background-lifecycle", peer, anchor, anchor + "        if self.isNodeLoaded { self.controllerNode.headerNode.whitegramBackground.setVisible(false) }\n")

    header = PEER + "PeerInfoHeaderNode.swift"
    anchor = "    let backgroundBannerView: UIView\n"
    edit("profileCoverPhoto", header, anchor, anchor + "    lazy var whitegramBackground = WhitegramBackgroundView(accountId: self.context.account.id.int64, surface: .profile)\n")
    anchor = "        if let profileGiftsContext, let peer {\n            let giftsCoverSize = self.giftsCover.update(\n"
    edit("profileCoverPhoto", header, anchor, """        self.whitegramBackground.configure(isOwnProfile: peer?.id == self.context.account.peerId,
            contentAllowed: !self.isAvatarExpanded && !state.isEditing && !isMediaOnly && backgroundBannerAlpha > 0.0,
            tint: presentationData.theme.list.blocksBackgroundColor)
        if self.whitegramBackground.superview !== self.backgroundBannerView { self.backgroundBannerView.addSubview(self.whitegramBackground) }
        self.backgroundBannerView.bringSubviewToFront(self.whitegramBackground)
        transition.updateFrame(view: self.whitegramBackground, frame: CGRect(x: 0, y: bannerFrame.height - backgroundCoverSize.height, width: bannerFrame.width, height: backgroundCoverSize.height))

""" + anchor)

    chat = UI + "ChatControllerNode.swift"
    # Scoped by the following declaration, avoiding SnapshotState's similarly named field.
    anchor = "    let backgroundNode: WallpaperBackgroundNode\n    "
    # Prefixing the first-level declaration is unambiguous: SnapshotState is indented by eight spaces.
    edit("videoChatBackground", chat, "\n" + anchor, "\n    lazy var whitegramBackground = WhitegramBackgroundView(accountId: self.context.account.id.int64, surface: .chat)\n" + anchor)
    anchor = "    override func didLoad() {\n        super.didLoad()\n"
    edit("videoChatBackground", chat, anchor, anchor + """        self.backgroundNode.view.addSubview(self.whitegramBackground)
        self.whitegramBackground.frame = self.backgroundNode.bounds
        self.whitegramBackground.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.whitegramBackground.configure(tint: self.chatPresentationInterfaceState.theme.list.blocksBackgroundColor)
""")
    anchor = "        self.backgroundNode.updateLayout(size: wallpaperBounds.size, displayMode: displayMode, transition: transition)\n"
    edit("videoChatBackground", chat, anchor, anchor + """        self.whitegramBackground.configure(tint: self.chatPresentationInterfaceState.theme.list.blocksBackgroundColor)
        self.backgroundNode.view.bringSubviewToFront(self.whitegramBackground)
""")
    controller = UI + "ChatController.swift"
    anchor = "    override public func viewDidAppear(_ animated: Bool) {\n        super.viewDidAppear(animated)\n"
    edit("video-background-lifecycle", controller, anchor, anchor + "        self.chatDisplayNode.whitegramBackground.setVisible(true)\n")
    anchor = "    override public func viewWillDisappear(_ animated: Bool) {\n"
    edit("video-background-lifecycle", controller, anchor, anchor + "        if self.isNodeLoaded { self.chatDisplayNode.whitegramBackground.setVisible(false) }\n")

    return tuple(edits)


def navigation_patches(patches: SourcePatches) -> None:
    saved = (dict(patches.original), dict(patches.pending), {key: set(value) for key, value in patches.features.items()})
    try:
        for edit in navigation_edits():
            value = patches.read(edit.path)
            installed = value.count(edit.after)
            if installed and (installed != 1 or edit.before in value.replace(edit.after, "")):
                raise ValueError(f"{edit.feature}: {edit.path}: mixed or duplicate navigation hook")
            patches.replace(edit.feature, edit.path, edit.before, edit.after)
    except Exception:
        patches.original, patches.pending, patches.features = saved
        raise


def apply_navigation_patches(root: Path) -> dict[str, list[str]]:
    patches = SourcePatches(Path(root))
    navigation_patches(patches)
    return patches.write()
