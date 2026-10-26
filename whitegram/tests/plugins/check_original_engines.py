"""Verify recovered language glue against the selected Beta 3.2 IPA, offline."""

import argparse
import hashlib
from pathlib import Path
import zipfile


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("embedded_source", type=Path)
    args = parser.parse_args()
    with args.ipa.open("rb") as file:
        digest = hashlib.file_digest(file, "sha256").hexdigest()
    assert digest == "5cf287812de7707dd21256281e645c29a9a5c0da3f66910746254842fce5ffbf", "Wrong original artifact"
    print("PASS original Beta 3.2 SHA-256:", digest)
    with zipfile.ZipFile(args.ipa) as archive:
        names = archive.namelist()
        candidates = [name for name in names if name.lower().endswith((".wasm", "runtime.json")) or any(key in name.lower() for key in ("typescript", "pyodide", "wasmoon", "fengari", "yaegi"))]
        print("Named compiler / interpreter archive member candidates:", candidates)
        binary = archive.read("Payload/Telegram.app/Frameworks/TelegramUIFramework.framework/TelegramUIFramework")
        for name in (
            "typescript-transpiler-e40a1db5fd25.js", "language-common-ccacfab1fc7e.js", "languages-host-3f64d058ce3f.html",
            "lua-worker-a9dfab876b6f.js", "ruby-worker-6b4f16f621a2.js", "go-worker-3ae18756c888.js",
        ):
            data = (args.embedded_source / name).read_bytes()
            assert data in binary, f"Recovered source does not match original embedded bytes: {name}"
            print("PASS exact embedded source:", name, hashlib.sha256(data).hexdigest())
    print("Worker/adapter presence is established; interpreter execution and external runtime downloads are not established by this check.")


if __name__ == "__main__":
    main()
