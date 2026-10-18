#!/bin/bash
# MK-ROUTING-20261011 DEVICE DV-BUILD-01: arm64-v8a JAR assembly.
# Replicates bundle_default.sh steps for the arm64 subset:
#   prefix/arm64-v8a/usr/local/lib/*.so -> temp/lib/arm64-v8a/
#   -> weaken_undefined_imports.py libmpv.so (vkweak, idempotent)
#   -> fixed timestamps -> zip -> default-arm64-v8a.jar
set -euo pipefail

BS=/Users/wuweiwei1/src/mk-device-20261011/libmpv-build/buildscripts
OUT=/Users/wuweiwei1/src/mk-device-20261011/artifacts
cd "$BS"

rm -rf temp "$OUT/default-arm64-v8a.jar"
mkdir -p temp/lib/arm64-v8a "$OUT"
# libmpv.so: fresh mpv build install (prefix/usr/local/lib).
cp prefix/arm64-v8a/usr/local/lib/libmpv.so temp/lib/arm64-v8a/
# libmediakitandroidhelper.so: helper gradle assembleRelease (b768ce102),
# extracted from its release APK — the exact bundle_default.sh step.
cp deps/media-kit-android-helper/app/build/outputs/apk/release/lib/arm64-v8a/libmediakitandroidhelper.so temp/lib/arm64-v8a/
# libc++_shared.so: NDK 27.2.12479018 sysroot copy (byte-identical to the
# reference v2026.013 JAR member: 1794776 bytes; shaderc's APP_STL=c++_shared
# ndk-build emits no .so for its static-only target).
cp "$HOME/Library/Android/sdk/ndk/27.2.12479018/toolchains/llvm/prebuilt/darwin-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so" temp/lib/arm64-v8a/

# vkweak: since mpv c11426b67a the two Vulkan 1.1 imports are resolved via
# vkGetInstanceProcAddr upstream — weakening is a no-op on fresh builds. Run
# it only when the symbols are actually present (same rule as DV001
# bundle_default.sh).
if nm -D --undefined-only temp/lib/arm64-v8a/libmpv.so 2>/dev/null | grep -q "vkGetPhysicalDeviceProperties2"; then
  python3 scripts/weaken_undefined_imports.py temp/lib/arm64-v8a/libmpv.so
else
  echo "DV001: no Vulkan 1.1 imports in fresh libmpv.so; weaken skipped"
fi

FIXED_TIME="2025-01-01 00:00:00"
find temp/lib -type d -exec touch -d "$FIXED_TIME" {} +
find temp/lib/arm64-v8a -type f -name "*.so" -exec touch -d "$FIXED_TIME" {} +

md5sum temp/lib/arm64-v8a/*.so | tee "$OUT/md5-arm64.txt"

(cd temp && find lib/arm64-v8a -type f | sort | zip -r -X "$OUT/default-arm64-v8a.jar" -@)

shasum -a 256 "$OUT/default-arm64-v8a.jar"
