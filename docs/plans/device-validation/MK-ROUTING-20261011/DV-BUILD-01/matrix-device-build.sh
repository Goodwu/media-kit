#!/usr/bin/env bash
# MK-ROUTING-20261011 DEVICE: lab matrix builds (LG P5/P8.4 × gate open/closed),
# mirroring media-kit tool/matrix-build.sh base defines + local JAR injection.
set -Eeuo pipefail
cd /Users/wuweiwei1/src/mk-device-20261011/media-kit/media_kit_hdr_lab
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export ORG_GRADLE_PROJECT_mediaKitLocalArm64Jar=/Users/wuweiwei1/src/mk-device-20261011/artifacts/default-arm64-v8a.jar
export ORG_GRADLE_PROJECT_mediaKitArm64Only=true

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

build() {
  local tag=$1 src=$2; shift 2
  local -a extra=("$@")
  echo "=== building $tag ==="
  flutter build apk --release --target-platform android-arm64 \
    "${base_defines[@]}" \
    "--dart-define=MEDIA_KIT_ANDROID_LOCAL_SOURCE=$src" \
    "${extra[@]}" || { echo "BUILD_FAILED $tag"; return 1; }
  cp build/app/outputs/flutter-apk/app-release.apk "/Users/wuweiwei1/src/mk-device-20261011/artifacts/matrix-$tag.apk"
  rm -rf build/.gradle build/app/intermediates build/app/tmp
  shasum -a 256 "/Users/wuweiwei1/src/mk-device-20261011/artifacts/matrix-$tag.apk"
}

build p5-hdr-F  /data/local/tmp/mk-dv-p5.mp4 \
  --dart-define=MEDIA_KIT_ANDROID_PLATFORM_VIEW=true \
  --dart-define=MEDIA_KIT_ANDROID_GPU_PLATFORM_HDR=true
build p5-hdr-G  /data/local/tmp/mk-dv-p5.mp4 \
  --dart-define=MEDIA_KIT_ANDROID_PLATFORM_VIEW=true \
  --dart-define=MEDIA_KIT_ANDROID_GPU_PLATFORM_HDR=true \
  --dart-define=MEDIA_KIT_ANDROID_HDR_GATE_OPEN=true
build p84-hdr-F /data/local/tmp/mk-dv-p84.mp4 \
  --dart-define=MEDIA_KIT_ANDROID_PLATFORM_VIEW=true
build p84-hdr-G /data/local/tmp/mk-dv-p84.mp4 \
  --dart-define=MEDIA_KIT_ANDROID_PLATFORM_VIEW=true \
  --dart-define=MEDIA_KIT_ANDROID_HDR_GATE_OPEN=true
build hdr10-hdr-F /data/local/tmp/mk-hdr10-pq.mp4 \
  --dart-define=MEDIA_KIT_ANDROID_PLATFORM_VIEW=true
build hlg-hdr-F /data/local/tmp/mk-hlg.mp4 \
  --dart-define=MEDIA_KIT_ANDROID_PLATFORM_VIEW=true
echo "ALL_BUILDS_DONE"
