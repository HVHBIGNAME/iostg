"""Read-only wgtool ARM64 recovery for the selected Whitegram 3.2 IPA."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import zipfile

EXPECTED_IPA = "5cf287812de7707dd21256281e645c29a9a5c0da3f66910746254842fce5ffbf"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", required=True, type=Path)
    parser.add_argument("--wgtool-root", required=True, type=Path)
    parser.add_argument("--recovery", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--function", action="append", default=[])
    parser.add_argument("--metadata", action="append", default=[], help="UI metadata address:byte length; report in-range code pointers")
    parser.add_argument("--region", action="append", default=[], help="UI start:end code region for bounded function recovery")
    args = parser.parse_args()
    if args.output.exists() or not args.output.parent.is_dir():
        parser.error("output must be absent with an existing parent")
    sys.path.insert(0, str(args.wgtool_root))
    from wgtool.binary import MachO, macho_offsets
    from wgtool.audit_methods import objc_methods
    with args.ipa.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if digest != EXPECTED_IPA:
        raise ValueError("Different original IPA")
    report = {"ipa_sha256": digest, "authority": "original bytes, static ARM64 calls; no runtime observation", "images": {}}
    with zipfile.ZipFile(args.ipa) as archive:
        for label in ("TelegramUIFramework", "TelegramCoreFramework"):
            member = f"Payload/Telegram.app/Frameworks/{label}.framework/{label}"
            data = archive.read(member)
            images = [MachO(data, offset) for offset in macho_offsets(data)]
            image, = [item for item in images if item.cpu == 0x100000C and not item.encrypted]
            matcher = re.compile(r"(?:WG(?:Posts)?Feed|classicInterface|showPostsFeed)", re.I)
            symbols = {name: hex(address) for name, address in image.exports.items() if matcher.search(name)}
            imports = {address: name for address, name in image.imports.items() if matcher.search(name)}
            selected = set()
            for name, address in image.exports.items():
                if matcher.search(name) and image.text.address <= address < image.text.address + image.text.size:
                    selected.add(image.function_bounds(address)[0])
            types = json.loads((args.recovery / "native" / (label + "-0") / "types.json").read_text(encoding="utf-8"))
            types = [item for item in types if "Feed" in item["name"] and item["name"].startswith("WG")]
            for item in types:
                address = int(item["descriptor_address"], 16) + 12
                delta = image.unpack("<i", image.vm_offset(address))[0]
                if delta:
                    selected.add(image.function_bounds(address + delta)[0])
                    item["metadata_accessor"] = hex(address + delta)
            classes, issues = objc_methods(image)
            classes = [item for item in classes if "WG" in item["name"] and "Feed" in item["name"]]
            for item in classes:
                for method in item["instance_methods"] + item["class_methods"]:
                    if method["implementation"]:
                        selected.add(image.function_bounds(int(method["implementation"], 16))[0])
            branches = list(image.direct_branches())
            metadata_pointers = []
            if label == "TelegramUIFramework":
                for specification in args.metadata:
                    address, length = (int(value, 0) for value in specification.split(":"))
                    if not 0 < length <= 4096:
                        raise ValueError("Metadata scan exceeds 4096 bytes")
                    for slot in range(address, address + length, 8):
                        word = image.unpack("<Q", image.vm_offset(slot))[0]
                        # This arm64 image uses dyld's 64-bit chained-rebase words;
                        # preserve the word and report the low-36-bit target only as a candidate.
                        target = word if word < (1 << 36) else (word & ((1 << 36) - 1) if word >> 63 == 0 else 0)
                        if 0x5b0000 <= target < 0x5d3000:
                            start = image.function_bounds(target)[0]
                            metadata_pointers.append({"slot": hex(slot), "raw_word": hex(word), "target": hex(target), "function": hex(start), "role": "metadata code-pointer candidate"})
                            selected.add(start)
                for _ in range(2):
                    selected.update(image.function_bounds(target)[0] for site, target in branches
                        if 0x5b0000 <= target < 0x5d3000 and image.function_bounds(site)[0] in selected)
            calls = [{"site": hex(site), "caller": hex(image.function_bounds(site)[0]), "target": hex(target), "name": imports[target]}
                     for site, target in branches if target in imports]
            selected.update(int(item["caller"], 16) for item in calls)
            # Explicit one-hop callers of named/metadata/method roots, not an unbounded call graph.
            roots = set(selected)
            incoming = [{"site": hex(site), "caller": hex(image.function_bounds(site)[0]), "target": hex(target)}
                        for site, target in branches if target in roots]
            # Retain the complete incoming-reference list without expanding unrelated
            # callers of shared initializers/accessors into full function dossiers.
            if label == "TelegramUIFramework":
                selected.update(int(value, 0) for value in args.function)
                for region in args.region:
                    lower, upper = (int(value, 0) for value in region.split(":"))
                    if not 0 < upper - lower <= 128 * 1024:
                        raise ValueError("Code region exceeds 128 KiB")
                    selected.update(address for address in image.functions if lower <= address < upper)
            functions = []
            for start in sorted(selected):
                instructions = []
                for address, _, mnemonic, operands in image.disassemble(start):
                    names = []
                    if mnemonic in ("bl", "b") and operands.startswith("#"):
                        target = int(operands[1:], 0)
                        names = image.by_address.get(target, [])
                        if target in image.imports:
                            names = [image.imports[target]]
                    instructions.append(f"{address:#x}: {mnemonic} {operands}" + (" ; " + " | ".join(names) if names else ""))
                retain = label == "TelegramCoreFramework" or 0x5b0000 <= start < 0x5d3000 or start in {0x561860, 0x5623c0, 0x183e38} or start in {int(value, 0) for value in args.function}
                functions.append({"start": hex(start), "end": hex(image.function_bounds(start)[1]),
                    "symbols": image.by_address.get(start, []), "sha256": hashlib.sha256(image.function_bytes(start)).hexdigest(),
                    "instruction_count": len(instructions), "assembly": instructions if retain else [], "assembly_retained": retain})
            report["images"][label] = {"member": member, "sha256": hashlib.sha256(data).hexdigest(),
                "symbols": symbols, "types": types, "objc_classes": classes, "objc_decode_issues": {"total": len(issues), "examples": issues[:8]},
                "metadata_code_pointers": metadata_pointers, "preference_calls": calls, "root_callers": incoming, "functions": functions}
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({label: {"symbols": len(data["symbols"]), "types": [item["name"] for item in data["types"]],
        "preference_calls": len(data["preference_calls"]), "functions": len(data["functions"])}
        for label, data in report["images"].items()}, indent=2))


if __name__ == "__main__":
    main()
