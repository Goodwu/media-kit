#!/usr/bin/env bash
# S1/S2/S4 实机探针构建（hdr-auto-output 计划第二轮）：事实轮 Texture SDR，
# p5 综合轮走 12704 已验证组合 + SURFACE_TRANSFER=pq，负向轮注入上游非 fork JAR，
# 无扩展轮用 -P hdrLabUnregisterVendorExt=true。
# usage: hdr-auto-probe-build.sh <tag> <device_sample_path> [extra --dart-define ...]
set -Eeuo pipefail
cd "$(dirname "$0")/../media_kit_hdr_lab"
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
if [[ -n "${ORG_GRADLE_PROJECT_mediaKitLocalArm64Jar:-}" ]]; then
  export ORG_GRADLE_PROJECT_mediaKitLocalArm64Jar
fi

tag=$1; src=$2; shift 2

base_defines=(
  --dart-define=MEDIA_KIT_AUTO_SINGLE_PLAYER=true
  --dart-define=MEDIA_KIT_ANDROID_OPEN_ON_TAP=true
  --dart-define=MEDIA_KIT_ANDROID_PREOPEN_FULLSCREEN=true
  --dart-define=MEDIA_KIT_ANDROID_NAMED_LOCAL_SOURCE=true
  --dart-define=MEDIA_KIT_ANDROID_P5_RPU_PIPELINE_BUILT=true
  --dart-define=MEDIA_KIT_ANDROID_HDR_TRANSACTION=true
  --dart-define=MEDIA_KIT_ANDROID_SURFACE_PRODUCER=false
  --dart-define=MEDIA_KIT_ANDROID_TEXTURE_LAYOUT_SIZE=true
  --dart-define=MEDIA_KIT_ANDROID_PERF_PROBE=true
  --dart-define=MEDIA_KIT_ANDROID_P5_COUNTER_PROBE=true
  --dart-define=MEDIA_KIT_ANDROID_DIRECT_OPEN_TRACE=true
)

echo "=== building hdr-auto-$tag ==="
flutter build apk --release --target-platform android-arm64 \
  "${base_defines[@]}" \
  "--dart-define=MEDIA_KIT_ANDROID_LOCAL_SOURCE=$src" \
  "$@" > "/tmp/hdr-auto-build-$tag.log" 2>&1
cp build/app/outputs/flutter-apk/app-release.apk "/tmp/hdr-auto-$tag.apk"
shasum -a 256 "/tmp/hdr-auto-$tag.apk"
