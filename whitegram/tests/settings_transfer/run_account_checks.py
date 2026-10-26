"""Compile the real Foundation preference/archive code and exercise account transitions."""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
SOURCES = (
    "WhitegramPreferences.swift", "WhitegramSettingsArchive.swift", "WhitegramSettingsArchiveJSON.swift",
    "WhitegramSettingsArchiveSchema.swift", "WhitegramSettingsArchiveMirrors.swift", "WhitegramSettingsArchiveStore.swift",
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scratch-parent", required=True, type=Path)
    parser.add_argument("--assembled-source", type=Path)
    args = parser.parse_args()
    if not args.scratch_parent.is_dir():
        parser.error("scratch parent must exist")
    with tempfile.TemporaryDirectory(prefix="account-settings-", dir=args.scratch_parent) as directory:
        scratch = Path(directory)
        def native(path):
            text = path.resolve().as_posix()
            return "/mnt/" + text[0].lower() + text[2:] if sys.platform == "win32" else text
        prefix = ["wsl", "--"] if sys.platform == "win32" else []
        swift = "/opt/swift/usr/bin/swiftc" if sys.platform == "win32" else "swiftc"
        executable = scratch / "account-settings-checks"
        subprocess.run(prefix + [swift, "-swift-version", "5", "-warnings-as-errors",
            *[native(ROOT / "cleanroom" / name) for name in SOURCES],
            native(HERE / "WhitegramAccountSettingsChecks.swift"), "-o", native(executable)], check=True)
        subprocess.run(prefix + ["env", "XDG_CONFIG_HOME=" + native(scratch), native(executable)], check=True)
        subprocess.run(prefix + ["env", "XDG_CONFIG_HOME=" + native(scratch), native(executable), "--resume"], check=True)
        subprocess.run(prefix + ["env", "XDG_CONFIG_HOME=" + native(scratch / "legacy-config"), native(executable), "--legacy"], check=True)
        if args.assembled_source:
            package = scratch / "foundation"
            package.mkdir()
            (package / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "SettingsFoundationChecks", targets: [
    .target(name: "TelegramCore"),
    .target(name: "TelegramUIPreferences", dependencies: ["TelegramCore"]),
    .testTarget(name: "SettingsTests", dependencies: ["TelegramCore", "TelegramUIPreferences"])
])
''', encoding="utf-8")
            core = package / "Sources/TelegramCore"
            core.mkdir(parents=True)
            for name in SOURCES + ("WhitegramMediaSettings.swift",):
                shutil.copyfile(ROOT / "cleanroom" / name, core / name)
            shutil.copyfile(ROOT / "generated/WhitegramSettingsState.swift", core / "WhitegramSettingsState.swift")
            public = package / "Sources/TelegramUIPreferences"
            public.mkdir(parents=True)
            for name in ("WhiteGramChatSettings.swift", "WhiteGramTabSettings.swift", "WhiteGramStorySettings.swift",
                         "WhiteGramChatFolderSettings.swift", "WhiteGramContextMenuSettings.swift", "WhiteGramOtherSettings.swift", "WhitegramForkBridge.swift"):
                shutil.copyfile(args.assembled_source / "submodules/TelegramUIPreferences/Sources" / name, public / name)
            tests = package / "Tests/SettingsTests"
            tests.mkdir(parents=True)
            for name in ("WhitegramSettingsArchiveTests.swift", "WhitegramSettingsTransferStoreTests.swift"):
                shutil.copyfile(HERE / name, tests / name)
            swift_driver = "/opt/swift/usr/bin/swift" if sys.platform == "win32" else "swift"
            environment = os.environ.copy()
            environment["XDG_CONFIG_HOME"] = native(scratch / "test-config")
            try:
                subprocess.run(prefix + ["env", "XDG_CONFIG_HOME=" + environment["XDG_CONFIG_HOME"], swift_driver,
                    "test", "--package-path", native(package)], check=True, env=environment)
            finally:
                if sys.platform == "win32":
                    subprocess.run(["wsl", "--", "rm", "-rf", "--", native(package / ".build")], check=True)


if __name__ == "__main__":
    main()
