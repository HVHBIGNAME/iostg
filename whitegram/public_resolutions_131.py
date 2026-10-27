"""Reviewed public overlay conflicts against Telegram fb0e62b (13.1.1)."""

import re
from pathlib import PurePosixPath

from public_resolutions import replace_once
from public_resolutions_13 import resolve_13

REVISION = "fb0e62ba8a147f0821da6aa63c09da7d79a10111"
COUNTS = {
    "BUILD": 1,
    "ChatListController.swift": 6,
    "TabBarContollerNode.swift": 5,
    "Account.swift": 2,
    "GlassBackgroundComponent.swift": 2,
    "StoryPeerListComponent.swift": 1,
    "TabBarComponent.swift": 15,
    "ChatPinnedMessageTitlePanelNode.swift": 2,
    "TelegramRootController.swift": 1,
}


def chat_list_block(index, ours, base, theirs):
    if index == 1:
        return ours + "                        releasePeerSelection()\n"
    if index == 2:
        return ours + theirs.split("\n", 1)[1]
    if index == 3:
        return replace_once(theirs, "UIScreen.main.bounds", "mainWindowScreenBounds")
    if index == 4:
        folder = theirs[theirs.index("    var allowFolderButton:"):]
        folder = replace_once(folder, "AnyComponentWithIdentity<NavigationButtonComponentEnvironment>", "NavigationBarComponent.Button")
        folder = replace_once(folder, 'AnyComponentWithIdentity(id: "folders", component: AnyComponent(NavigationButtonComponent(\n            content: .folder,\n            pressed:', 'NavigationBarComponent.Button(id: "folders", content: .icon(imageName: "Chat/Context Menu/Folder"), action:')
        folder = replace_once(folder, "        )))", "        )")
        return ours + folder
    return ours + theirs


def tab_node_block(index, ours, base, theirs):
    if index == 1:
        return replace_once(theirs, "(whiteGramTabSettings.hideSearchButton", "(sidePlacement != nil || whiteGramTabSettings.hideSearchButton")
    if index == 2:
        return ours.rstrip() + ",\n" + theirs.split("\n", 1)[1]
    if index == 3:
        positioning = theirs[:theirs.index("        let tabBarFrame =")]
        return positioning + replace_once(ours, "x: floor((params.layout.size.width - tabBarSize.width) * 0.5)", "x: tabBarX")
    if index == 4:
        return "            tabBarComponentView.isUserInteractionEnabled = !isCompactSearchActive\n" + replace_once(ours, "params.toolbar == nil ?", "params.toolbar == nil && !isCompactSearchActive ?")
    return ours + theirs


def tab_component_block(index, ours, base, theirs):
    if index in (1, 3, 4):
        return ours + theirs
    if index == 2:
        return ours.rstrip() + ",\n" + theirs.split("\n", 1)[1]
    if index == 5:
        return replace_once(ours, "showsTitle: true", "showsTitle: !component.hideItemTitles")
    if index == 7:
        return """            if component.axis == .horizontal && !component.forceFullWidth {
                let desiredLength = unboundItemWidths.reduce(CGFloat(8.0)) { $0 + max(component.hideItemTitles ? 48.0 : 76.0, $1) }
                availableLength = min(availableLength, desiredLength)
            }
""" + replace_once(ours, "isCompact: component.isCompact,", "isCompact: component.isCompact || component.hideItemTitles,")
    if index in (9, 10):
        return replace_once(ours, "showsTitle: !component.isCompact", "showsTitle: !component.isCompact && !component.hideItemTitles")
    # The upstream layout and iconY helper support both axes. Its search-only
    # badge hiding already leaves badges visible in icon-only mode.
    return ours


def resolve_block(name, index, ours, base, theirs):
    if name == "BUILD":
        if theirs.strip() != 'load("@rules_cc//cc:objc_library.bzl", "objc_library")' or theirs.strip() not in ours:
            raise ValueError("Unexpected 13.1.1 BUILD imports")
        return ours
    if name == "ChatListController.swift":
        return chat_list_block(index, ours, base, theirs)
    if name == "TabBarContollerNode.swift":
        return tab_node_block(index, ours, base, theirs)
    if name == "TabBarComponent.swift":
        return tab_component_block(index, ours, base, theirs)
    if name == "Account.swift":
        return ours + ("    private let automaticProxyBootstrapDisposable = MetaDisposable()\n" if index == 1 else "")
    if name == "GlassBackgroundComponent.swift":
        return ("                #if compiler(>=6.2)\n" + ours) if index == 1 else (ours + theirs)
    if name == "StoryPeerListComponent.swift":
        return theirs
    if name == "ChatPinnedMessageTitlePanelNode.swift":
        if index == 1:
            return ours + theirs
        result = replace_once(theirs, "&& actionTitle == nil", "&& actionTitle == nil && !isSkeleton")
        return replace_once(result, "else if isReplyThread || actionTitle != nil {", "else if isReplyThread || actionTitle != nil || isSkeleton {")
    if name == "TelegramRootController.swift":
        return replace_once(theirs, "addRootControllers(showCallsTab: Bool)", "addRootControllers(showCallsTab: Bool, showNewsTab: Bool)")
    raise ValueError(f"Unreviewed 13.1.1 conflict: {name} #{index}")


def resolve_131(relative, merged):
    name = PurePosixPath(relative).name
    if name not in COUNTS or (name == "BUILD" and relative != "Telegram/BUILD"):
        return resolve_13(relative, merged)
    pattern = re.compile(r"^<<<<<<< upstream\n(.*?)^\|\|\|\|\|\|\| base\n(.*?)^=======\n(.*?)^>>>>>>> whitegram\n", re.MULTILINE | re.DOTALL)
    blocks = list(pattern.finditer(merged))
    if len(blocks) != COUNTS[name]:
        raise ValueError(f"13.1.1 conflict layout changed: {relative}")
    result = merged
    for index, match in reversed(list(enumerate(blocks, 1))):
        result = result[:match.start()] + resolve_block(name, index, *match.groups()) + result[match.end():]
    if name == "Account.swift":
        anchor = "            network?.updateProxySettings(activeServer)\n        }))\n"
        result = replace_once(result, anchor, anchor + "        self.automaticProxyBootstrapDisposable.set(managedAutomaticProxyBootstrap(accountManager: accountManager, network: network))\n")
        result = replace_once(result, "        self.networkEngineStateDisposable.dispose()\n", "        self.networkEngineStateDisposable.dispose()\n        self.automaticProxyBootstrapDisposable.dispose()\n")
        result = replace_once(result, "    deinit {\n        self.proxySettingsDisposable.dispose()\n        self.automaticProxyBootstrapDisposable.dispose()\n    }\n", "")
    if name == "TabBarComponent.swift":
        result = replace_once(result, "                if component.isCompact {\n                    return CGSize(width: 44.0", "                if !component.showsTitle {\n                    return CGSize(width: 44.0")
    if name == "StoryPeerListComponent.swift":
        result = replace_once(result, "titleSafeMaxX - titleSafeMinX - collapsedState.titleWidth", "titleSafeMaxX - titleSafeMinX - titleWidth")
    if name == "TelegramRootController.swift":
        result = replace_once(result, "    private var currentShowCallsTab: Bool = true", "    private var currentShowNewsTab: Bool = false\n    private var currentShowCallsTab: Bool = true")
        anchor = "        self.currentShowCallsTab = showCallsTab"
        if result.count(anchor) != 2:
            raise ValueError("Expected both root-tab state updates")
        result = result.replace(anchor, "        self.currentShowNewsTab = showNewsTab\n" + anchor)
        result = replace_once(result, "self.updateRootControllers(showCallsTab: self.currentShowCallsTab)", "self.updateRootControllers(showCallsTab: self.currentShowCallsTab, showNewsTab: self.currentShowNewsTab)")
    return result
