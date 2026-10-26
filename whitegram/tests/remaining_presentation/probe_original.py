"""Read-only whole-IPA ARM64 caller scan for the remaining presentation contract."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import zipfile

IPA_SHA256 = "5cf287812de7707dd21256281e645c29a9a5c0da3f66910746254842fce5ffbf"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", required=True, type=Path)
    parser.add_argument("--wgtool-root", required=True, type=Path)
    parser.add_argument("--pattern", default="appBadgeColorIsBlack|hideWhitegramUserBadge|hideOthersCustomMessageStyle|scammerProtection|[Ss]cammer")
    parser.add_argument("--resources", action="store_true")
    parser.add_argument("--module")
    parser.add_argument("--target", type=lambda value: int(value, 0))
    args = parser.parse_args()
    sys.path.insert(0, str(args.wgtool_root))
    from wgtool.binary import MachO, macho_offsets

    with args.ipa.open("rb") as stream:
        assert hashlib.file_digest(stream, "sha256").hexdigest() == IPA_SHA256
    images = []
    scanned = 0
    with zipfile.ZipFile(args.ipa) as archive:
        if args.resources:
            for member in archive.infolist():
                if "/WGBadge" in member.filename:
                    data = archive.read(member)
                    print(member.filename, len(data), hashlib.sha256(data).hexdigest())
            return
        for member in archive.infolist():
            if member.is_dir():
                continue
            if args.module and not member.filename.endswith("/" + args.module):
                continue
            with archive.open(member) as stream:
                header = stream.read(4)
            if header not in (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
                continue
            data = archive.read(member)
            for offset in macho_offsets(data):
                image = MachO(data, offset)
                if image.cpu != 0x100000C or image.encrypted:
                    continue
                scanned += 1
                targets = {address: name for address, name in image.imports.items() if re.search(args.pattern, name)}
                targets.update({address: name for name, address in image.exports.items() if re.search(args.pattern, name)})
                if args.target is not None:
                    if not args.module:
                        raise ValueError("An explicit address requires --module")
                    targets = {args.target: "explicit-target"}
                if not targets:
                    continue
                calls = []
                for site, target in image.direct_branches():
                    if target not in targets:
                        continue
                    start, end = image.function_bounds(site)
                    calls.append({"site": hex(site), "target": targets[target], "start": hex(start),
                                  "end": hex(end), "caller": image.by_address.get(start, []),
                                  "function_sha256": hashlib.sha256(image.function_bytes(start)).hexdigest()})
                images.append({"member": member.filename, "sha256": hashlib.sha256(data).hexdigest(),
                               "targets": {hex(k): v for k, v in targets.items()}, "calls": calls})
    print(json.dumps({"ipa_sha256": IPA_SHA256, "scanned_arm64_images": scanned, "images": images,
                      "limit": "Direct B/BL edges to matching imported/exported symbols; inlined and computed uses remain unknown."}, indent=2))


if __name__ == "__main__":
    main()
