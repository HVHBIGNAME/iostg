"""Run Swift policy executable and parse staged UI files using the installed WSL compiler."""
import argparse
from pathlib import Path
import subprocess
import sys
import tempfile

WHITEGRAM = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(WHITEGRAM), str(WHITEGRAM / "tests")]
import remaining_presentation_patches as remaining
from test_appearance_extensions import MemoryRoot
from source_patches import SourcePatches


def linux(path):
    return subprocess.run(["wsl.exe", "--exec", "wslpath", "-a", str(path)], check=True, capture_output=True, text=True).stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--scratch-parent", type=Path, required=True)
    args = parser.parse_args()
    if not args.scratch_parent.is_dir():
        raise ValueError("Scratch parent must already exist")
    scratch = Path(tempfile.mkdtemp(prefix="remaining-presentation-", dir=args.scratch_parent))
    compiler = ["wsl.exe", "--exec", "/opt/swift/usr/bin/swiftc", "-swift-version", "5"]
    tests = WHITEGRAM / "tests/remaining_presentation"
    binary = scratch / "policy-checks"
    subprocess.run(compiler + [linux(WHITEGRAM / "cleanroom/WhitegramRemainingPresentationPolicy.swift"),
                              linux(tests / "PreferencesStub.swift"), linux(tests / "main.swift"), "-o", linux(binary)], check=True)
    subprocess.run(["wsl.exe", "--exec", linux(binary)], check=True)
    library = scratch / "libTelegramCore.so"
    subprocess.run(compiler + ["-emit-library", "-emit-module", "-module-name", "TelegramCore",
                              "-emit-module-path", linux(scratch / "TelegramCore.swiftmodule"),
                              linux(WHITEGRAM / "cleanroom/WhitegramRemainingPresentationPolicy.swift"),
                              linux(tests / "PreferencesStub.swift"), "-o", linux(library)], check=True)
    service_binary = scratch / "badge-service-checks"
    subprocess.run(compiler + ["-I", linux(scratch), "-L", linux(scratch), "-lTelegramCore",
                              "-Xlinker", "-rpath", "-Xlinker", linux(scratch),
                              linux(WHITEGRAM / "cleanroom/WhitegramRemainingBadgeService.swift"),
                              linux(tests / "BadgeServiceStubs.swift"), linux(tests / "service_main.swift"),
                              "-o", linux(service_binary)], check=True)
    subprocess.run(["wsl.exe", "--exec", linux(service_binary)], check=True)
    paths = [remaining.APP, remaining.ROOT, remaining.LIST, remaining.TITLE, remaining.BUBBLE, remaining.ITEMS, remaining.SCREEN]
    originals = {path: (args.source / path).read_bytes() for path in paths}
    root = MemoryRoot({path: value.decode("utf-8") for path, value in originals.items()})
    patches = SourcePatches(root)
    remaining.remaining_presentation_patches(patches)
    parse = [WHITEGRAM / "cleanroom" / name for name in remaining.RUNTIME_FILES]
    for index, (path, text) in enumerate(patches.pending.items()):
        output = scratch / f"staged-{index}-{Path(path).name}"
        output.write_text(text, encoding="utf-8")
        parse.append(output)
    for path in parse:
        subprocess.run(compiler[:3] + ["-frontend", "-parse", "-swift-version", "5", linux(path)], check=True)
    for path, original in originals.items():
        assert (args.source / path).read_bytes() == original, "Reference changed during validation"
    print(f"Swift parse passed for {len(parse)} runtime/staged files. Scratch retained: {scratch}")


if __name__ == "__main__":
    main()
