"""Evidence-directed visual consumers. Staging is transactional; source trees are caller-owned."""

from dataclasses import dataclass
from pathlib import Path
import re

from source_patches import SourcePatches


RUNTIME_FILES = {
    "WhitegramVisualPolicy.swift": "submodules/TelegramCore/Sources/Settings/WhitegramVisualPolicy.swift",
    **{name: "submodules/TelegramPresentationData/Sources/" + name for name in (
        "WhitegramVisualEnvironment.swift", "WhitegramVisualBackdrop.swift", "WhitegramVisualProfile.swift",
        "WhitegramVisualScroll.swift", "WhitegramVisualFisheye.swift", "WhitegramVisualParticles.swift",
    )},
}

UI = "submodules/TelegramUI/"
PROFILE = UI + "Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift"
PANES = UI + "Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoPaneContainerNode.swift"
TABS = UI + "Components/HorizontalTabsComponent/Sources/HorizontalTabsComponent.swift"
PLAYER = UI + "Sources/OverlayAudioPlayerControlsNode.swift"
CHAT = UI + "Sources/ChatControllerNode.swift"
ROOT = UI + "Sources/TelegramRootController.swift"
BUBBLE = UI + "Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift"


@dataclass(frozen=True)
class Edit:
    feature: str
    path: str
    before: str
    after: str
    marker: str


PROFILE_METHOD = '''    private func whitegramUpdateVisualProfile() {
        guard let (layout, _) = self.validLayout else { return }
        let peer = self.data?.savedMessagesPeer ?? self.data?.peer
        let images = peer?._asPeer().profileImageRepresentations ?? []
        let identity = peer.map { String(self.context.account.id.int64) + ":" + String($0.id.toInt64()) + ":" + images.map { $0.resource.id.stringRepresentation }.joined(separator: ",") }
        var colors: [UIColor] = []
        if let status = peer?.emojiStatus, case let .starGift(_, _, _, _, _, innerColor, outerColor, _, _) = status.content {
            colors = [UIColor(rgb: UInt32(bitPattern: innerColor)), UIColor(rgb: UInt32(bitPattern: outerColor))]
        } else if let color = peer?.effectiveProfileColor {
            let profile = self.context.peerNameColors.getProfile(color, dark: self.presentationData.theme.overallDarkAppearance)
            colors = [profile.main, profile.secondary ?? profile.main]
        }
        self.whitegramVisualProfile.update(host: self.view, avatarView: self.headerNode.avatarListNode.avatarContainerNode.avatarNode.view,
            frame: CGRect(origin: .zero, size: layout.size), identity: identity, hasPhoto: !images.isEmpty,
            colors: colors, base: self.presentationData.theme.list.blocksBackgroundColor,
            expanded: self.headerNode.isAvatarExpanded, suppressed: self.state.isEditing || self.isMediaOnly || self.searchDisplayController != nil)
    }

'''


def visual_effects_edits() -> tuple[Edit, ...]:
    edits = []

    def add(feature, path, before, addition, *, prepend=False):
        marker = f"whitegram-visual-{len(edits):02d}"
        indent = re.match(r"[ \t]*", before)[0]
        before = "\n" + before
        block = f"{indent}// {marker}:begin\n" + addition + f"{indent}// {marker}:end\n"
        edits.append(Edit(feature, path, before, "\n" + block + before if prepend else before + block, marker))

    add("visualProfile", PROFILE, "    let headerNode: PeerInfoHeaderNode\n", "    private let whitegramVisualProfile = WhitegramVisualProfile()\n")
    add("visualProfile", PROFILE, "        self.addSubnode(self.headerNode)\n", '''        let whitegramAvatarImageNode = self.headerNode.avatarListNode.avatarContainerNode.avatarNode.imageNode
        let whitegramPreviousImageUpdated = whitegramAvatarImageNode.contentUpdated
        whitegramAvatarImageNode.contentUpdated = { [weak self] image in
            whitegramPreviousImageUpdated?(image)
            self?.whitegramVisualProfile.setImage(image)
        }
''')
    signature = "    func containerLayoutUpdated(layout: ContainerViewLayout, navigationHeight: CGFloat, transition: ContainedViewLayoutTransition, additive: Bool = false) {\n"
    add("visualProfile", PROFILE, signature, PROFILE_METHOD, prepend=True)
    add("visualProfile", PROFILE, signature + "        if self.isLentToExpansion {\n            self.layoutHeldDuringExpansion = (layout, navigationHeight)\n            return\n        }\n        self.validLayout = (layout, navigationHeight)\n", '''        self.whitegramUpdateVisualProfile()
        defer { self.whitegramUpdateVisualProfile() }
''')

    add("albumArtBlur", PLAYER, "    let albumArtNode: TransformImageNode\n", "    private let whitegramVisualAlbumArt = WhitegramVisualAlbumArt()\n")
    add("albumArtBlur", PLAYER, "        self.addSubnode(self.albumArtNode)\n", '''        self.albumArtNode.imageUpdated = { [weak self] image in
            guard let self else { return }
            self.whitegramVisualAlbumArt.setImage(self.currentAlbumArt == nil ? nil : image)
        }
''')
    add("albumArtBlur", PLAYER, "            self.currentAlbumArt = albumArt\n", "            self.whitegramVisualAlbumArt.setImage(nil)\n")
    add("albumArtBlur", PLAYER, "                strongSelf.currentItemId = valueItemId\n", "                strongSelf.whitegramVisualAlbumArt.setImage(nil)\n                strongSelf.currentAlbumArtInitialized = false\n")
    add("albumArtBlur", PLAYER,
        "        transition.updateFrame(node: self.backgroundNode, frame: CGRect(origin: CGPoint(x: 0.0, y: -8.0), size: CGSize(width: width, height: finalPanelHeight + 8.0)))\n",
        "        self.whitegramVisualAlbumArt.update(host: self.view, above: self.backgroundNode.layer, frame: self.backgroundNode.frame, base: self.presentationData.theme.list.modalPlainBackgroundColor)\n")

    add("chatScrollAnimation", BUBBLE, "    private var absoluteRect: (CGRect, CGSize)?\n", '''    private let whitegramVisualScroll = WhitegramVisualScrollEffect()

    override public func reuse() {
        self.whitegramVisualScroll.reset()
        super.reuse()
    }
''')
    add("chatScrollAnimation", BUBBLE, "    override public func updateAbsoluteRect(_ rect: CGRect, within containerSize: CGSize) {\n", '''        if self.isNodeLoaded, let item = self.item {
            self.whitegramVisualScroll.update(layer: self.mainContextSourceNode.contentNode.layer,
                identity: String(item.context.account.id.int64) + ":" + String(describing: item.message.id), rect: rect,
                visible: self.visibility != .none && !self.mainContextSourceNode.isExtractedToContextPreview)
        } else {
            self.whitegramVisualScroll.reset()
        }
''')
    add("chatScrollAnimation", BUBBLE, "                self.visibilityStatus = self.visibility != .none\n", "                if self.visibility == .none { self.whitegramVisualScroll.reset() }\n")
    add("chatScrollAnimation", BUBBLE, "        self.mainContextSourceNode.willUpdateIsExtractedToContextPreview = { [weak self] isExtractedToContextPreview, _ in\n", "            self?.whitegramVisualScroll.reset()\n")

    add("wgBubbleFisheyeEffect", TABS, "        private var itemViews: [Tab.Id: ItemView] = [:]\n", '''        private let whitegramVisualFisheye = WhitegramVisualFisheye()
        public var whitegramVisualFisheyeEnabled = false {
            didSet { self.whitegramUpdateFisheye() }
        }

        private func whitegramUpdateFisheye() {
            var layers: [(CALayer, CGFloat)] = []
            for (_, item) in self.itemViews {
                if let view = item.regularView.view { layers.append((view.layer, item.frame.midX)) }
                if let view = item.selectedView.view { layers.append((view.layer, item.frame.midX)) }
            }
            self.whitegramVisualFisheye.update(layers: layers, center: self.scrollView.bounds.midX,
                enabled: self.whitegramVisualFisheyeEnabled && self.reorderingItem == nil && self.component?.isEditing != true && self.window != nil)
        }

        public override func didMoveToWindow() {
            super.didMoveToWindow()
            self.whitegramUpdateFisheye()
        }
''')
    add("wgBubbleFisheyeEffect", TABS, "        private func updateScrolling(transition: ComponentTransition) {\n", "            self.whitegramUpdateFisheye()\n")
    add("wgBubbleFisheyeEffect", PANES, "        let tabsContainerEffectiveSize = self.tabsContainer.update(\n", '''        defer {
            (self.tabsContainer.view as? HorizontalTabsComponent.View)?.whitegramVisualFisheyeEnabled = true
        }
''', prepend=True)

    add("particleEffect", CHAT, "    let backgroundNode: WallpaperBackgroundNode\n", "    private let whitegramVisualParticles = WhitegramVisualParticles(placement: .chat)\n")
    add("particleEffect", CHAT, "        self.contentContainerNode.contentNode.addSubnode(self.backgroundNode)\n", "        self.backgroundNode.view.addSubview(self.whitegramVisualParticles)\n")
    add("particleEffect", CHAT, "    override func didLoad() {\n", '''    override func didEnterHierarchy() {
        super.didEnterHierarchy()
        self.whitegramVisualParticles.setVisible(true)
    }

    override func didExitHierarchy() {
        self.whitegramVisualParticles.setVisible(false)
        super.didExitHierarchy()
    }

''', prepend=True)
    add("particleEffect", CHAT, "        self.backgroundNode.updateLayout(size: wallpaperBounds.size, displayMode: displayMode, transition: transition)\n", '''        self.whitegramVisualParticles.frame = CGRect(origin: .zero, size: wallpaperBounds.size)
        self.whitegramVisualParticles.layer.zPosition = 1000.0
''')
    add("particleEffect", ROOT, "    public var rootTabController: TabBarController?\n", "    private let whitegramVisualParticles = WhitegramVisualParticles(placement: .screen)\n")
    add("particleEffect", ROOT, "        super.containerLayoutUpdated(layout, transition: transition)\n", '''        if self.whitegramVisualParticles.superview !== self.view {
            self.view.addSubview(self.whitegramVisualParticles)
            self.whitegramVisualParticles.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }
        self.whitegramVisualParticles.frame = self.view.bounds
        self.whitegramVisualParticles.layer.zPosition = 10000.0
''')
    return tuple(edits)


def _replace(patches: SourcePatches, edit: Edit, *, reverse: bool = False) -> None:
    before, after = (edit.after, edit.before) if reverse else (edit.before, edit.after)
    value = patches.read(edit.path)
    # The small original anchor also occurs inside an insertion. Count only outside
    # the complete installed block, rejecting duplicate and mixed-version sites.
    installed = value.count(edit.after)
    pristine = value.replace(edit.after, "").count(edit.before)
    if value.count(edit.marker + ":begin") != installed or value.count(edit.marker + ":end") != installed:
        raise ValueError(f"{edit.feature}: {edit.path}: modified or partial installed block {edit.marker}")
    if (installed, pristine) not in ((0, 1), (1, 0)):
        raise ValueError(f"{edit.feature}: {edit.path}: {edit.marker}: expected one exact original or installed anchor; got {installed}/{pristine}: {edit.before[:120]!r}")
    if (reverse and pristine == 1) or (not reverse and installed == 1):
        patches.features.setdefault(edit.feature, set()).add(edit.path)
        return
    patches.pending[edit.path] = value.replace(before, after, 1)
    patches.features.setdefault(edit.feature, set()).add(edit.path)


def visual_effects_patches(patches: SourcePatches, *, reverse: bool = False) -> None:
    """Stage all hooks or none, preserving the caller's preexisting pending edits."""
    checkpoint = (dict(patches.original), dict(patches.pending), {key: set(value) for key, value in patches.features.items()})
    try:
        edits = visual_effects_edits()
        for path in sorted({edit.path for edit in edits}):
            normalized = patches.read(path)
            for edit in reversed(edits):
                if edit.path == path:
                    normalized = normalized.replace(edit.after, edit.before)
            if re.search(r"\b(?:WhitegramVisual(?:Profile|ScrollEffect|Particles|AlbumArt|Fisheye|Environment|Policy)|whitegramVisual(?:Profile|Scroll|Particles|AlbumArt|Fisheye|FisheyeEnabled)|whitegramUpdateVisualProfile|whitegramUpdateFisheye)\b", normalized):
                raise ValueError(f"visual effects: {path}: unrecognized or modified visual consumer outside exact installed blocks")
        for edit in reversed(edits) if reverse else edits:
            _replace(patches, edit, reverse=reverse)
    except Exception:
        patches.original, patches.pending, patches.features = checkpoint
        raise


def apply_visual_effects_patches(root: Path) -> dict[str, list[str]]:
    patches = SourcePatches(root)
    visual_effects_patches(patches)
    for path, original in patches.original.items():
        if (root / path).read_text(encoding="utf-8") != original:
            raise ValueError(f"visual effects: {path}: source changed during staging")
    return patches.write()
