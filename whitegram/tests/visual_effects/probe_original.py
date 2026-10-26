"""Read-only focused ARM64 evidence probe; requires the existing wgtool environment."""

import argparse
import hashlib
import json
import math
import re
import struct
import sys
import zipfile
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--wgtool-root", required=True, type=Path)
    parser.add_argument("--module", default="TelegramUIFramework")
    parser.add_argument("--pattern", default="avatarBlur|avatarGlow|profileColorEffect|albumArtBlur|chatScrollAnimation|wgBubbleFisheyeEffect|particleEffect|particleMode|particleSpeed|particleDensity|wgBuildParticleEmitter")
    parser.add_argument("--function", type=lambda value: int(value, 0))
    parser.add_argument("--calls-only", action="store_true")
    parser.add_argument("--start", type=lambda value: int(value, 0))
    parser.add_argument("--end", type=lambda value: int(value, 0))
    parser.add_argument("--data", type=lambda value: int(value, 0), nargs="*")
    parser.add_argument("--strings", help="Case-insensitive regex over defined native C-string sections")
    parser.add_argument("--verify-record", type=Path, help="Verify recorded hash, strings, constant bytes and function bounds")
    args = parser.parse_args()
    sys.path.insert(0, str(args.wgtool_root))
    from wgtool.binary import MachO

    with zipfile.ZipFile(args.ipa) as archive:
        members = [name for name in archive.namelist() if name.endswith("/" + args.module)]
        if len(members) != 1:
            raise ValueError(members)
        data = archive.read(members[0])
    image = MachO(data)
    print("MEMBER", members[0], "SHA256", hashlib.sha256(data).hexdigest())
    if args.verify_record:
        record = json.loads(args.verify_record.read_text(encoding="utf-8"))
        assert record["member"] == members[0]
        assert record["member_sha256"] == hashlib.sha256(data).hexdigest()
        for item in record["strings"]:
            assert image.string_at(int(item["address"], 0)) == item["text"], item
        for item in record["constants"]:
            address = image.vm_offset(int(item["address"], 0))
            expected = bytes.fromhex(item["bytes"])
            assert data[address:address + len(expected)] == expected, item
            value = struct.unpack("<d" if item["type"] == "f64le" else "<f", expected)[0]
            assert math.isclose(value, item["value"], rel_tol=1e-7), item
        for item in record["functions"]:
            start = int(item["start"], 0)
            assert image.function_bounds(start) == (start, int(item["end_exclusive"], 0)), item
        print("VERIFIED", len(record["strings"]), "strings,", len(record["constants"]), "constants,", len(record["functions"]), "function bounds; analyst descriptions are not runtime assertions")
        return
    if args.strings:
        for section, address, offset, value in image.strings():
            text = value.decode("utf-8", "replace")
            if re.search(args.strings, text, re.IGNORECASE):
                print("STRING", section, hex(address), "file", hex(offset), repr(text))
        return
    for address in args.data or []:
        offset = image.vm_offset(address)
        print("DATA", hex(address), data[offset:offset + 8].hex(), "double", struct.unpack_from("<d", data, offset)[0], "float", struct.unpack_from("<f", data, offset)[0])
    if args.data:
        return
    if args.function is not None:
        print("BOUNDS", tuple(hex(value) for value in image.function_bounds(args.function)))
        pages = {}
        for address, _, mnemonic, operands in image.disassemble(args.function):
            target = int(operands[1:], 16) if mnemonic in ("bl", "b") and operands.startswith("#0x") else None
            symbol = image.imports.get(target) or " | ".join(image.by_address.get(target, []))
            if mnemonic == "adrp":
                reg, page = operands.split(", #")
                pages[reg] = int(page, 0)
            annotation = ""
            load = re.fullmatch(r"x1, \[(x\d+), #(0x[0-9a-f]+)\]", operands)
            if mnemonic == "ldr" and load and load[1] in pages:
                pointer = pages[load[1]] + int(load[2], 0)
                try:
                    value = image.unpack("<Q", image.vm_offset(pointer))[0]
                    annotation = image.string_at(value & 0xfffffffff)
                    if not annotation.isprintable() or len(annotation) > 160:
                        annotation = ""
                except ValueError:
                    pass
            in_range = (args.start is None or address >= args.start) and (args.end is None or address < args.end)
            if in_range and (not args.calls_only or symbol or annotation):
                print(hex(address), mnemonic, operands, symbol or annotation)
        return
    targets = {address: name for address, name in image.imports.items() if re.search(args.pattern, name)}
    targets.update({address: name for name, address in image.exports.items() if re.search(args.pattern, name)})
    for address, name in sorted(targets.items()):
        print("TARGET", hex(address), name)
    callers = {}
    for address, target in image.direct_branches():
        if target in targets:
            start, end = image.function_bounds(address)
            callers.setdefault(start, []).append((hex(address), targets[target]))
    for start, calls in sorted(callers.items()):
        print("CALLER", hex(start), " | ".join(image.by_address.get(start, [])))
        for call in calls:
            print(" ", *call)


if __name__ == "__main__":
    main()
