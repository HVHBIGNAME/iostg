"""Run WSL Swift checks; write only a new artifacts directory beside this script."""

import argparse
import hashlib
from pathlib import Path
import subprocess
import sys
import uuid

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
OVERLAY = HERE.parents[1]
sys.path.insert(0, str(OVERLAY))
from source_patches import SourcePatches
from visual_effects_patches import RUNTIME_FILES, visual_effects_patches, visual_effects_edits


def wsl(path):
    value = path.resolve().as_posix()
    return "/mnt/" + value[0].lower() + value[2:]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    args = parser.parse_args()
    if not args.source.is_dir():
        parser.error("source directory must exist")
    # Stage through SourcePatches.read/pending only; never call write on the reference.
    patches = SourcePatches(args.source)
    visual_effects_patches(patches)
    paths = sorted({edit.path for edit in visual_effects_edits()})
    original_hashes = {path: hashlib.sha256((args.source / path).read_bytes()).hexdigest() for path in paths}
    output = HERE / ("artifacts-" + uuid.uuid4().hex[:10])
    output.mkdir()
    sources = dict(patches.pending)
    sources.update({destination: (OVERLAY / "cleanroom" / name).read_text(encoding="utf-8") for name, destination in RUNTIME_FILES.items()})
    swift = ["wsl", "--", "/opt/swift/usr/bin/swiftc"]
    for relative, text in sources.items():
        path = output / Path(relative).name
        path.write_text(text, encoding="utf-8")
        subprocess.run(swift + ["-frontend", "-parse", wsl(path)], check=True)
    executable = output / "policy-tests"
    subprocess.run(swift + ["-swift-version", "5", "-warnings-as-errors", "-module-cache-path", wsl(output / "module-cache"),
                           wsl(OVERLAY / "cleanroom/WhitegramVisualPolicy.swift"), wsl(HERE / "PolicyTests.swift"), "-o", wsl(executable)], check=True)
    subprocess.run(["wsl", "--", wsl(executable)], check=True)
    common = ["-swift-version", "5", "-warnings-as-errors", "-module-cache-path", wsl(output / "module-cache")]
    for module, files in {
        "UIKit": [HERE / "UIKitMotionFixture.swift"],
        "TelegramCore": [OVERLAY / "cleanroom/WhitegramVisualPolicy.swift", HERE / "PreferencesFixture.swift"],
    }.items():
        subprocess.run(swift + common + ["-emit-module", "-emit-library", "-module-name", module, *map(wsl, files),
                                        "-emit-module-path", wsl(output / (module + ".swiftmodule")), "-o", wsl(output / ("lib" + module + ".so"))], check=True)
    motion = output / "motion-tests"
    subprocess.run(swift + common + ["-I", wsl(output), "-L", wsl(output), "-lUIKit", "-lTelegramCore",
        *[wsl(OVERLAY / "cleanroom" / name) for name in ("WhitegramVisualEnvironment.swift", "WhitegramVisualScroll.swift", "WhitegramVisualFisheye.swift")],
        wsl(HERE / "MotionLifecycleTests.swift"), "-o", wsl(motion)], check=True)
    subprocess.run(["wsl", "--", "env", "LD_LIBRARY_PATH=" + wsl(output), "XDG_CONFIG_HOME=" + wsl(output), wsl(motion)], check=True)
    surfaces = output / "surface-tests"
    subprocess.run(swift + common + ["-I", wsl(output), "-L", wsl(output), "-lUIKit", "-lTelegramCore",
        *[wsl(OVERLAY / "cleanroom" / name) for name in ("WhitegramVisualEnvironment.swift", "WhitegramVisualBackdrop.swift", "WhitegramVisualProfile.swift", "WhitegramVisualParticles.swift")],
        wsl(HERE / "SurfaceLifecycleTests.swift"), "-o", wsl(surfaces)], check=True)
    subprocess.run(["wsl", "--", "env", "LD_LIBRARY_PATH=" + wsl(output), "XDG_CONFIG_HOME=" + wsl(output), wsl(surfaces)], check=True)
    for path, digest in original_hashes.items():
        if hashlib.sha256((args.source / path).read_bytes()).hexdigest() != digest:
            raise RuntimeError(f"Reference changed during verification: {path}")
    print(f"Parsed {len(sources)} Swift files; policies executed; {len(paths)} read-only source digests unchanged. Artifacts: {output}")


if __name__ == "__main__":
    main()
