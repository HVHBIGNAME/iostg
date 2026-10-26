import ast
import copy
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import client_interface_patches as client
from source_patches import SourcePatches


class ClientInterfacePatchesTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="client-interface-", dir=os.environ.get("WHITEGRAM_CLIENT_SCRATCH"))
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        source = os.environ.get("WHITEGRAM_CLIENT_SOURCE")
        self.original = {}
        for relative in sorted({edit.path for edit in client.client_interface_edits()}):
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            if source:
                value = (Path(source) / relative).read_bytes()
            else:
                value = "\n/* boundary */\n".join(edit.before * edit.count for edit in client.client_interface_edits() if edit.path == relative).encode()
            path.write_bytes(value)
            self.original[relative] = value

    def assertPreimages(self):
        self.assertEqual({relative: (self.root / relative).read_bytes() for relative in self.original}, self.original)

    def test_precise_replay_and_line_endings(self):
        inventory = client.apply_client_interface_patches(self.root)
        installed = {relative: (self.root / relative).read_bytes() for relative in self.original}
        self.assertEqual(client.apply_client_interface_patches(self.root), inventory)
        self.assertEqual(installed, {relative: (self.root / relative).read_bytes() for relative in self.original})
        self.assertEqual(set(inventory), {edit.feature for edit in client.client_interface_edits()})
        for relative, value in installed.items():
            self.assertNotEqual(value, self.original[relative])
            if b"\r\n" in self.original[relative]:
                self.assertNotIn(b"\n", value.replace(b"\r\n", b""))

    def test_each_missing_anchor_rolls_back_staging(self):
        for edit in client.client_interface_edits():
            with self.subTest(feature=edit.feature, path=edit.path, anchor=edit.before[:80]):
                patches = SourcePatches(self.root)
                # Corrupt precisely this anchor before any mutation is staged.
                patches.read(edit.path)
                patches.pending[edit.path] = patches.pending[edit.path].replace(edit.before, "/* changed upstream */", 1)
                saved = copy.deepcopy((patches.original, patches.pending, patches.features))
                with self.assertRaises(ValueError):
                    client.client_interface_patches(patches)
                self.assertEqual((patches.original, patches.pending, patches.features), saved)
        self.assertPreimages()

    def test_late_invalid_anchor_writes_nothing(self):
        edit = client.client_interface_edits()[-1]
        path = self.root / edit.path
        path.write_bytes(path.read_bytes().replace(edit.before.encode(), b"changed", 1))
        self.original[edit.path] = path.read_bytes()
        with self.assertRaises(ValueError):
            client.apply_client_interface_patches(self.root)
        self.assertPreimages()
        self.assertFalse(list(self.root.rglob(".whitegram-client-*")))

    def test_mixed_and_duplicate_installed_hooks_rejected(self):
        client.apply_client_interface_patches(self.root)
        edit = client.client_interface_edits()[0]
        path = self.root / edit.path
        installed = path.read_text(encoding="utf-8")
        for extra in (edit.before, edit.after):
            with self.subTest(extra=extra[:80]):
                path.write_text(installed + "\n" + extra, encoding="utf-8")
                before = path.read_bytes()
                with self.assertRaises(ValueError):
                    client.apply_client_interface_patches(self.root)
                self.assertEqual(path.read_bytes(), before)

    def test_io_failure_restores_exact_bytes(self):
        real_replace = os.replace
        calls = 0

        def fail_once(source, destination):
            nonlocal calls
            calls += 1
            if calls == 3:
                raise OSError("simulated replacement failure")
            return real_replace(source, destination)

        with patch.object(client.os, "replace", side_effect=fail_once):
            with self.assertRaisesRegex(OSError, "simulated"):
                client.apply_client_interface_patches(self.root)
        self.assertPreimages()
        self.assertFalse(list(self.root.rglob(".whitegram-client-*")))

    def test_runtime_registry_and_scope(self):
        cleanroom = Path(client.__file__).parent / "cleanroom"
        self.assertEqual(len(client.CLIENT_INTERFACE_RUNTIME_FILES), 10)
        for name, target in client.CLIENT_INTERFACE_RUNTIME_FILES.items():
            self.assertTrue((cleanroom / name).is_file())
            self.assertTrue(name.startswith(("WhitegramClientInterface", "WhitegramLocalPremium", "WhitegramAccountStrip")))
            self.assertTrue(target.endswith(name))
        self.assertFalse(client.CLIENT_INTERFACE_BOOLEAN_CAPABILITIES["unlimitedPinnedChats"])
        self.assertFalse(client.CLIENT_INTERFACE_BOOLEAN_CAPABILITIES["classicInterface"])
        for edit in client.client_interface_edits():
            self.assertNotIn("TogglePeerChatPinned", edit.path)
            self.assertNotIn("TelegramApi", edit.path)
            self.assertNotIn("PortCapabilities", edit.path)
        ast.parse(Path(client.__file__).read_text(encoding="utf-8"))

    def test_composed_transaction_preserves_other_owner_edits(self):
        patches = SourcePatches(self.root)
        path = client.client_interface_edits()[0].path
        patches.read(path)
        patches.pending[path] += "\n// independently staged owner edit\n"
        patches.features["other-owner"] = {path}
        client.client_interface_patches(patches)
        self.assertTrue(patches.pending[path].endswith("// independently staged owner edit\n"))
        self.assertEqual(patches.features["other-owner"], {path})
        self.assertPreimages()

    def test_card_relayout_uses_unmodified_parameters(self):
        patches = SourcePatches(self.root)
        client.client_interface_patches(patches)
        path = "submodules/ChatListUI/Sources/Node/ChatListItem.swift"
        self.assertIn("let whitegramOriginalParams = params", patches.pending[path])
        self.assertIn("nextHasActiveRevealControls, whitegramOriginalParams, countersSize)", patches.pending[path])

    def test_concurrent_source_change_is_not_overwritten(self):
        real_temporary = client._temporary
        changed = False
        relative = client.client_interface_edits()[0].path

        def change_source(path, content):
            nonlocal changed
            temporary = real_temporary(path, content)
            if not changed:
                changed = True
                (self.root / relative).write_bytes(b"concurrent owner edit")
            return temporary

        with patch.object(client, "_temporary", side_effect=change_source):
            with self.assertRaisesRegex(ValueError, "changed during preflight"):
                client.apply_client_interface_patches(self.root)
        self.original[relative] = b"concurrent owner edit"
        self.assertPreimages()
        self.assertFalse(list(self.root.rglob(".whitegram-client-*")))

    def test_failed_rollback_retains_recoverable_preimages(self):
        real_replace = os.replace
        calls = 0

        def fail_commit_and_rollback(source, destination):
            nonlocal calls
            calls += 1
            if calls >= 3:
                raise OSError("simulated volume failure")
            return real_replace(source, destination)

        with patch.object(client.os, "replace", side_effect=fail_commit_and_rollback):
            with self.assertRaisesRegex(RuntimeError, "retained preimages"):
                client.apply_client_interface_patches(self.root)
        retained = list(self.root.rglob(".whitegram-client-*"))
        self.assertTrue(retained)
        for relative, original in self.original.items():
            self.assertTrue(any(path.parent == (self.root / relative).parent and path.read_bytes() == original for path in retained))


if __name__ == "__main__":
    unittest.main()
