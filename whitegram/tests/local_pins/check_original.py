"""Validate retained pin-accessor evidence against the original IPA, read-only."""

import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile

IPA_SHA256 = "5cf287812de7707dd21256281e645c29a9a5c0da3f66910746254842fce5ffbf"
MEMBER = "Payload/Telegram.app/Frameworks/TelegramCoreFramework.framework/TelegramCoreFramework"


def segments(data):
    start = 0
    if data[:4] == bytes.fromhex("cafebabe"):
        count = struct.unpack_from(">I", data, 4)[0]
        arm = []
        for index in range(count):
            cpu, _, offset, _, _ = struct.unpack_from(">IIIII", data, 8 + 20 * index)
            if cpu == 0x100000C:
                arm.append(offset)
        if len(arm) != 1:
            raise ValueError("ambiguous arm64 image")
        start = arm[0]
    magic, cpu, _, _, count, _, _, _ = struct.unpack_from("<IIIIIIII", data, start)
    if magic != 0xFEEDFACF or cpu != 0x100000C:
        raise ValueError("expected arm64 Mach-O")
    offset = start + 32
    result = []
    for _ in range(count):
        command, size = struct.unpack_from("<II", data, offset)
        if size < 8 or offset + size > len(data):
            raise ValueError("invalid load command")
        if command == 0x19:
            vm, _, file_offset, file_size = struct.unpack_from("<QQQQ", data, offset + 24)
            result.append((vm, start + file_offset, file_size))
        offset += size
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", type=Path, required=True)
    parser.add_argument("--recovery", type=Path, required=True)
    args = parser.parse_args()
    with args.ipa.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if digest != IPA_SHA256:
        raise ValueError("original IPA digest mismatch")
    with zipfile.ZipFile(args.ipa) as archive:
        core = archive.read(MEMBER)
    records = json.loads((args.recovery / "native/TelegramCoreFramework-0/symbols.json").read_text(encoding="utf-8"))
    records = [record for record in records if "SGSettingsV20unlimitedPinnedChats" in record["symbol"] and "function_start" in record]
    if len(records) != 3:
        raise ValueError("expected getter, setter and modify accessor evidence")
    mappings = segments(core)
    for record in records:
        start, end = int(record["function_start"], 0), int(record["function_end"], 0)
        ranges = [(file + start - vm, end - start) for vm, file, size in mappings if vm <= start < end <= vm + size]
        if len(ranges) != 1:
            raise ValueError("unmapped/ambiguous accessor")
        offset, size = ranges[0]
        if hashlib.sha256(core[offset:offset + size]).hexdigest() != record["bytes_sha256"]:
            raise ValueError("accessor bytes differ from recovery")
    print(json.dumps({"ipa_sha256": digest, "core_sha256": hashlib.sha256(core).hexdigest(),
                      "accessors": [{key: row[key] for key in ("symbol", "function_start", "function_end", "bytes_sha256")} for row in records],
                      "coverage": "Original accessor identity/bytes only. The local store, merge policy and pagination are cleanroom design; original behavioral parity is not established."}, indent=2))


if __name__ == "__main__":
    main()
