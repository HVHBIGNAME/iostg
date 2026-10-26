import copy
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import local_pins_patches as pins
from source_patches import SourcePatches


class LocalPinsPatchesTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="local-pins-", dir=os.environ.get("WHITEGRAM_LOCAL_PINS_SCRATCH"))
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        source = os.environ.get("WHITEGRAM_LOCAL_PINS_SOURCE")
        self.preimages = {}
        for relative in sorted({edit.path for edit in pins.local_pins_edits()}):
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            data = ((Path(source) / relative).read_bytes() if source else
                    "\n/* fixture boundary */\n".join(edit.before * edit.count for edit in pins.local_pins_edits() if edit.path == relative).encode())
            path.write_bytes(data)
            self.preimages[relative] = data

    def snapshot(self):
        return {relative: (self.root / relative).read_bytes() for relative in self.preimages}

    def test_precise_replay(self):
        inventory = pins.apply_local_pins_patches(self.root)
        first = self.snapshot()
        self.assertEqual(inventory, pins.apply_local_pins_patches(self.root))
        self.assertEqual(first, self.snapshot())
        self.assertEqual(set(inventory), {edit.feature for edit in pins.local_pins_edits()})
        for relative, original in self.preimages.items():
            self.assertNotEqual(first[relative], original)
            if b"\r\n" in original:
                self.assertNotIn(b"\n", first[relative].replace(b"\r\n", b""))

    def test_every_missing_anchor_restores_composed_staging(self):
        for edit in pins.local_pins_edits():
            with self.subTest(feature=edit.feature, anchor=edit.before):
                transaction = SourcePatches(self.root)
                transaction.read(edit.path)
                transaction.pending[edit.path] = transaction.pending[edit.path].replace(edit.before, "// missing anchor", 1)
                transaction.features["parent-feature"] = {"parent.swift"}
                saved = copy.deepcopy((transaction.original, transaction.pending, transaction.features))
                with self.assertRaises(ValueError):
                    pins.local_pins_patches(transaction)
                self.assertEqual(saved, (transaction.original, transaction.pending, transaction.features))
        self.assertEqual(self.preimages, self.snapshot())

    def test_late_failure_has_no_writes(self):
        edit = pins.local_pins_edits()[-1]
        path = self.root / edit.path
        path.write_text(path.read_text().replace(edit.before, "// missing"), encoding="utf-8")
        before = self.snapshot()
        with self.assertRaises(ValueError):
            pins.apply_local_pins_patches(self.root)
        self.assertEqual(before, self.snapshot())

    def test_mixed_or_duplicate_rejected(self):
        pins.apply_local_pins_patches(self.root)
        edit = pins.local_pins_edits()[0]
        path = self.root / edit.path
        installed = path.read_bytes()
        for extra in (edit.before, edit.after):
            path.write_bytes(installed + extra.encode())
            before = self.snapshot()
            with self.assertRaises(ValueError):
                pins.apply_local_pins_patches(self.root)
            self.assertEqual(before, self.snapshot())

    def test_io_failure_rolls_back(self):
        replace = os.replace
        calls = 0

        def fail_third(source, destination):
            nonlocal calls
            calls += 1
            if calls == 3:
                raise OSError("injected replacement failure")
            return replace(source, destination)

        with patch.object(pins.os, "replace", side_effect=fail_third), self.assertRaises(OSError):
            pins.apply_local_pins_patches(self.root)
        self.assertEqual(self.preimages, self.snapshot())
        self.assertFalse(list(self.root.rglob(".whitegram-local-pins-*")))

    def test_concurrent_preimage_change_is_rejected(self):
        prepare = pins._temporary
        first = next(iter(self.preimages))
        modified = False

        def concurrent(path, content):
            nonlocal modified
            result = prepare(path, content)
            if not modified:
                modified = True
                (self.root / first).write_bytes(b"concurrent owner")
            return result

        with patch.object(pins, "_temporary", side_effect=concurrent), self.assertRaises(ValueError):
            pins.apply_local_pins_patches(self.root)
        self.assertEqual((self.root / first).read_bytes(), b"concurrent owner")
        for relative in self.preimages.keys() - {first}:
            self.assertEqual((self.root / relative).read_bytes(), self.preimages[relative])

    def test_runtime_map_and_no_cloud_limit_edits(self):
        root = Path(__file__).resolve().parents[1]
        for basename in pins.RUNTIME_FILES:
            self.assertTrue((root / "cleanroom" / basename).is_file())
        self.assertTrue(pins.LOCAL_PINS_BOOLEAN_CAPABILITIES["unlimitedPinnedChats"])
        for edit in pins.local_pins_edits():
            self.assertNotIn("UserLimitsConfiguration", edit.path)
            self.assertNotIn("setPinnedItemIds(", edit.after)
            self.assertNotIn("addSynchronizePinnedChatsOperation(", edit.after)


if __name__ == "__main__":
    unittest.main()
