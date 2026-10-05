#!/usr/bin/env python3
"""Compile the optimized macOS bridge and run its ABI/epoch/lease tests.

Requires a directory containing FlutterMacOS.framework and Mpv.framework.
This does not verify video pixels, playback performance or display acceptance.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("framework_directory", type=Path)
    args = parser.parse_args()
    framework_directory = args.framework_directory.resolve()
    for name in ("FlutterMacOS", "Mpv"):
        if not (framework_directory / f"{name}.framework").is_dir():
            parser.error(f"Missing {name}.framework in {framework_directory}")
    root = Path(__file__).resolve().parents[1]
    plugin = root / "media_kit_video/macos/media_kit_video/Sources/media_kit_video/plugin"
    common = root / "media_kit_video/common/darwin/Classes/plugin"
    with tempfile.TemporaryDirectory(prefix="media-kit-shared-bridge-") as temporary:
        subprocess.run([
            "xcrun", "swiftc", "-emit-object", "-O", "-whole-module-optimization",
            "-parse-as-library", "-D", "SWIFT_PACKAGE",
            "-target", "arm64-apple-macos12.0", "-F", str(framework_directory),
            *map(str, sorted(plugin.rglob("*.swift"))),
            "-o", str(Path(temporary) / "bridge.o"),
        ], check=True)
        binary = Path(temporary) / "bridge-test"
        subprocess.run([
            "xcrun", "swiftc", str(plugin / "GpuNextRenderABI.swift"),
            str(common / "NativeFrameRegistry.swift"),
            str(common / "SwappableObjectManager.swift"),
            str(root / "media_kit_video/test/native/shared_render_bridge_test.swift"),
            "-o", str(binary),
        ], check=True)
        subprocess.run([str(binary)], check=True)


if __name__ == "__main__":
    main()
