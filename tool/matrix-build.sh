#!/usr/bin/env bash
# 三仓库归一后播放矩阵构建：P5/HDR10/P8.4 × SDR/HDR 六包
# 基础 define 集 = 12632（去起播偏移），HDR 轮加 PLATFORM_VIEW（P5 PQ 另加 GPU_PLATFORM_HDR）
set -Eeuo pipefail
cd /Users/wuweiwei1/src/media-kit/media_kit_test
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export ORG_GRADLE_PROJECT_mediaKitLocalArm64Jar=/tmp/media-kit-p5-colorfix-398d0c3-arm64.jar

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
    "${extra[@]}" > "/tmp/matrix-build-$tag.log" 2>&1
  cp build/app/outputs/flutter-apk/app-release.apk "/tmp/matrix-$tag.apk"
  shasum -a 256 "/tmp/matrix-$tag.apk"
}

build p5-sdr-12703  /data/local/tmp/media-kit-p5-mystery-box.mp4
build p5-pq-12704   /data/local/tmp/media-kit-p5-mystery-box.mp4 \
  --dart-define=MEDIA_KIT_ANDROID_PLATFORM_VIEW=true \
  --dart-define=MEDIA_KIT_ANDROID_GPU_PLATFORM_HDR=true
build hdr10-sdr-12705 /data/local/tmp/media-kit-hdr10-full.mp4
build hdr10-hdr-12706 /data/local/tmp/media-kit-hdr10-full.mp4 \
  --dart-define=MEDIA_KIT_ANDROID_PLATFORM_VIEW=true
build p84-sdr-12707  /data/local/tmp/media-kit-p84-full.mp4
build p84-hdr-12708  /data/local/tmp/media-kit-p84-full.mp4 \
  --dart-define=MEDIA_KIT_ANDROID_PLATFORM_VIEW=true
echo "ALL_BUILDS_DONE"
