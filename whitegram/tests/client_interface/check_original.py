"""Read-only original IPA identity, exact call-site, and recovered OLED byte checks."""

import argparse
import hashlib
import json
from pathlib import Path
import sys
import struct
import zipfile

IPA_HASH = "5cf287812de7707dd21256281e645c29a9a5c0da3f66910746254842fce5ffbf"
UI_HASH = "7f64950144cc75631ceb9cc9365cd4d802d583e5315ee63498829a1c72cb3ac3"
UI_MEMBER = "Payload/Telegram.app/Frameworks/TelegramUIFramework.framework/TelegramUIFramework"
CALLS = {
    0x183e48: "newChatHeaderStyle",
    0x183e58: "classicInterface",
    0x1945d84: "newChatListUI",
    0x9a4504: "roundProfileButtons",
    0x31e3378: "reactionButtonGlow",
    0x2a3f0: "localPremium",
    0x2a408: "localPremiumNameColor",
    0x2a410: "localPremiumNameBgEmojiId",
    0x2a418: "localPremiumProfileColor",
    0x2a420: "localPremiumProfileBgEmojiId",
    0x2a428: "localPremiumEmojiStatusFileId",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", required=True, type=Path)
    parser.add_argument("--recovery", required=True, type=Path)
    parser.add_argument("--wgtool-root", required=True, type=Path)
    args = parser.parse_args()
    sys.path.insert(0, str(args.wgtool_root))
    from wgtool.binary import MachO, macho_offsets
    with args.ipa.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    assert digest == IPA_HASH, "IPA changed"
    with zipfile.ZipFile(args.ipa) as archive:
        data = archive.read(UI_MEMBER)
    assert hashlib.sha256(data).hexdigest() == UI_HASH, "UI framework changed"
    images = [MachO(data, offset) for offset in macho_offsets(data)]
    images = [image for image in images if image.cpu == 0x100000C and not image.encrypted]
    assert len(images) == 1
    image = images[0]
    branches = dict(image.direct_branches())
    for site, name in CALLS.items():
        assert name in image.imports[branches[site]], f"missing original consumer: {site:#x} {name}"
    evidence = json.loads((args.recovery / "theme-resolved" / "evidence.json").read_text(encoding="utf-8"))
    assert evidence["ipa_sha256"] == digest
    oled = next(record for record in evidence["images"]["ui"]["functions"] if "wgApplyOledTheme" in record["symbol"])
    start = int(oled["function_start"], 0)
    assert hashlib.sha256(image.function_bytes(start)).hexdigest() == oled["bytes_sha256"]
    opacity = struct.unpack_from("<f", data, image.vm_offset(0x556d1e4))[0]
    assert abs(opacity - 0.62) < 0.000001, "original shadow opacity changed"
    print(json.dumps({"ipa_sha256": digest, "ui_sha256": UI_HASH, "checked_original_calls": {hex(site): name for site, name in CALLS.items()},
                      "oled_function": oled["function_start"], "oled_bytes_sha256": oled["bytes_sha256"],
                      "reaction_shadow_opacity": opacity,
                      "coverage": "11 exact original call sites and recovered OLED bytes; static consumers, not pixel parity or runtime equivalence"}, indent=2))


if __name__ == "__main__":
    main()
