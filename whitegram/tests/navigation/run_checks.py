"""Validate against a read-only assembled source; compile only inside fresh scratch."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from navigation_patches import RUNTIME_FILES, apply_navigation_patches, navigation_edits, navigation_patches
from source_patches import SourcePatches


def swift_path(path):
    path = path.resolve()
    if sys.platform == "win32":
        value = path.as_posix()
        return "/mnt/" + value[0].lower() + value[2:]
    return str(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--scratch-parent", required=True, type=Path)
    parser.add_argument("--swiftc", default="/opt/swift/usr/bin/swiftc")
    args = parser.parse_args()
    if not args.source.is_dir() or not args.scratch_parent.is_dir():
        parser.error("source and scratch parent must exist")
    prefix = ["wsl", "--"] if sys.platform == "win32" else []
    paths = sorted({edit.path for edit in navigation_edits()})
    originals = {path: (args.source / path).read_bytes() for path in paths}
    with tempfile.TemporaryDirectory(prefix="navigation-swift-", dir=args.scratch_parent) as temporary:
        scratch = Path(temporary)
        for path, data in originals.items():
            target = scratch / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        staged = SourcePatches(scratch)
        navigation_patches(staged)
        for edit in reversed(navigation_edits()):
            staged.pending[edit.path] = staged.pending[edit.path].replace(edit.after, edit.before)
        assert staged.pending == staged.original, "Exact source reversal failed"
        inventory = apply_navigation_patches(scratch)
        installed = {path: (scratch / path).read_bytes() for path in paths}
        assert apply_navigation_patches(scratch) == inventory
        assert installed == {path: (scratch / path).read_bytes() for path in paths}, "Replay changed bytes"
        for name, relative in RUNTIME_FILES.items():
            target = scratch / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / "cleanroom" / name, target)
        files = sorted(scratch.rglob("*.swift"))
        for file in files:
            subprocess.run(prefix + [args.swiftc, "-frontend", "-parse", swift_path(file)], check=True)
        binary = scratch / "navigation-policy-checks"
        subprocess.run(prefix + [args.swiftc, "-swift-version", "5", "-warnings-as-errors",
            *[swift_path(ROOT / "cleanroom" / name) for name in ["WhitegramPreferences.swift", "WhitegramNavigationPolicy.swift", "WhitegramBackgroundStore.swift"]],
            swift_path(Path(__file__).with_name("WhitegramNavigationTests.swift")), "-o", swift_path(binary)], check=True)
        environment = ["env", "XDG_CONFIG_HOME=" + swift_path(scratch), "XDG_DATA_HOME=" + swift_path(scratch), "HOME=" + swift_path(scratch)]
        subprocess.run(prefix + environment + [swift_path(binary)], check=True)
        subprocess.run(prefix + environment + [swift_path(binary), "--reload"], check=True)
        assert originals == {path: (args.source / path).read_bytes() for path in paths}, "Read-only source changed during checks"
        print(json.dumps({"parsed_swift_files": len(files), "edit_count": len(navigation_edits()), "inventory": inventory,
            "source_sha256": {path: hashlib.sha256(data).hexdigest() for path, data in originals.items()}}, indent=2))


if __name__ == "__main__":
    main()
