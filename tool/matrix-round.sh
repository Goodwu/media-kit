#!/usr/bin/env bash
# 播放矩阵轮次：全屏、最高亮度；结束恢复原 12492、自动亮度、熄屏
# usage: matrix-round.sh <apk> <tag> <duration_seconds> <sample_enum>
set -Eeuo pipefail
apk=${1:?}; tag=${2:?}; dur=${3:?}; sample=${4:?}
serial=${ANDROID_SERIAL:-}
adb="adb ${serial:+-s $serial}"
original=${MEDIA_KIT_ORIGINAL_APK:?set MEDIA_KIT_ORIGINAL_APK to the restore APK}
base=/tmp/matrix-round-${tag}
logcat_pid=
restore() {
  set +e
  if [[ -n "$logcat_pid" ]]; then kill "$logcat_pid" 2>/dev/null; wait "$logcat_pid" 2>/dev/null; fi
  $adb shell am force-stop com.example.media_kit_hdr_lab
  $adb install -r -d "$original"
  $adb shell setprop debug.media_kit.p5_image_timeline 0
  $adb shell settings put system screen_brightness_mode 1
  $adb shell input keyevent KEYCODE_SLEEP
  $adb shell dumpsys package com.example.media_kit_hdr_lab | grep -m1 versionCode
  $adb shell settings get system screen_brightness_mode
  $adb shell dumpsys power | grep -m1 mWakefulness
}
trap restore EXIT INT TERM
$adb install -r -d "$apk"
for attempt in 1 2 3; do
  $adb shell input keyevent KEYCODE_WAKEUP
  $adb shell input keyevent KEYCODE_MENU
  sleep 1
  if $adb shell dumpsys window | grep -q 'isStatusBarKeyguard=false'; then break; fi
done
$adb shell dumpsys window | grep -q 'isStatusBarKeyguard=false'
# 全屏播放期间最高亮度
$adb shell settings put system screen_brightness_mode 0
$adb shell settings put system screen_brightness 255
echo "brightness_value=$($adb shell settings get system screen_brightness | tr -d '\r')"
$adb shell setprop debug.media_kit.p5_image_timeline 1
$adb logcat -c
$adb logcat -v threadtime > "$base-device.log" &
logcat_pid=$!
$adb shell am start -n com.example.media_kit_hdr_lab/.MainActivity
for attempt in 1 2 3 4 5; do
  sleep 2
  if $adb shell dumpsys window | grep -q 'mCurrentFocus=.*com.example.media_kit_hdr_lab' &&
     $adb shell dumpsys window | grep -q 'isStatusBarKeyguard=false'; then break; fi
  $adb shell input keyevent KEYCODE_WAKEUP
  $adb shell input keyevent KEYCODE_MENU
  $adb shell am start -n com.example.media_kit_hdr_lab/.MainActivity
done
$adb shell dumpsys window | grep -q 'mCurrentFocus=.*com.example.media_kit_hdr_lab'
$adb shell input tap 1560 720
sleep 5
grep -q "ANDROID_HDR_OPEN sample=$sample " "$base-device.log" && echo "OPEN_OK" || echo "OPEN_MISSING"
t=0
sf_dumped=0
for shot in 30 45 90 150 240; do
  if [ "$shot" -ge "$dur" ]; then break; fi
  if [ "$shot" = 45 ] && [ "$sf_dumped" = 0 ]; then
    sleep $((shot - t)); t=$shot; sf_dumped=1
    $adb shell dumpsys SurfaceFlinger > "$base-sf-t45.txt" 2>&1 || true
    continue
  fi
  sleep $((shot - t)); t=$shot
  $adb exec-out screencap -p > "$base-t${shot}.png"
done
sleep $((dur - t)); t=$dur
$adb exec-out screencap -p > "$base-t${t}.png"
sleep 5
echo "=== 关键证据 grep ==="
grep -m1 "ANDROID_NAMED_LOCAL_SAMPLE" "$base-device.log" || echo "NO_NAMED_SAMPLE"
grep -m1 "ANDROID_HDR_OPEN" "$base-device.log" || echo "NO_HDR_OPEN"
grep -m2 'P5_SECTION_INIT' "$base-device.log" | head -2 || true
grep -m1 'P5_DOVI_RESCALE' "$base-device.log" || true
grep -m1 'P84_BASE_FILTER' "$base-device.log" || true
grep -m1 'AUTO_COMPLETED' "$base-device.log" || echo "NO_COMPLETED"
echo "render_failures=$(grep -c 'Failed rendering frame' "$base-device.log" || true)"
grep -m3 'P5_TAIL_FALLBACK' "$base-device.log" || true
grep -m1 'ANDROID_TEXTURE_PREPARED' "$base-device.log" || true
echo "=== SF HDR 层 (t45) ==="
grep -i -m6 'bt2020\| bt2020\|PQ\|HLG' "$base-sf-t45.txt" 2>/dev/null | head -6 || echo "NO_SF_DUMP"
echo "=== 退出闭合 ==="
$adb shell input keyevent KEYCODE_BACK
sleep 6
grep -m2 'P5_IMAGE_FINAL' "$base-device.log" | head -2 || true
grep -c 'FATAL EXCEPTION\|SIGSEGV' "$base-device.log" || true
