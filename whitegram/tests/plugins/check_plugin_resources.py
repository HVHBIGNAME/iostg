"""Exercise the real resource installer in fresh temporary source trees."""

import hashlib
from pathlib import Path
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from plugin_resources import SDK_FILES, install_plugin_resources


def main() -> None:
    overlay = Path(__file__).resolve().parents[2]
    source = overlay / "cleanroom" / "pluginsdk"
    adapter = source / "whitegram-typescript-transpiler.js"
    assert hashlib.sha256(adapter.read_bytes()).hexdigest() == "e40a1db5fd258fcddb33a7d2831f2baf6afa6116a24a79998aa913b3184696f2"
    with tempfile.TemporaryDirectory(prefix="whitegram-resources-") as directory:
        root = Path(directory)
        telegram = root / "Telegram"
        telegram.mkdir()
        (telegram / "BUILD").write_text('''load("@bazel_skylib//rules:common_settings.bzl", "string_flag")
ios_application(
    name = "Telegram",
    resources = [
        ":LaunchScreen",
    ],
)
''', encoding="utf-8")
        install_plugin_resources(root, overlay)
        once = (telegram / "BUILD").read_bytes()
        install_plugin_resources(root, overlay)
        assert (telegram / "BUILD").read_bytes() == once
        for name in SDK_FILES:
            assert (telegram / "WhitegramPluginSDK" / name).read_bytes() == (source / name).read_bytes()
            assert once.count(f'"WhitegramPluginSDK/{name}"'.encode()) == 1
        assert once.count(b'name = "WhitegramPluginSDK"') == 1
        assert b"whitegram-sdk-hooks.js" not in once
        assert (b"typescript-compiler.js" in once) == (source / "typescript-compiler.js").is_file(), "Compiler registration must reflect its actual asset"
    print(f"PASS {len(SDK_FILES)} exact SDK resources, original TS adapter hash, resource rule and idempotent installer; absent compiler stays absent")


if __name__ == "__main__":
    main()
