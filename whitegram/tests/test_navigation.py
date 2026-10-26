import copy
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from navigation_patches import BOOLEAN_CAPABILITIES, RUNTIME_FILES, apply_navigation_patches, navigation_edits, navigation_patches
from source_patches import SourcePatches


class NavigationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="navigation-", dir=os.environ.get("WHITEGRAM_NAVIGATION_SCRATCH"))
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = os.environ.get("WHITEGRAM_NAVIGATION_SOURCE")
        self.preimages = {}
        for relative in sorted({edit.path for edit in navigation_edits()}):
            if self.source:
                data = (Path(self.source) / relative).read_bytes()
            else:
                data = "\n/* boundary */\n".join(edit.before for edit in navigation_edits() if edit.path == relative).encode()
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
            self.preimages[relative] = data

    def assertUnwritten(self):
        self.assertEqual(self.preimages, {path: (self.root / path).read_bytes() for path in self.preimages})

    def test_staging_replay_and_exact_reversal(self):
        patches = SourcePatches(self.root)
        navigation_patches(patches)
        first = copy.deepcopy((patches.pending, patches.features))
        navigation_patches(patches)
        self.assertEqual((patches.pending, patches.features), first)
        for edit in reversed(navigation_edits()):
            self.assertEqual(patches.pending[edit.path].count(edit.after), 1)
            patches.pending[edit.path] = patches.pending[edit.path].replace(edit.after, edit.before)
        self.assertEqual(patches.pending, patches.original)
        self.assertUnwritten()

    def test_wrapper_uses_parent_write_contract(self):
        real_write = SourcePatches.write
        writes = []

        def write(patches):
            writes.append(set(patches.pending))
            return real_write(patches)

        with patch.object(SourcePatches, "write", write):
            inventory = apply_navigation_patches(self.root)
            installed = {path: (self.root / path).read_bytes() for path in self.preimages}
            self.assertEqual(apply_navigation_patches(self.root), inventory)
            self.assertEqual(installed, {path: (self.root / path).read_bytes() for path in self.preimages})
        self.assertEqual(len(writes), 2)
        self.assertEqual(set(inventory), {edit.feature for edit in navigation_edits()})

    def test_every_missing_or_duplicate_anchor_rolls_back_staging(self):
        for edit in navigation_edits():
            for duplicate in (False, True):
                with self.subTest(path=edit.path, anchor=edit.before[:70], duplicate=duplicate):
                    patches = SourcePatches(self.root)
                    value = patches.read(edit.path)
                    patches.pending[edit.path] = value + edit.before if duplicate else value.replace(edit.before, "/* upstream changed */", 1)
                    patches.features["other-owner"] = {edit.path}
                    saved = copy.deepcopy((patches.original, patches.pending, patches.features))
                    with self.assertRaises(ValueError):
                        navigation_patches(patches)
                    self.assertEqual((patches.original, patches.pending, patches.features), saved)
        self.assertUnwritten()

    def test_late_failure_never_writes(self):
        edit = navigation_edits()[-1]
        target = self.root / edit.path
        target.write_bytes(target.read_bytes().replace(edit.before.encode(), b"changed", 1))
        self.preimages[edit.path] = target.read_bytes()
        with self.assertRaises(ValueError), patch.object(SourcePatches, "write") as write:
            apply_navigation_patches(self.root)
        write.assert_not_called()
        self.assertUnwritten()

    def test_mixed_and_duplicate_installed_code_rejected(self):
        patches = SourcePatches(self.root)
        navigation_patches(patches)
        for edit in navigation_edits():
            for extra in (edit.before, edit.after):
                with self.subTest(path=edit.path, extra=extra[:60]):
                    broken = copy.deepcopy(patches)
                    broken.pending[edit.path] += extra
                    saved = copy.deepcopy((broken.original, broken.pending, broken.features))
                    with self.assertRaises(ValueError):
                        navigation_patches(broken)
                    self.assertEqual((broken.original, broken.pending, broken.features), saved)
        self.assertUnwritten()

    def test_staging_preserves_other_owners(self):
        patches = SourcePatches(self.root)
        relative = navigation_edits()[0].path
        patches.read(relative)
        patches.pending[relative] += "\n// other owner\n"
        patches.features["other-owner"] = {relative}
        navigation_patches(patches)
        self.assertTrue(patches.pending[relative].endswith("// other owner\n"))
        self.assertEqual(patches.features["other-owner"], {relative})
        self.assertUnwritten()

    def test_scope_manifest_and_honest_capabilities(self):
        self.assertEqual(len(RUNTIME_FILES), len(set(RUNTIME_FILES.values())))
        for name, target in RUNTIME_FILES.items():
            self.assertTrue(name.startswith(("WhitegramNavigation", "WhitegramBackground")))
            self.assertTrue((ROOT / "cleanroom" / name).is_file())
            self.assertTrue(target.endswith(name))
        self.assertFalse(BOOLEAN_CAPABILITIES["showPostsFeed"])
        self.assertFalse(BOOLEAN_CAPABILITIES["classicInterface"])
        for edit in navigation_edits():
            self.assertNotIn("Preferences.swift", edit.path)
            self.assertNotIn("WhiteGramSettingsController", edit.path)
            self.assertNotIn("PortCapabilities", edit.path)
            self.assertNotIn("compactPanel =", edit.after)


if __name__ == "__main__":
    unittest.main()
