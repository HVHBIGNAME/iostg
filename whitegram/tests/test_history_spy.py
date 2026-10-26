"""Read-only pristine/assembled spy consumers and patch composition checks."""
import os
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from spy_patches import PEERS, READ_STATS, TITLES, SPY_RUNTIME_FILES, apply_spy_patches
from online_history_patches import apply_online_history_patches
from test_history_patches import MemoryRoot, PIN, parse_sources


class SpySourceTests(unittest.TestCase):
    def test_production_sources_parse_and_use_observed_account_bound_evidence(self):
        sources = {name: (ROOT / "cleanroom" / name).read_text(encoding="utf-8") for name in SPY_RUNTIME_FILES}
        for name, diagnostics in parse_sources(sources).items(): self.assertEqual(diagnostics, [], name)
        runtime = sources["WhitegramSpyRuntime.swift"]
        self.assertIn('guard enabled("trackLastOnline")', runtime)
        self.assertIn('guard enabled("saveReadDates")', runtime)
        self.assertIn("case .present: return presence", runtime)
        self.assertIn("Int64(presence.lastActivity) + 30 >= Int64(now): return presence", runtime)
        self.assertIn("captureQueue.async", runtime)
        self.assertIn("transaction.isPeerContact(peerId: id)", runtime)
        self.assertIn("default: continue", runtime)
        self.assertIn("accountPeerId.toInt64()", runtime)
        self.assertNotIn("Timer", runtime)
        self.assertNotIn("network.request", runtime)


@unittest.skipUnless(os.environ.get("WHITEGRAM_ASSEMBLED_SOURCE"), "Set WHITEGRAM_ASSEMBLED_SOURCE")
class SpyPatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(os.environ["WHITEGRAM_ASSEMBLED_SOURCE"])
        cls.paths = [PEERS, READ_STATS, *TITLES]
        cls.original = {path: subprocess.check_output(["git", "-C", str(root), "show", f"{PIN}:{path}"]).decode() for path in cls.paths}
        cls.assembled = {path: (root / path).read_text(encoding="utf-8") for path in cls.paths}

    def test_install_replay_and_both_online_assembly_orders(self):
        for files in (self.original, self.assembled):
            results = []
            for patchers in ((apply_spy_patches, apply_online_history_patches), (apply_online_history_patches, apply_spy_patches)):
                root = MemoryRoot(files)
                for patch in patchers: patch(root)
                first = root.texts()
                root.writes.clear()
                for patch in patchers: patch(root)
                self.assertEqual(root.texts(), first)
                self.assertEqual(root.writes, [])
                self.assertEqual(first[READ_STATS].count("getOutboxReadDate("), files[READ_STATS].count("getOutboxReadDate("))
                self.assertIn("accountPeerId: component.context.account.peerId", first[list(TITLES)[1]])
                self.assertIn("accountPeerId: context.account.peerId", first[list(TITLES)[2]])
                results.append(first)
            self.assertEqual(results[0], results[1])

    def test_late_anchor_and_partial_hook_fail_without_any_writes(self):
        files = dict(self.original)
        last = list(TITLES)[-1]
        files[last] = files[last].replace("EnginePeer.Presence(presence), relativeTo: Int32(timestamp), expanded: true)", "changedPresence)")
        root = MemoryRoot(files)
        with self.assertRaises(ValueError): apply_spy_patches(root)
        self.assertEqual(root.writes, [])
        root = MemoryRoot(self.original)
        apply_spy_patches(root)
        files = root.texts()
        files[PEERS] = files[PEERS].replace("acceptedPeerIds: Set(parsedPresences.keys)", "acceptedPeerIds: []", 1)
        root = MemoryRoot(files)
        with self.assertRaises(ValueError): apply_spy_patches(root)
        self.assertEqual(root.writes, [])

    def test_patched_swift_adds_no_parser_diagnostics(self):
        root = MemoryRoot(self.assembled)
        apply_spy_patches(root)
        before, after = parse_sources(self.assembled), parse_sources(root.texts())
        for path in self.paths: self.assertEqual(before[path], after[path], path)


if __name__ == "__main__": unittest.main()
