"""Reproducible Beta 3.2 anchors from the verified IPA; target is never run."""
import hashlib
import os
from pathlib import Path
import sys
import unittest
import zipfile

RECOVERY = Path(__file__).resolve().parents[3] / "whitegram-rebuild"
sys.path.insert(0, str(RECOVERY))
try:
    from wgtool.binary import MachO
except ImportError:
    MachO = None

IPA = Path(os.environ.get("WHITEGRAM_ORIGINAL_IPA", str(RECOVERY.parent / "Whitegram Beta 3.2 (13.0) [tg@heypaintech].ipa")))
SHA = "5cf287812de7707dd21256281e645c29a9a5c0da3f66910746254842fce5ffbf"


@unittest.skipUnless(IPA.is_file() and MachO is not None, "Original IPA and local wgtool/capstone required")
class OriginalHistoryEvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with IPA.open("rb") as stream:
            if hashlib.file_digest(stream, "sha256").hexdigest() != SHA:
                raise ValueError("Original IPA identity mismatch")
        with zipfile.ZipFile(IPA) as archive:
            cls.core = MachO(archive.read("Payload/Telegram.app/Frameworks/TelegramCoreFramework.framework/TelegramCoreFramework"))
            cls.ui = MachO(archive.read("Payload/Telegram.app/Frameworks/TelegramUIFramework.framework/TelegramUIFramework"))

    def test_spy_getters_are_shipped_disabled_not_claimed_live_consumers(self):
        self.assertEqual(self.core.function_bytes(0x23ec20).hex(), "00008052c0035fd6")
        for selector in (0x233aa8, 0x233b40):
            self.assertEqual(list(self.core.disassemble(selector))[0][2:], ("b", "#0x23ec20"))
        self.assertIn("_$s12TelegramCore16SGReadDatesStoreC8readDate3fors5Int32VSgs5Int64V_tF", self.core.exports)

    def test_display_switch_defaults_true_and_gates_original_block(self):
        instructions = {pc: (mnemonic, operands) for pc, _, mnemonic, operands in self.core.disassemble(0x21e720)}
        self.assertEqual(instructions[0x21e7d0], ("mov", "w19, #1"))
        ui = {pc: (mnemonic, operands) for pc, _, mnemonic, operands in self.ui.disassemble(0x188e4a8)}
        self.assertEqual(ui[0x189098c], ("bl", "#0x5421804"))
        self.assertEqual(ui[0x1890994], ("bl", "#0x54218b8"))
        self.assertEqual(ui[0x1890998], ("tbz", "w0, #0, #0x1890a30"))

    def test_original_online_archive_is_plain_array_with_additive_server_date(self):
        self.assertEqual(self.core.string_at(0xe98720), "wg_onlineHistory_v2")
        self.assertIn("_$s12TelegramCore20SGOnlineHistoryEntryV15serverTimestampSdSgvg", self.core.exports)
        decode_calls = [operands for _, _, mnemonic, operands in self.core.disassemble(0x21162c) if mnemonic == "bl"]
        optional_date = self.core.imports.get(0xe00064)
        self.assertIn("decodeIfPresent", optional_date)
        self.assertIn("#0xe00064", decode_calls)
        self.assertIn("#0xe00058", decode_calls)  # optional contact flag


if __name__ == "__main__": unittest.main()
