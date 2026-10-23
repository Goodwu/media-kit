#!/usr/bin/env bash
# 测试版默认构建入口：从最新源码构建 libmpv JAR，再构建 Android 测试 APK。
#
# 这是测试链的正向打包路径：
#   1. build_android_native.py 同步本地依赖源码构建树与当前 mpv；
#   2. 从 helper 当前源码编译，组合 NDK 运行库，产出全新 arm64 JAR/溯源；
#   3. 经 Gradle 正式的本地 JAR 通道构建测试 APK。
# 可复用工具与配方受版本管理；build/ 仅保存可重建产物。
#
# 发布构建不走本脚本：gradle 默认下载钉定发布 JAR + SHA-256 核验（发布链）。
#
# usage: build-android-test.sh [--debug] [--tag <name>] [--platform-view]
#                              --local-source <device-path> [--app-dir <flutter-project>]
#                              [-- 额外 flutter build 参数 ...]
set -Eeuo pipefail
cd "$(dirname "$0")/.."

variant=release
tag=test-latest
platform_view=false
local_source=
app_dir=
extra=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) variant=debug; shift;;
    --tag) tag=$2; shift 2;;
    --platform-view) platform_view=true; shift;;
    --local-source) local_source=$2; shift 2;;
    --app-dir) app_dir=$2; shift 2;;
    --) shift; extra+=("$@"); break;;
    *) extra+=("$1"); shift;;
  esac
done
lab_dir="$PWD/media_kit_hdr_lab"
if [[ -z "$app_dir" ]]; then
  app_dir="$lab_dir"
  [[ -n "$local_source" ]] || { echo "need --local-source <device-path> for the default hdr_lab build" >&2; exit 2; }
fi
[[ -f "$app_dir/pubspec.yaml" ]] || { echo "Flutter project not found: $app_dir" >&2; exit 2; }
app_dir="$(cd "$app_dir" && pwd)"
is_lab=false
[[ "$app_dir" == "$(cd "$lab_dir" && pwd)" ]] && is_lab=true

export JAVA_HOME="${MEDIA_KIT_JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
ndk="${MEDIA_KIT_ANDROID_NDK:-$HOME/Library/Android/sdk/ndk/27.2.12479018}"
native_repo="${MEDIA_KIT_NATIVE_REPO:-$HOME/src/libmpv-android-video-build-dv-experiment}"
mpv_source="${MEDIA_KIT_MPV_SOURCE:-$HOME/src/mpv}"
[[ "$tag" != */* && "$tag" != . && "$tag" != .. ]] || { echo "tag must be a file name" >&2; exit 2; }
native_output="${MEDIA_KIT_NATIVE_OUTPUT:-$PWD/build/android-native/$tag-$(date +%Y%m%d-%H%M%S)-$$}"

# Preserve --debug as an app-variant selector. Both variants rebuild every
# native component from local source; neither consumes a released native JAR.
echo "=== [1-2/3] current local native sources → fresh arm64 JAR ==="
native_args=(--native-repo "$native_repo" --mpv-source "$mpv_source" --ndk "$ndk"
  --output "$native_output" --jobs "${MEDIA_KIT_BUILD_JOBS:-4}")
[[ -n "${MEDIA_KIT_MPV_BUILD:-}" ]] && native_args+=(--mpv-build "$MEDIA_KIT_MPV_BUILD")
python3 tool/build_android_native.py "${native_args[@]}"
jar="$native_output/package/default-arm64-v8a.jar"
[[ -f "$jar" ]] || { echo "JAR missing: $jar" >&2; exit 1; }
jar="$(cd "$(dirname "$jar")" && pwd)/$(basename "$jar")"
shasum -a 256 "$jar"
[[ "${MKS_SKIP_APK:-0}" == 1 ]] && { echo "native-only: $jar"; exit 0; }

echo "=== [3/3] flutter build apk ($variant, local JAR) ==="
base_defines=()
if $is_lab; then
  base_defines+=(
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
fi

export ORG_GRADLE_PROJECT_mediaKitLocalArm64Jar="$jar"
export ORG_GRADLE_PROJECT_mediaKitArm64Only=true
mode=(--release); [[ "$variant" == debug ]] && mode=(--debug)
output_dir="$app_dir/build/app/outputs/flutter-apk"
mkdir -p "$output_dir"
build_marker="$(mktemp "$output_dir/.android-test-build.XXXXXX")"
trap 'rm -f "$build_marker"' EXIT
split_per_abi=false
for arg in "${extra[@]}"; do
  [[ "$arg" == --split-per-abi ]] && split_per_abi=true
done
(cd "$app_dir" && flutter build apk "${mode[@]}" --target-platform android-arm64 \
  "${base_defines[@]}" "${extra[@]}")
apk="$output_dir/app-${variant}.apk"
if $split_per_abi; then
  apk="$app_dir/build/app/outputs/flutter-apk/app-arm64-v8a-${variant}.apk"
fi
[[ -f "$apk" ]] || { echo "APK missing for $variant under $app_dir/build/app/outputs/flutter-apk" >&2; exit 1; }
[[ "$apk" -nt "$build_marker" ]] || { echo "APK was not rebuilt in this invocation: $apk" >&2; exit 1; }
cp "$apk" "$output_dir/$tag-$variant.apk"
echo "=== DONE: $tag-$variant.apk ($app_dir) ==="
shasum -a 256 "$output_dir/$tag-$variant.apk"
