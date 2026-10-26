"""Stage into an isolated scratch copy, parse hooks and compile/run Foundation policies."""

import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from local_pins_patches import RUNTIME_FILES, apply_local_pins_patches, local_pins_edits


def wsl_path(path):
    text = path.resolve().as_posix()
    return "/mnt/" + text[0].lower() + text[2:]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--scratch-parent", type=Path, required=True)
    args = parser.parse_args()
    if not args.source.is_dir() or not args.scratch_parent.is_dir():
        parser.error("source and scratch parent must exist")
    with tempfile.TemporaryDirectory(prefix="local-pins-swift-", dir=args.scratch_parent) as temporary:
        scratch = Path(temporary)
        for relative in sorted({edit.path for edit in local_pins_edits()}):
            destination = scratch / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(args.source / relative, destination)
        inventory = apply_local_pins_patches(scratch)
        assert apply_local_pins_patches(scratch) == inventory
        for basename, relative in RUNTIME_FILES.items():
            destination = scratch / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / "cleanroom" / basename, destination)
        files = sorted(scratch.rglob("*.swift"))
        for path in files:
            subprocess.run(["wsl", "--", "/opt/swift/usr/bin/swiftc", "-frontend", "-parse", wsl_path(path)], check=True)
        executable = scratch / "policy-checks"
        subprocess.run(["wsl", "--", "/opt/swift/usr/bin/swiftc", "-swift-version", "5", "-warnings-as-errors",
                        wsl_path(ROOT / "cleanroom" / "WhitegramLocalPinPolicy.swift"),
                        wsl_path(Path(__file__).with_name("WhitegramLocalPinTests.swift")), "-o", wsl_path(executable)], check=True)
        subprocess.run(["wsl", "--", wsl_path(executable)], check=True)
        fixtures = Path(__file__).parent
        modules = [
            ("SwiftSignalKit", [fixtures / "SignalFixture.swift"], []),
            ("Postbox", [fixtures / "PostboxFixture.swift"], ["SwiftSignalKit"]),
            ("TelegramCore", [fixtures / "CoreFixture.swift", ROOT / "cleanroom" / "WhitegramPreferences.swift",
                              ROOT / "cleanroom" / "WhitegramLocalPinPolicy.swift", ROOT / "cleanroom" / "WhitegramLocalPinRuntime.swift"], ["Postbox", "SwiftSignalKit"]),
            ("AccountContext", [fixtures / "AccountContextFixture.swift"], ["TelegramCore", "Postbox", "SwiftSignalKit"]),
        ]
        flags = ["wsl", "--", "/opt/swift/usr/bin/swiftc", "-swift-version", "5", "-warnings-as-errors", "-I", wsl_path(scratch), "-L", wsl_path(scratch)]
        for name, sources, dependencies in modules:
            subprocess.run([*flags, "-emit-module", "-emit-library", "-module-name", name,
                            *[wsl_path(path) for path in sources], *["-l" + dependency for dependency in dependencies],
                            "-emit-module-path", wsl_path(scratch / (name + ".swiftmodule")),
                            "-o", wsl_path(scratch / ("lib" + name + ".so"))], check=True)
        runtime = scratch / "runtime-checks"
        consumer = scratch / "ChatListConsumer.swift"
        source = (scratch / "submodules/ChatListUI/Sources/Node/ChatListNode.swift").read_text(encoding="utf-8")
        anchor = "        |> mapToSignal { listLocation -> Signal<(ChatListNodeViewUpdate, ChatListFilter?), NoError> in\n"
        body = anchor + source.split(anchor, 1)[1].split("        let previousState", 1)[0]
        consumer.write_text('''import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext
enum LocalPinConsumerMode { case chatList, peers }
private struct LocalPinConsumerContext { let account: Account }
func localPinConsumer(account: Account, mode: LocalPinConsumerMode, listLocation: ChatListNodeLocation) -> Signal<(ChatListNodeViewUpdate, ChatListFilter?), NoError> {
    let context = LocalPinConsumerContext(account: account)
    let location = ChatListControllerLocation.chatList(.root)
    let shouldLoadCanMessagePeer = false
    return Signal<ChatListNodeLocation, NoError>.single(listLocation)
''' + body + "}\n", encoding="utf-8")
        subprocess.run([*flags, *["-l" + name for name, _, _ in modules],
                        wsl_path(consumer),
                        wsl_path(ROOT / "cleanroom" / "WhitegramLocalPinList.swift"),
                        wsl_path(fixtures / "ListFixture.swift"), wsl_path(fixtures / "WhitegramLocalPinRuntimeTests.swift"),
                        "-o", wsl_path(runtime)], check=True)
        subprocess.run(["wsl", "--", "env", "LD_LIBRARY_PATH=" + wsl_path(scratch), "XDG_CONFIG_HOME=" + wsl_path(scratch), wsl_path(runtime)], check=True)
        print(f"Parsed {len(files)} Swift files; exact replay passed.")


if __name__ == "__main__":
    main()
