import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import tree_sitter_swift
from account_settings_patches import apply_account_settings_patches
from source_patches import SourcePatches
from tree_sitter import Language, Parser


class AccountSettingsTests(unittest.TestCase):
    def test_controller_and_foundation_account_checks_parse(self):
        parser = Parser(Language(tree_sitter_swift.language()))
        for path in [ROOT / "cleanroom/WhitegramAccountSettingsController.swift", ROOT / "tests/settings_transfer/WhitegramAccountSettingsChecks.swift"]:
            pending = [parser.parse(path.read_bytes()).root_node]
            while pending:
                node = pending.pop()
                self.assertFalse(node.type == "ERROR" or node.is_missing, f"{path}:{node.start_point}")
                pending.extend(node.children)

    @unittest.skipUnless(os.environ.get("WHITEGRAM_ASSEMBLED_SOURCE"), "Set WHITEGRAM_ASSEMBLED_SOURCE")
    def test_primary_profile_selection_replays_without_reference_writes(self):
        root = Path(os.environ["WHITEGRAM_ASSEMBLED_SOURCE"])
        staged = SourcePatches(root)
        with patch("account_settings_patches.SourcePatches", return_value=staged), patch.object(staged, "write", return_value={}):
            apply_account_settings_patches(root)
            first = dict(staged.pending)
            apply_account_settings_patches(root)
            self.assertEqual(first, staged.pending)
        for relative, text in staged.original.items():
            self.assertEqual((root / relative).read_text(encoding="utf-8"), text)
