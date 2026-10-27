"""Regression contracts for the 13.1.1 public merge and upstream storage guard."""

import json
import os
import subprocess
import sys
import unittest
from pathlib import Path

OVERLAY = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(OVERLAY))
from port_public import (
    BASE_REF,
    PUBLIC_REF,
    merge,
    normalize_indentation,
    resolver_for_revision,
    text,
)
from public_resolutions_131 import REVISION, resolve_131


class Telegram131PinTests(unittest.TestCase):
    def test_active_pin_selects_reviewed_resolver(self):
        pin = json.loads((OVERLAY / "upstream.json").read_text(encoding="utf-8"))
        self.assertEqual(pin["source_tag"], "release-13.1.1")
        self.assertEqual(pin["source_sha"], REVISION)
        self.assertIs(resolver_for_revision(REVISION), resolve_131)


@unittest.skipUnless(os.environ.get("WHITEGRAM_ASSEMBLED_SOURCE") and os.environ.get("WHITEGRAM_PUBLIC_SOURCE"), "Set assembled and public sources")
class Telegram131MergeTests(unittest.TestCase):
    def merged(self, relative):
        def read(root, revision):
            return text(subprocess.check_output(["git", "-C", root, "show", f"{revision}:{relative}"]))
        ours = read(os.environ["WHITEGRAM_ASSEMBLED_SOURCE"], REVISION)
        base = read(os.environ["WHITEGRAM_PUBLIC_SOURCE"], BASE_REF)
        theirs = read(os.environ["WHITEGRAM_PUBLIC_SOURCE"], PUBLIC_REF)
        result, clean = merge(ours, base, theirs)
        if not clean:
            result, clean = merge(ours, base, normalize_indentation(base, theirs))
        self.assertFalse(clean, relative)
        resolved = resolve_131(relative, result)
        self.assertNotIn("<<<<<<<", resolved)
        with self.assertRaises(ValueError):
            resolve_131(relative, result + "<<<<<<< upstream\nx\n||||||| base\ny\n=======\nz\n>>>>>>> whitegram\n")
        return resolved

    def test_login_retains_engine_key_validation_and_single_observer(self):
        result = self.merged("submodules/TelegramCore/Sources/Account/Account.swift")
        login = result.split("public class UnauthorizedAccount {", 1)[1].split("public func changedMasterDatacenterId", 1)[0]
        for marker in ("self.proxySettingsDisposable.set(", "self.automaticProxyBootstrapDisposable.set(", "    deinit {", "self.automaticProxyBootstrapDisposable.dispose()"):
            self.assertEqual(login.count(marker), 1, marker)
        for marker in ("network.permanentKeyUnknown =", "selector: prefetchedSelector", "network?.updateProxySettings(activeServer)", "self.networkEngineStateDisposable.dispose()"):
            self.assertIn(marker, login)
        self.assertNotIn("network.context.updateApiEnvironment", login)

    def test_news_tab_gate_survives_local_tab_refresh(self):
        result = self.merged("submodules/TelegramUI/Sources/TelegramRootController.swift")
        self.assertIn("if showNewsTab {", result)
        self.assertEqual(result.count("self.currentShowNewsTab = showNewsTab"), 2)
        self.assertIn("self.updateRootControllers(showCallsTab: self.currentShowCallsTab, showNewsTab: self.currentShowNewsTab)", result)

    def test_native_navigation_buttons_keep_folder_action_and_story_source(self):
        result = self.merged("submodules/ChatListUI/Sources/ChatListController.swift")
        self.assertIn("var folderButton: NavigationBarComponent.Button?", result)
        self.assertIn("parentController?.openWhiteGramFolderMenu(sourceView: sourceView)", result)
        self.assertIn("sourceView: UIView? = nil", result)
        self.assertNotIn("NavigationButtonComponentEnvironment", result)

    def test_side_placement_and_crossfade_survive_compact_menu(self):
        result = self.merged("submodules/TabBarUI/Sources/TabBarContollerNode.swift")
        for marker in ("sidePlacement.hiddenFrame", "previousPlacement.movedFrame", "tabBarFrameTransition.updateFrame", "sidePlacement != nil || whiteGramTabSettings.hideSearchButton", "params.toolbar == nil && !isCompactSearchActive"):
            self.assertIn(marker, result)

    def test_tab_item_layout_keeps_axes_and_title_independent_of_search(self):
        result = self.merged("submodules/TelegramUI/Components/TabBarComponent/Sources/TabBarComponent.swift")
        self.assertIn("tabBarItemsLayout(axis: component.axis", result)
        self.assertIn("showsTitle: !component.isCompact && !component.hideItemTitles", result)
        self.assertIn("alpha: component.isSearchActive ? 0.0 : 1.0", result)
        self.assertNotIn("availableItemsWidth", result)

    def test_pin_placeholder_is_not_presented_as_compact_action(self):
        result = self.merged("submodules/TelegramUI/Sources/ChatPinnedMessageTitlePanelNode.swift")
        self.assertIn("&& actionTitle == nil && !isSkeleton", result)
        self.assertIn("else if isReplyThread || actionTitle != nil || isSkeleton", result)


if __name__ == "__main__":
    unittest.main()
