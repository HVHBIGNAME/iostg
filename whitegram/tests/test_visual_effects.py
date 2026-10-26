"""Read-only upstream checks: all install/uninstall writes are intercepted in memory."""

import os
from pathlib import Path
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True
OVERLAY = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(OVERLAY))
import visual_effects_patches as visual
from source_patches import SourcePatches
from test_history_patches import MemoryRoot, PIN, parse_sources


class VisualRuntimeSources(unittest.TestCase):
    def test_runtime_sources_parse(self):
        sources = {name: (OVERLAY / "cleanroom" / name).read_text(encoding="utf-8") for name in visual.RUNTIME_FILES}
        for name, errors in parse_sources(sources).items():
            self.assertEqual(errors, [], name)

    def test_runtime_map_is_collision_free_and_stays_in_existing_dependency_modules(self):
        self.assertEqual(len(visual.RUNTIME_FILES), len(set(visual.RUNTIME_FILES.values())))
        for name, destination in visual.RUNTIME_FILES.items():
            self.assertTrue(name.startswith("WhitegramVisual"))
            self.assertTrue((OVERLAY / "cleanroom" / name).is_file())
            self.assertIn(destination.split("/")[1], ("TelegramCore", "TelegramPresentationData"))


@unittest.skipUnless(os.environ.get("WHITEGRAM_ASSEMBLED_SOURCE"), "Set WHITEGRAM_ASSEMBLED_SOURCE to the read-only assembled tree")
class VisualSourcePatches(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = Path(os.environ["WHITEGRAM_ASSEMBLED_SOURCE"])
        cls.paths = sorted({edit.path for edit in visual.visual_effects_edits()})
        cls.assembled = {path: (cls.source / path).read_text(encoding="utf-8") for path in cls.paths}
        # Exercise this stage at its installer position, even when CI supplies the
        # fully installed tree. Reverse only exact later adapters in this copy.
        from feed_classic_patches import feed_classic_edits
        from navigation_patches import navigation_edits
        for edits in (feed_classic_edits(), navigation_edits()):
            for edit in reversed(edits):
                if edit.path in cls.assembled:
                    cls.assembled[edit.path] = cls.assembled[edit.path].replace(edit.after, edit.before)
        baseline = MemoryRoot(cls.assembled)
        patches = SourcePatches(baseline)
        visual.visual_effects_patches(patches, reverse=True)
        patches.write()
        cls.assembled = baseline.texts()
        cls.pristine = {path: subprocess.check_output(["git", "-C", str(cls.source), "show", f"{PIN}:{path}"]).decode("utf-8") for path in cls.paths}

    def test_pristine_and_assembled_install_replay_and_uninstall_exactly(self):
        for sources in (self.pristine, self.assembled):
            with self.subTest(assembled=sources is self.assembled):
                root = MemoryRoot({**sources, "user.swift": "// user bytes\r\n"})
                original = dict(root.files)
                report = visual.apply_visual_effects_patches(root)
                self.assertEqual(set(root.writes), set(self.paths))
                installed = dict(root.files)
                root.writes.clear()
                self.assertEqual(visual.apply_visual_effects_patches(root), report)
                self.assertEqual(root.files, installed)
                self.assertEqual(root.writes, [])
                patches = SourcePatches(root)
                visual.visual_effects_patches(patches, reverse=True)
                patches.write()
                self.assertEqual(root.files, original)
                root.writes.clear()
                patches = SourcePatches(root)
                visual.visual_effects_patches(patches, reverse=True)
                patches.write()
                self.assertEqual(root.writes, [])

    def test_every_missing_or_ambiguous_original_anchor_fails_before_any_write(self):
        for edit in visual.visual_effects_edits():
            for replacement in ("/* missing visual anchor */\n", edit.before + edit.before):
                with self.subTest(path=edit.path, marker=edit.marker, duplicate=replacement == edit.before * 2):
                    root = MemoryRoot(self.assembled)
                    root.files[edit.path] = root.text(edit.path).replace(edit.before, replacement, 1).encode("utf-8")
                    original = dict(root.files)
                    with self.assertRaises(ValueError):
                        visual.apply_visual_effects_patches(root)
                    self.assertEqual(root.files, original)
                    self.assertEqual(root.writes, [])

    def test_modified_installed_blocks_reject_install_and_uninstall(self):
        root = MemoryRoot(self.assembled)
        visual.apply_visual_effects_patches(root)
        installed = root.texts()
        for edit in visual.visual_effects_edits():
            for reverse in (False, True):
                with self.subTest(marker=edit.marker, reverse=reverse):
                    altered = MemoryRoot(installed)
                    altered.files[edit.path] = altered.text(edit.path).replace(edit.marker + ":end", edit.marker + ":user-edit", 1).encode("utf-8")
                    before = dict(altered.files)
                    with self.assertRaises(ValueError):
                        visual.visual_effects_patches(SourcePatches(altered), reverse=reverse)
                    self.assertEqual(altered.files, before)
                    self.assertEqual(altered.writes, [])

    def test_staging_failure_rolls_back_only_this_scope(self):
        root = MemoryRoot({**self.assembled, "parent.swift": "old\n"})
        root.files[visual.ROOT] = b"// missing late anchor\n"
        patches = SourcePatches(root)
        patches.replace("parent-feature", "parent.swift", "old", "new")
        original = (dict(patches.original), dict(patches.pending), {key: set(paths) for key, paths in patches.features.items()})
        with self.assertRaises(ValueError):
            visual.visual_effects_patches(patches)
        self.assertEqual((patches.original, patches.pending, patches.features), original)
        self.assertEqual(root.writes, [])

    def test_stripped_install_markers_and_unmarked_consumer_conflicts_fail_closed(self):
        import re
        root = MemoryRoot(self.assembled)
        visual.apply_visual_effects_patches(root)
        for path in self.paths:
            with self.subTest(path=path):
                damaged = MemoryRoot(root.texts())
                damaged.files[path] = re.sub(r"^[ \t]*// whitegram-visual-\d+:(?:begin|end)\n", "", damaged.text(path), flags=re.MULTILINE).encode("utf-8")
                with self.assertRaises(ValueError):
                    visual.apply_visual_effects_patches(damaged)
                self.assertEqual(damaged.writes, [])

    def test_apply_rechecks_concurrent_drift_before_writing(self):
        from unittest.mock import patch
        root = MemoryRoot(self.assembled)
        stage = visual.visual_effects_patches

        def edit_during_stage(patches):
            stage(patches)
            root.files[visual.PROFILE] += b"// concurrent parent edit\n"

        with patch.object(visual, "visual_effects_patches", edit_during_stage):
            with self.assertRaisesRegex(ValueError, "source changed during staging"):
                visual.apply_visual_effects_patches(root)
        self.assertEqual(root.writes, [])
        self.assertTrue(root.files[visual.PROFILE].endswith(b"// concurrent parent edit\n"))

    def test_modified_sources_introduce_no_parser_errors(self):
        for sources in (self.pristine, self.assembled):
            root = MemoryRoot(sources)
            visual.apply_visual_effects_patches(root)
            self.assertEqual(parse_sources(root.texts()), parse_sources(sources))

    def test_target_modules_already_depend_on_presentation_runtime_and_use_source_globs(self):
        modules = ["submodules/TelegramUI", visual.BUBBLE.split("/Sources/")[0], visual.TABS.split("/Sources/")[0], visual.PROFILE.split("/Sources/")[0]]
        for module in modules:
            build = (self.source / module / "BUILD").read_text(encoding="utf-8")
            self.assertIn("//submodules/TelegramPresentationData", build)
        for module in ("TelegramCore", "TelegramPresentationData"):
            build = (self.source / "submodules" / module / "BUILD").read_text(encoding="utf-8")
            self.assertIn('"Sources/**/*.swift"', build)

    def test_callbacks_and_reuse_cleanup_are_at_real_consumers(self):
        root = MemoryRoot(self.assembled)
        visual.apply_visual_effects_patches(root)
        self.assertIn("whitegramPreviousImageUpdated?(image)", root.text(visual.PROFILE))
        self.assertIn("profileImageRepresentations", root.text(visual.PROFILE))
        self.assertIn("case let .starGift", root.text(visual.PROFILE))
        self.assertIn("currentAlbumArt == nil ? nil : image", root.text(visual.PLAYER))
        self.assertIn("strongSelf.currentAlbumArtInitialized = false", root.text(visual.PLAYER))
        bubble = root.text(visual.BUBBLE)
        self.assertIn("override public func reuse()", bubble)
        self.assertIn("if self.visibility == .none { self.whitegramVisualScroll.reset() }", bubble)
        self.assertIn("!self.mainContextSourceNode.isExtractedToContextPreview", bubble)
        self.assertIn("self.backgroundNode.view.addSubview(self.whitegramVisualParticles)", root.text(visual.CHAT))
        self.assertIn("self.view.addSubview(self.whitegramVisualParticles)", root.text(visual.ROOT))
        self.assertIn("self.reorderingItem == nil", root.text(visual.TABS))


if __name__ == "__main__":
    unittest.main()
