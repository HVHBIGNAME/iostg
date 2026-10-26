"""Read-only source composition, Swift parse and executable Foundation policies."""
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
from source_patches import SourcePatches
from navigation_patches import navigation_patches, navigation_edits, RUNTIME_FILES as NAVIGATION_FILES
from feed_classic_patches import feed_classic_patches, feed_classic_edits, RUNTIME_FILES


def wsl(path):
    value = path.resolve().as_posix()
    return "/mnt/" + value[0].lower() + value[2:]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--scratch-parent", required=True, type=Path)
    args = parser.parse_args()
    if not args.source.is_dir() or not args.scratch_parent.is_dir(): parser.error("Both directories must exist")
    paths = {edit.path for edit in (*navigation_edits(), *feed_classic_edits())}
    original = {path: (args.source / path).read_bytes() for path in paths}
    with tempfile.TemporaryDirectory(prefix="feed-classic-swift-", dir=args.scratch_parent) as temporary:
        scratch = Path(temporary)
        for relative, data in original.items():
            target = scratch / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        patches = SourcePatches(scratch)
        navigation_patches(patches)
        feed_classic_patches(patches)
        pending = dict(patches.pending)
        navigation_patches(patches)
        feed_classic_patches(patches)
        assert patches.pending == pending
        report = patches.write()
        for name, relative in {**NAVIGATION_FILES, **RUNTIME_FILES}.items():
            target = scratch / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / "cleanroom" / name, target)
        files = sorted(scratch.rglob("*.swift"))
        for file in files:
            subprocess.run(["wsl", "--", "/opt/swift/usr/bin/swiftc", "-frontend", "-parse", wsl(file)], check=True)
        executable = scratch / "feed-classic-checks"
        subprocess.run(["wsl", "--", "/opt/swift/usr/bin/swiftc", "-swift-version", "5", "-warnings-as-errors",
            wsl(ROOT / "cleanroom/WhitegramFeedMerge.swift"), wsl(ROOT / "cleanroom/WhitegramClassicStyle.swift"),
            wsl(Path(__file__).with_name("PolicyTests.swift")), "-o", wsl(executable)], check=True)
        subprocess.run(["wsl", "--", wsl(executable)], check=True)
        compiler = ["wsl", "--", "/opt/swift/usr/bin/swiftc", "-swift-version", "5", "-warnings-as-errors"]
        for module, source in (("Display", "WhitegramClassicStyle.swift"), ("TelegramCore", "WhitegramPreferences.swift")):
            subprocess.run(compiler + ["-emit-module", "-emit-library", "-module-name", module,
                wsl(ROOT / "cleanroom" / source), "-emit-module-path", wsl(scratch / (module + ".swiftmodule")),
                "-o", wsl(scratch / ("lib" + module + ".so"))], check=True)
        profileExecutable = scratch / "classic-profiles"
        subprocess.run(compiler + ["-I", wsl(scratch), "-L", wsl(scratch), "-lDisplay", "-lTelegramCore",
            wsl(ROOT / "cleanroom/WhitegramClassicSettings.swift"), wsl(Path(__file__).with_name("ClassicProfiles.swift")),
            "-o", wsl(profileExecutable)], check=True)
        subprocess.run(["wsl", "--", "env", "LD_LIBRARY_PATH=" + wsl(scratch), "XDG_CONFIG_HOME=" + wsl(scratch),
            "HOME=" + wsl(scratch), wsl(profileExecutable)], check=True)
        assert original == {path: (args.source / path).read_bytes() for path in paths}
        print(json.dumps({"swift_parsed": len(files), "new_edits": len(feed_classic_edits()), "composed_features": sorted(report),
            "reference_sha256": {path: hashlib.sha256(data).hexdigest() for path, data in sorted(original.items())}}, indent=2))


if __name__ == "__main__": main()
