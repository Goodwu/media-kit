#!/usr/bin/env bash
# 测试版默认构建入口：从最新源码构建 libmpv JAR，再构建 Android 测试 APK。
#
# 这是测试链的正向打包路径（非 hack）：
#   1. ninja 增量编译 ~/src/mpv（media-kit/android 分支 HEAD，含未推送提交）；
#   2. build-mks-r1.py 按历史链接配方 + genbump token 重指做最终链接，
#      strip 后换装入 r22 钉定基础 JAR（helper 库保持钉定），产出带
#      native-candidate.json 溯源的 media-kit-mks-r1.jar；
#   3. flutter build，经 gradle 内建的 ORG_GRADLE_PROJECT_mediaKitLocalArm64Jar
#      属性（build.gradle 正式支持的本地 JAR 验证通道）采用该 JAR。
#
# 发布构建不走本脚本：gradle 默认下载钉定发布 JAR + SHA-256 核验（发布链）。
#
# usage: build-android-test.sh [--debug] [--tag <name>] [--platform-view]
#                              --local-source <device-path> [-- 额外 --dart-define ...]
set -Eeuo pipefail
cd "$(dirname "$0")/.."

variant=release
tag=test-latest
platform_view=false
local_source=
extra=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) variant=debug; shift;;
    --tag) tag=$2; shift 2;;
    --platform-view) platform_view=true; shift;;
    --local-source) local_source=$2; shift 2;;
    --) shift; extra+=("$@"); break;;
    *) extra+=("$1"); shift;;
  esac
done
[[ -n "$local_source" ]] || { echo "need --local-source <device-path>" >&2; exit 2; }

export PATH="/Users/wuweiwei1/Library/Android/sdk/ndk/27.2.12479018/toolchains/llvm/prebuilt/darwin-x86_64/bin:$PATH"
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home

echo "=== [1/3] ninja sync ~/src/mpv _build-arm64-mks ==="
ninja -C ~/src/mpv/_build-arm64-mks

echo "=== [2/3] build-mks-r1 pipeline (JAR from latest sources) ==="
MKS_LABEL="$tag" MKS_SKIP_APK=1 python3 \
  ~/src/media-kit-build/lg-api24/lg-api24-realtime-gpu-phase0-20261008/build-mks-r1.py
jar="$HOME/src/media-kit-build/lg-api24/lg-api24-realtime-gpu-mks-$tag-build/media-kit-mks-r1.jar"
[[ -f "$jar" ]] || { echo "JAR missing: $jar" >&2; exit 1; }
shasum -a 256 "$jar"

echo "=== [3/3] flutter build apk ($variant, local JAR) ==="
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
[[ -n "$local_source" ]] && base_defines+=("--dart-define=MEDIA_KIT_ANDROID_LOCAL_SOURCE=$local_source")
$platform_view && base_defines+=("--dart-define=MEDIA_KIT_ANDROID_PLATFORM_VIEW=true")

export ORG_GRADLE_PROJECT_mediaKitLocalArm64Jar="$jar"
export ORG_GRADLE_PROJECT_mediaKitArm64Only=true
mode=(); [[ "$variant" == debug ]] && mode=(--debug)
flutter build apk "${mode[@]}" --target-platform android-arm64 \
  "${base_defines[@]}" "${extra[@]}"
apk="media_kit_hdr_lab/build/app/outputs/flutter-apk/app-${variant}.apk"
cp "$apk" "media_kit_hdr_lab/build/app/outputs/flutter-apk/$tag-$variant.apk"
echo "=== DONE: $tag-$variant.apk ==="
shasum -a 256 "media_kit_hdr_lab/build/app/outputs/flutter-apk/$tag-$variant.apk"
