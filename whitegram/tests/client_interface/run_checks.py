"""Copy just owned hooks to a scratch tree, replay, parse Swift, and execute policies."""

import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from client_interface_patches import CLIENT_INTERFACE_RUNTIME_FILES, apply_client_interface_patches, client_interface_edits


def wsl_path(path):
    value = path.resolve().as_posix()
    return "/mnt/" + value[0].lower() + value[2:]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--scratch-parent", required=True, type=Path)
    args = parser.parse_args()
    if not args.source.is_dir() or not args.scratch_parent.is_dir():
        parser.error("source and scratch parent must exist")
    with tempfile.TemporaryDirectory(prefix="client-interface-swift-", dir=args.scratch_parent) as temporary:
        scratch = Path(temporary)
        for relative in sorted({edit.path for edit in client_interface_edits()}):
            destination = scratch / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(args.source / relative, destination)
        inventory = apply_client_interface_patches(scratch)
        assert apply_client_interface_patches(scratch) == inventory
        for name, relative in CLIENT_INTERFACE_RUNTIME_FILES.items():
            destination = scratch / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / "cleanroom" / name, destination)
        swift_files = sorted(scratch.rglob("*.swift"))
        for path in swift_files:
            subprocess.run(["wsl", "--", "/opt/swift/usr/bin/swiftc", "-frontend", "-parse", wsl_path(path)], check=True)
        policies = ["WhitegramClientInterfacePolicy.swift", "WhitegramLocalPremiumPolicy.swift", "WhitegramAccountStripOrder.swift"]
        executable = scratch / "policy-checks"
        subprocess.run(["wsl", "--", "/opt/swift/usr/bin/swiftc", "-warnings-as-errors", *[wsl_path(ROOT / "cleanroom" / name) for name in policies],
                        wsl_path(Path(__file__).with_name("WhitegramClientInterfaceTests.swift")), "-o", wsl_path(executable)], check=True)
        subprocess.run(["wsl", "--", wsl_path(executable)], check=True)
        fixtures = Path(__file__).parent
        subprocess.run(["wsl", "--", "/opt/swift/usr/bin/swiftc", "-emit-module", "-emit-library", "-module-name", "Postbox",
                        wsl_path(fixtures / "PostboxFixture.swift"), "-emit-module-path", wsl_path(scratch / "Postbox.swiftmodule"),
                        "-o", wsl_path(scratch / "libPostbox.so")], check=True)
        premium = scratch / "premium-checks"
        subprocess.run(["wsl", "--", "/opt/swift/usr/bin/swiftc", "-swift-version", "5", "-warnings-as-errors",
                        "-I", wsl_path(scratch), "-L", wsl_path(scratch), "-lPostbox",
                        wsl_path(ROOT / "cleanroom" / "WhitegramPreferences.swift"),
                        wsl_path(ROOT / "cleanroom" / "WhitegramLocalPremiumPolicy.swift"),
                        wsl_path(ROOT / "cleanroom" / "WhitegramLocalPremiumPresentation.swift"),
                        wsl_path(fixtures / "PremiumPeerFixture.swift"), wsl_path(fixtures / "WhitegramLocalPremiumTests.swift"),
                        "-o", wsl_path(premium)], check=True)
        subprocess.run(["wsl", "--", "env", "LD_LIBRARY_PATH=" + wsl_path(scratch), "XDG_CONFIG_HOME=" + wsl_path(scratch),
                        wsl_path(premium)], check=True)
        print(f"Parsed {len(swift_files)} Swift files; exact source replay passed.")


if __name__ == "__main__":
    main()
