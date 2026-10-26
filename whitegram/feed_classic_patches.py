"""Independent feed and bounded classic-renderer patch stage (after navigation)."""
from dataclasses import dataclass
from pathlib import Path

from source_patches import SourcePatches

UI = "submodules/TelegramUI/Sources/"
TABS = "submodules/TabBarUI/Sources/"
COMPONENTS = "submodules/TelegramUI/Components/"
RUNTIME_FILES = {
    "WhitegramFeedMerge.swift": "submodules/TelegramCore/Sources/WhitegramFeedMerge.swift",
    "WhitegramFeedHistory.swift": "submodules/TelegramCore/Sources/WhitegramFeedHistory.swift",
    "WhitegramFeedLoader.swift": UI + "WhitegramFeedLoader.swift",
    "WhitegramFeedController.swift": UI + "WhitegramFeedController.swift",
    "WhitegramFeedRoot.swift": UI + "WhitegramFeedRoot.swift",
    "WhitegramClassicStyle.swift": "submodules/Display/Source/WhitegramClassicStyle.swift",
    "WhitegramClassicPlate.swift": "submodules/Display/Source/WhitegramClassicPlate.swift",
    "WhitegramClassicSettings.swift": "submodules/TelegramPresentationData/Sources/WhitegramClassicSettings.swift",
    "WhitegramClassicTabs.swift": TABS + "WhitegramClassicTabs.swift",
}
BOOLEAN_CAPABILITIES = {"showPostsFeed": True, "classicInterface": True}
REQUIRED_DEPENDENCIES = {}  # Existing target imports/dependencies cover these files.


@dataclass(frozen=True)
class FeedClassicEdit:
    feature: str
    path: str
    before: str
    after: str
    count: int = 1


def feed_classic_edits() -> tuple[FeedClassicEdit, ...]:
    edits = []

    def edit(feature, path, before, after, count=1):
        edits.append(FeedClassicEdit(feature, path, before, after, count))

    root = UI + "TelegramRootController.swift"
    anchor = "    private var currentShowCallsTab: Bool = true\n"
    edit("showPostsFeed", root, anchor, anchor + "    private lazy var whitegramFeed = WhitegramFeedRootState(context: self.context)\n    private var whitegramFeedObserver: NSObjectProtocol?\n")
    anchor = "        super.init(mode: .automaticMasterDetail, theme: NavigationControllerTheme(presentationTheme: self.presentationData.theme))\n"
    edit("classic-root", root, anchor, anchor + "        WhitegramClassicSettings.install()\n")
    anchor = "        self.presentationDataDisposable = (context.sharedContext.presentationData\n"
    edit("showPostsFeed", root, anchor, """        self.whitegramFeedObserver = NotificationCenter.default.addObserver(forName: WhitegramPreferences.updatedNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.whitegramFeed.needsUpdate else { return }
            self.updateRootControllers(showCallsTab: self.currentShowCallsTab)
        }
""" + anchor)
    anchor = "        self.permissionsDisposable?.dispose()\n"
    edit("showPostsFeed", root, anchor, anchor + "        if let observer = self.whitegramFeedObserver { NotificationCenter.default.removeObserver(observer) }\n")
    for anchor in ("        controllers.append(accountSettingsController)\n", "        controllers.append(self.accountSettingsController!)\n"):
        edit("showPostsFeed", root, anchor, anchor + "        controllers = self.whitegramFeed.controllers(base: controllers, parent: self)\n")

    node = TABS + "TabBarContollerNode.swift"
    anchor = "    private let tabBarView = ComponentView<Empty>()\n"
    edit("classic-tabs", node, anchor, anchor + "    private let whitegramClassicTabs = WhitegramClassicTabRenderer()\n    private var whitegramClassicObserver: WhitegramClassicObserver?\n")
    anchor = "        //self.addSubnode(self.tabBarNode)\n"
    edit("classic-tabs", node, anchor, """        self.whitegramClassicObserver = WhitegramClassicObserver { [weak self] in
            guard let self else { return }
            self.layoutResult = nil
            self.whitegramAppearanceUpdated?()
        }
""" + anchor)
    anchor = "        let tabBarFrame = CGRect(origin: CGPoint(x: tabBarX, y: params.layout.size.height - (self.tabBarHidden ? 0.0 : (tabBarSize.height + tabBarBottomInset))), size: tabBarSize)\n"
    edit("classic-tabs", node, anchor, """        let classicHeight = CGFloat(WhitegramClassicStyle.tabHeight(landscape: !params.layout.safeInsets.left.isZero, safeBottom: Double(params.layout.insets(options: []).bottom)))
        let tabBarFrame = WhitegramClassicStyle.enabled
            ? CGRect(x: 0, y: params.layout.size.height - (self.tabBarHidden ? 0 : classicHeight), width: params.layout.size.width, height: classicHeight)
            : CGRect(origin: CGPoint(x: tabBarX, y: params.layout.size.height - (self.tabBarHidden ? 0.0 : (tabBarSize.height + tabBarBottomInset))), size: tabBarSize)
""")
    anchor = "            tabBarComponentView.isHidden = self.tabBarHidden\n            tabBarComponentView.accessibilityElementsHidden = self.tabBarHidden\n            tabBarComponentView.isUserInteractionEnabled = !self.tabBarHidden && !isCompactSearchActive\n"
    edit("classic-tabs", node, anchor, anchor + """            if WhitegramClassicStyle.enabled {
                tabBarComponentView.isHidden = true
                tabBarComponentView.accessibilityElementsHidden = true
                tabBarComponentView.isUserInteractionEnabled = false
            }
""")
    anchor = "        self.disabledOverlayNode.isHidden = self.tabBarHidden\n"
    edit("classic-tabs", node, anchor, """        self.whitegramClassicTabs.update(host: self, frame: tabBarFrame, layout: params.layout, theme: self.theme,
            items: self.tabBarItems, selected: self.selectedIndex, enabled: WhitegramClassicStyle.enabled,
            hidden: self.tabBarHidden || params.toolbar != nil, interactionEnabled: self.disabledOverlayNode.alpha < 0.5,
            reduceMotion: self.presentationData.reduceMotion, transition: transition,
            select: self.itemSelected, swipe: self.swipeAction)
""" + anchor)
    # The upstream node takes a swipe closure but did not retain it; the legacy renderer needs it.
    anchor = "    private let itemDoubleTapped: (Int) -> Void\n"
    edit("classic-tabs", node, anchor, anchor + "    private let swipeAction: (Int, TabBarItemSwipeDirection) -> Void\n")
    anchor = "        self.itemDoubleTapped = itemDoubleTapped\n"
    edit("classic-tabs", node, anchor, anchor + "        self.swipeAction = swipeAction\n")
    anchor = "        transition.updateAlpha(node: self.disabledOverlayNode, alpha: value ? 0.0 : 1.0)\n"
    edit("classic-tabs", node, anchor, anchor + "        self.requestUpdate()\n")
    anchor = "        if self.tabBarHidden { return nil }\n"
    edit("classic-tabs", node, anchor, anchor + "        if WhitegramClassicStyle.enabled { return self.whitegramClassicTabs.frame(index: index, in: self.view) }\n")

    glass = COMPONENTS + "GlassBackgroundComponent/Sources/GlassBackgroundComponent.swift"
    anchor = "        for name in [WhitegramGlassSettings.updatedNotification, UIAccessibility.reduceTransparencyStatusDidChangeNotification, UIAccessibility.reduceMotionStatusDidChangeNotification] {\n"
    edit("classic-material", glass, anchor, anchor.replace("[WhitegramGlassSettings", "[WhitegramClassicStyle.changedNotification, WhitegramGlassSettings"))
    anchor = "        if replacement == .telegram, self.legacyView != nil { replacement = .system }\n"
    edit("classic-material", glass, anchor, anchor + "        if WhitegramClassicStyle.enabled { replacement = UIAccessibility.isReduceTransparencyEnabled ? .color : .blur }\n")

    nav = COMPONENTS + "NavigationBarImpl/Sources/NavigationBarImpl.swift"
    anchor = "    private var requestedLayout: Bool = false\n"
    edit("classic-header", nav, anchor, anchor + "    private let whitegramClassicPlate = WhitegramClassicPlate(frame: .zero)\n    private var whitegramClassicObserver: WhitegramClassicObserver?\n")
    anchor = "        super.init()\n        \n        if case .glass = presentationData.theme.style {\n"
    edit("classic-header", nav, anchor, """        super.init()
        self.view.insertSubview(self.whitegramClassicPlate, at: 0)
        self.whitegramClassicObserver = WhitegramClassicObserver { [weak self] in
            self?.requestLayout()
            self?.requestContainerLayout?(.immediate)
        }
       \x20
        if case .glass = presentationData.theme.style {
""")
    anchor = "        self.validLayout = (size, defaultHeight, additionalTopHeight, additionalContentHeight, additionalBackgroundHeight, additionalCutout, leftInset, rightInset, appearsHidden, isLandscape)\n"
    edit("classic-header", nav, anchor, anchor + """        self.whitegramClassicPlate.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height + additionalBackgroundHeight)
        self.whitegramClassicPlate.update(size: self.whitegramClassicPlate.bounds.size, color: self.presentationData.theme.opaqueBackgroundColor,
            separatorColor: self.presentationData.theme.separatorColor, separatorAtTop: false, enabled: WhitegramClassicStyle.enabled && !appearsHidden, transition: transition)
""")
    anchor = "        let nominalHeight: CGFloat = 60.0\n"
    edit("classic-header", nav, anchor, "        let nominalHeight: CGFloat = WhitegramClassicStyle.enabled ? 44.0 : 60.0\n")
    anchor = "    public func contentHeight(defaultHeight: CGFloat) -> CGFloat {\n"
    edit("classic-header", nav, anchor, anchor + "        let defaultHeight = CGFloat(WhitegramClassicStyle.navigationHeight(original: Double(defaultHeight)))\n")

    listing = COMPONENTS + "ChatListHeaderComponent/Sources/ChatListNavigationBar.swift"
    anchor = "        private let edgeEffectView: EdgeEffectView\n"
    edit("classic-chat-list-header", listing, anchor, anchor + "        private let whitegramClassicPlate = WhitegramClassicPlate(frame: .zero)\n        private var whitegramClassicObserver: WhitegramClassicObserver?\n")
    anchor = "            self.addSubview(self.edgeEffectView)\n"
    edit("classic-chat-list-header", listing, anchor, """            self.addSubview(self.whitegramClassicPlate)
            self.whitegramClassicObserver = WhitegramClassicObserver { [weak self] in self?.state?.updated(transition: .immediate) }
""" + anchor)
    anchor = "            self.edgeEffectView.isHidden = !component.hasEdgeEffect\n"
    edit("classic-chat-list-header", listing, anchor, """            self.edgeEffectView.isHidden = !component.hasEdgeEffect || WhitegramClassicStyle.enabled
            self.whitegramClassicPlate.frame = CGRect(origin: .zero, size: size)
            self.whitegramClassicPlate.update(size: size, color: component.theme.rootController.navigationBar.opaqueBackgroundColor,
                separatorColor: component.theme.rootController.navigationBar.separatorColor, separatorAtTop: false,
                enabled: WhitegramClassicStyle.enabled, transition: .immediate)
""")

    composer = COMPONENTS + "Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift"
    anchor = "    private let glassBackgroundContainer: GlassBackgroundContainerView\n"
    edit("classic-composer", composer, anchor, anchor + "    private let whitegramClassicPlate = WhitegramClassicPlate(frame: .zero)\n    private var whitegramClassicObserver: WhitegramClassicObserver?\n")
    anchor = "        self.view.addSubview(self.glassBackgroundContainer)\n"
    edit("classic-composer", composer, anchor, """        self.view.addSubview(self.whitegramClassicPlate)
        self.whitegramClassicObserver = WhitegramClassicObserver { [weak self] in self?.requestLayout() }
""" + anchor)
    anchor = "        let compactBottomSideInset = self.compactBottomSideInset(bottomInset: bottomInset, deviceMetrics: deviceMetrics)\n"
    edit("classic-composer", composer, anchor, "        let compactBottomSideInset: CGFloat = WhitegramClassicStyle.enabled ? 0.0 : self.compactBottomSideInset(bottomInset: bottomInset, deviceMetrics: deviceMetrics)\n", count=2)
    anchor = "        self.textInputContainerBackgroundView.update(size: textInputContainerBackgroundFrame.size, cornerRadius: floor(minimalInputHeight * 0.5), isDark: interfaceState.theme.overallDarkAppearance, tintColor: defaultGlassTintColor, isInteractive: true, transition: textInputContainerBackgroundTransition)\n"
    edit("classic-composer", composer, anchor, anchor.replace("floor(minimalInputHeight * 0.5)", "WhitegramClassicStyle.enabled ? min(12.0, floor(minimalInputHeight * 0.5)) : floor(minimalInputHeight * 0.5)").replace("isInteractive: true", "isInteractive: !WhitegramClassicStyle.enabled"))
    anchor = "        self.glassBackgroundContainer.update(size: containerFrame.size, isDark: interfaceState.theme.overallDarkAppearance, transition: ComponentTransition(transition))\n"
    edit("classic-composer", composer, anchor, anchor + """        self.whitegramClassicPlate.frame = containerFrame
        self.whitegramClassicPlate.update(size: containerFrame.size, color: interfaceState.theme.chat.inputPanel.panelBackgroundColor,
            separatorColor: interfaceState.theme.chat.inputPanel.panelSeparatorColor, separatorAtTop: true,
            enabled: WhitegramClassicStyle.enabled, transition: transition)
""")

    for filename in ("ItemListSwitchItem.swift", "ItemListDisclosureItem.swift", "ItemListActionItem.swift"):
        path = "submodules/ItemListUI/Sources/Items/" + filename
        anchor = "        self.systemStyle = systemStyle\n"
        edit("classic-settings-items", path, anchor, "        self.systemStyle = WhitegramClassicStyle.enabled ? .legacy : systemStyle\n")
    return tuple(edits)


def feed_classic_patches(patches: SourcePatches) -> None:
    saved = (dict(patches.original), dict(patches.pending), {key: set(value) for key, value in patches.features.items()})
    try:
        for edit in feed_classic_edits():
            value = patches.read(edit.path)
            installed = value.count(edit.after)
            if installed and (installed != edit.count or edit.before in value.replace(edit.after, "")):
                raise ValueError(f"{edit.feature}: {edit.path}: mixed or duplicate feed/classic hooks")
            patches.replace(edit.feature, edit.path, edit.before, edit.after, count=edit.count)
    except Exception:
        patches.original, patches.pending, patches.features = saved
        raise


def apply_feed_classic_patches(root: Path) -> dict[str, list[str]]:
    patches = SourcePatches(Path(root))
    feed_classic_patches(patches)
    return patches.write()
