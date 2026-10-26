"""Verify the focused evidence ledger against the unchanged original IPA."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", required=True, type=Path)
    parser.add_argument("--wgtool-root", required=True, type=Path)
    args = parser.parse_args()
    sys.path.insert(0, str(args.wgtool_root))
    from wgtool.binary import MachO
    evidence = json.loads(Path(__file__).with_name("evidence.json").read_text())
    with args.ipa.open("rb") as stream:
        assert hashlib.file_digest(stream, "sha256").hexdigest() == evidence["ipa_sha256"]
    functions = calls = 0
    with zipfile.ZipFile(args.ipa) as archive:
        for record in evidence["images"].values():
            data = archive.read(record["member"])
            assert hashlib.sha256(data).hexdigest() == record["sha256"]
            image = MachO(data)
            for function in record["functions"]:
                address = int(function["start"], 0)
                assert image.function_bounds(address) == (address, int(function["end"], 0))
                assert hashlib.sha256(image.function_bytes(address)).hexdigest() == function["sha256"]
                functions += 1
            branches = dict(image.direct_branches())
            for site, suffix in record["calls"].items():
                assert image.imports[branches[int(site, 0)]].endswith(suffix)
                calls += 1
            for address, expected in record.get("bytes", {}).items():
                offset = image.vm_offset(int(address, 0))
                raw = bytes.fromhex(expected)
                assert data[offset:offset + len(raw)] == raw
    print(f"Verified original IPA/image identities, {functions} complete function hashes, {calls} direct calls and the scammer refresh RET.")


if __name__ == "__main__":
    main()
