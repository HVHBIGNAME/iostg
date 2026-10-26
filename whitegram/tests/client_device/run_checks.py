"""Compile production policies and deferred consumer with typed native-boundary fixtures."""
from pathlib import Path
import argparse
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def wsl_path(path):
    value = path.resolve().as_posix()
    return '/mnt/' + value[0].lower() + value[2:]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scratch-parent', required=True, type=Path)
    parser.add_argument('--source', required=True, type=Path)
    args = parser.parse_args()
    if not args.scratch_parent.is_dir() or not args.source.is_dir(): parser.error('directories must exist')
    with tempfile.TemporaryDirectory(prefix='whitegram-device-', dir=args.scratch_parent) as temporary:
        scratch = Path(temporary)
        swift = ['wsl', '--', '/opt/swift/usr/bin/swiftc']
        for module, filename in [('Postbox', 'PostboxFixture.swift'), ('SwiftSignalKit', 'SignalFixture.swift')]:
            subprocess.run(swift + ['-emit-module', '-emit-library', '-module-name', module, wsl_path(HERE / filename), '-emit-module-path', wsl_path(scratch / (module + '.swiftmodule')), '-o', wsl_path(scratch / ('lib' + module + '.so'))], check=True)
        policies = ['WhitegramPreferences.swift', 'WhitegramMediaSettings.swift', 'WhitegramDeviceSettings.swift', 'WhitegramDeviceDeferredMessages.swift']
        executable = scratch / 'device-checks'
        subprocess.run(swift + ['-swift-version', '5', '-warnings-as-errors', '-I', wsl_path(scratch), '-L', wsl_path(scratch), '-lPostbox', '-lSwiftSignalKit',
            *[wsl_path(ROOT / 'cleanroom' / name) for name in policies], wsl_path(HERE / 'BoundaryFixture.swift'), wsl_path(HERE / 'WhitegramDeviceTests.swift'), '-o', wsl_path(executable)], check=True)
        subprocess.run(['wsl', '--', 'env', 'LD_LIBRARY_PATH=' + wsl_path(scratch), 'XDG_CONFIG_HOME=' + wsl_path(scratch), wsl_path(executable)], check=True)
        import sys
        sys.path.insert(0, str(ROOT))
        from source_patches import SourcePatches
        from media_camera_patches import media_camera_patches
        from client_device_patches import client_device_patches, DEVICE_RUNTIME_FILES
        patches = SourcePatches(args.source)
        media_camera_patches(patches)
        client_device_patches(patches)
        sources = {Path(path).name: text for path, text in patches.pending.items() if path.endswith('.swift')}
        sources.update({name: (ROOT / 'cleanroom' / name).read_text(encoding='utf8') for name in DEVICE_RUNTIME_FILES})
        for name, text in sources.items():
            path = scratch / name
            path.write_text(text, encoding='utf8')
            subprocess.run(swift + ['-frontend', '-parse', wsl_path(path)], check=True)
        print(f'Swift parser accepted {len(sources)} runtime and patched Swift files; original source stayed read-only.')


if __name__ == '__main__': main()
