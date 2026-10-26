import copy
import os
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from source_patches import SourcePatches
from navigation_patches import navigation_patches, navigation_edits
from feed_classic_patches import feed_classic_patches, feed_classic_edits, apply_feed_classic_patches, RUNTIME_FILES


class FeedClassicTests(unittest.TestCase):
    def setUp(self):
        source = os.environ.get("WHITEGRAM_FEED_SOURCE")
        if not source:
            self.skipTest("Set WHITEGRAM_FEED_SOURCE to the read-only assembled 13.0 tree")
        self.scratch = tempfile.TemporaryDirectory(prefix="feed-classic-", dir=os.environ.get("WHITEGRAM_FEED_SCRATCH"))
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.reference = {}
        for relative in {edit.path for edit in (*navigation_edits(), *feed_classic_edits())}:
            data = (Path(source) / relative).read_bytes()
            self.reference[relative] = data
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        self.patches = SourcePatches(self.root)
        navigation_patches(self.patches)

    def test_full_navigation_feed_classic_replay(self):
        feed_classic_patches(self.patches)
        before = copy.deepcopy((self.patches.pending, self.patches.features))
        navigation_patches(self.patches)
        feed_classic_patches(self.patches)
        self.assertEqual((self.patches.pending, self.patches.features), before)

    def test_exact_reverse(self):
        before = dict(self.patches.pending)
        feed_classic_patches(self.patches)
        for edit in reversed(feed_classic_edits()):
            self.assertEqual(self.patches.pending[edit.path].count(edit.after), edit.count)
            self.patches.pending[edit.path] = self.patches.pending[edit.path].replace(edit.after, edit.before)
        for path, source in self.patches.pending.items():
            self.assertEqual(source, before.get(path, self.patches.original[path]))

    def test_missing_duplicate_and_mixed_anchors_rollback(self):
        for edit in feed_classic_edits():
            for mode in ("missing", "duplicate", "mixed"):
                with self.subTest(feature=edit.feature, path=edit.path, mode=mode):
                    patches = copy.deepcopy(self.patches)
                    if mode == "mixed":
                        feed_classic_patches(patches)
                        patches.pending[edit.path] += edit.before
                    else:
                        value = patches.read(edit.path)
                        patches.pending[edit.path] = value.replace(edit.before, "changed", 1) if mode == "missing" else value + edit.before
                    saved = copy.deepcopy((patches.original, patches.pending, patches.features))
                    with self.assertRaises(ValueError):
                        feed_classic_patches(patches)
                    self.assertEqual((patches.original, patches.pending, patches.features), saved)
        self.assertEqual(self.reference, {path: (self.root / path).read_bytes() for path in self.reference})

    def test_wrapper_replay(self):
        self.patches.write()
        report = apply_feed_classic_patches(self.root)
        before = {path: (self.root / path).read_bytes() for path in self.reference}
        self.assertEqual(apply_feed_classic_patches(self.root), report)
        self.assertEqual(before, {path: (self.root / path).read_bytes() for path in self.reference})

    def test_registry_and_scope(self):
        self.assertEqual(len(RUNTIME_FILES), len(set(RUNTIME_FILES.values())))
        for name, relative in RUNTIME_FILES.items():
            self.assertTrue(name.startswith(("WhitegramFeed", "WhitegramClassic")))
            self.assertTrue((ROOT / "cleanroom" / name).is_file())
            self.assertTrue(relative.endswith(name))
        for edit in feed_classic_edits():
            self.assertNotIn("WhitegramNavigation", edit.path)
            self.assertNotIn("WhitegramBackground", edit.path)
            self.assertNotIn("PortCapabilities", edit.path)
            self.assertNotIn("Preferences.swift", edit.path)


if __name__ == "__main__":
    unittest.main()
