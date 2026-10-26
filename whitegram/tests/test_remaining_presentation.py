"""Real-source staging/replay/ambiguity checks; the assembled tree stays read-only."""

import ast
import hashlib
import json
import os
from pathlib import Path
import struct
import sys
import unittest
from unittest.mock import patch

WHITEGRAM = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(WHITEGRAM))
import remaining_presentation_patches as remaining
from source_patches import SourcePatches
from test_appearance_extensions import MemoryRoot, syntax_errors

SOURCE = os.environ.get("WHITEGRAM_REMAINING_SOURCE") or os.environ.get("WHITEGRAM_ASSEMBLED_SOURCE")
TARGETS = (remaining.APP, remaining.ROOT, remaining.LIST, remaining.TITLE, remaining.BUBBLE, remaining.ITEMS, remaining.SCREEN)


def stage(root):
    edits = []
    replace = remaining._replace

    def record(patches, feature, path, before, after, count=1):
        replace(patches, feature, path, before, after, count)
        edits.append((path, before, after, count))

    patches = SourcePatches(root)
    with patch.object(remaining, "_replace", record):
        remaining.remaining_presentation_patches(patches)
    return patches, edits


class RemainingSourceTests(unittest.TestCase):
    def test_swift_syntax_and_registry(self):
        self.assertEqual(len(set(remaining.RUNTIME_FILES.values())), len(remaining.RUNTIME_FILES))
        for name in remaining.RUNTIME_FILES:
            self.assertTrue(name.startswith("WhitegramRemaining"))
            self.assertEqual(syntax_errors((WHITEGRAM / "cleanroom" / name).read_bytes()), [], name)
        ast.parse((WHITEGRAM / "remaining_presentation_patches.py").read_text(encoding="utf-8"))

    def test_exact_information_keys_exist_in_recovered_localization(self):
        info = (WHITEGRAM / "cleanroom/WhitegramRemainingInformation.swift").read_text(encoding="utf-8")
        localization = (WHITEGRAM / "generated/WhitegramLocalizationStrings.swift").read_text(encoding="utf-8")
        mapping = {
            "hideChannelAdsInfo": "s.hideChannelAds.desc",
            "hideWhitegramUserBadgeInfo": "s.hideWhitegramUserBadge.desc",
            "hideOthersCustomMessageStyleInfo": "s.hideOthersCustomMsgStyle.desc",
            "iconsInfo": "icons.info",
        }
        for key, text in mapping.items():
            self.assertIn(f'"{key}": "{text}"', info)
            self.assertIn(f'"{text}": [', localization)
        self.assertIn('"iconPackSitePreview": "s.createIconPack"', info)
        self.assertIn('"wh.createIconPack": [', localization)

    def test_original_resource_bytes_and_asset_scale(self):
        hashes = {
            "WGBadgeBlack": "16e707432b2b8a52a2c10c7766ac26fa0d77faa2c693a37e83e61b9b15717219",
            "WGBadgeWhite": "cda3a6b7c104fd6ab87784551a06f52a77bf232c14ef1079f27490f62724ad6f",
        }
        for name, expected in hashes.items():
            folder = WHITEGRAM / f"tests/remaining_presentation/assets/{name}.imageset"
            data = (folder / (name + ".png")).read_bytes()
            self.assertEqual(hashlib.sha256(data).hexdigest(), expected)
            self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
            offset = data.index(b"IHDR") + 4
            width, height = struct.unpack_from(">II", data, offset)
            self.assertEqual((width, height), (176, 44))
            self.assertEqual(json.loads((folder / "Contents.json").read_text())["images"][0]["scale"], "2x")

    def test_badge_service_reuses_existing_profile_endpoint_and_grant_policy(self):
        source = (WHITEGRAM / "cleanroom/WhitegramRemainingBadgeService.swift").read_text(encoding="utf-8")
        self.assertIn("service.fetch(WhitegramProfileBadge.self, resource: .badge", source)
        self.assertIn("hasGrantedBadge(granted: badge.granted", source)
        self.assertIn("currentSession() == session", source)
        self.assertNotIn("URLSession", source)
        self.assertNotIn("badge.enabled", source)


@unittest.skipUnless(SOURCE, "Set WHITEGRAM_REMAINING_SOURCE to the assembled read-only checkout")
class RemainingPatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.files = {path: (Path(SOURCE) / path).read_text(encoding="utf-8") for path in TARGETS}
        _, cls.edits = stage(MemoryRoot(cls.files))
        # Accept both pre-integration and already assembled candidates.
        for path, before, after, count in reversed(cls.edits):
            if cls.files[path].count(after) == count:
                cls.files[path] = cls.files[path].replace(after, before)

    def test_all_consumers_stage_parse_and_replay(self):
        root = MemoryRoot(self.files)
        patches, _ = stage(root)
        self.assertEqual(root.writes, [])
        report = patches.write()
        self.assertEqual(set(report), {"hideWhitegramUserBadge", "appBadgeColorIsBlack", "scammerProtection"})
        self.assertEqual(set(root.writes), set(TARGETS))
        first = dict(root.files)
        root.writes.clear()
        self.assertEqual(remaining.apply_remaining_presentation_patches(root), report)
        self.assertEqual(root.files, first)
        self.assertEqual(root.writes, [])
        for path in TARGETS:
            # The pinned tree uses newer Swift syntax (nonisolated(unsafe)) which
            # this tree-sitter grammar does not accept; swiftc parses the full files.
            actual = [(kind, text) for _, _, kind, text in syntax_errors(root.files[path])]
            baseline = [(kind, text) for _, _, kind, text in syntax_errors(self.files[path].encode())]
            self.assertEqual(actual, baseline, path)

    def test_every_missing_duplicate_or_mixed_anchor_rejects_before_writes(self):
        for path, before, after, _ in self.edits:
            for replacement in ("/* absent anchor */", before + before, before + after, after + after):
                with self.subTest(path=path, anchor=before[:65], replacement=replacement[:25]):
                    root = MemoryRoot(self.files)
                    root.files[path] = root.text(path).replace(before, replacement, 1).encode()
                    original = dict(root.files)
                    with self.assertRaises(ValueError):
                        remaining.apply_remaining_presentation_patches(root)
                    self.assertEqual(root.files, original)
                    self.assertEqual(root.writes, [])

    def test_no_shared_router_or_preferences_edits_and_exact_reversal(self):
        root = MemoryRoot({**self.files, "unrelated.swift": "// user work\r\n"})
        patches, edits = stage(root)
        self.assertFalse(any("Preferences.swift" in path or "Capabilities" in path or "SettingsScreen" in path for path in patches.pending))
        patches.write()
        for path, before, after, count in reversed(edits):
            self.assertEqual(root.text(path).count(after), count)
            root.files[path] = root.text(path).replace(after, before).encode()
        self.assertEqual(root.files, MemoryRoot({**self.files, "unrelated.swift": "// user work\r\n"}).files)

    def test_native_identity_and_render_boundaries(self):
        root = MemoryRoot(self.files)
        remaining.apply_remaining_presentation_patches(root)
        bubble = root.text(remaining.BUBBLE)
        self.assertIn("whitegramRemainingBadgeUserId(effectiveAuthor)", bubble)
        self.assertIn("!isPreview && authorNameString != nil", bubble)
        self.assertIn("surface: .post", bubble)
        self.assertIn("surface: .chatList", root.text(remaining.LIST))
        self.assertIn("surface: .chatHeader", root.text(remaining.TITLE))
        self.assertNotIn("remainingBadge", root.text(remaining.ITEMS))
        self.assertIn("whitegramRemainingScammerItem(data: data", root.text(remaining.ITEMS))
        self.assertNotIn("applicationIconBadgeNumber", root.text(remaining.ROOT))


if __name__ == "__main__":
    unittest.main()
