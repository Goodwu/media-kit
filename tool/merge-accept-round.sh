#!/usr/bin/env bash
# 合并验收轮：Glass SDR 全片（EOS+片尾+direct/rescale 证据）
# usage: round-glass-full.sh <apk> <tag> [duration_seconds]
set -Eeuo pipefail
apk=${1:?}; tag=${2:?}; dur=${3:-230}
original=${MEDIA_KIT_ORIGINAL_APK:?set MEDIA_KIT_ORIGINAL_APK to the restore APK}
base=/tmp/merge-accept-${tag}
logcat_pid=
restore() {
  set +e
  if [[ -n "$logcat_pid" ]]; then kill "$logcat_pid" 2>/dev/null; wait "$logcat_pid" 2>/dev/null; fi
  adb shell am force-stop com.example.media_kit_hdr_lab
  adb install -r -d "$original"
  adb shell setprop debug.media_kit.p5_image_timeline 0
  adb shell settings put system screen_brightness_mode 1
  adb shell input keyevent KEYCODE_SLEEP
  adb shell dumpsys package com.example.media_kit_hdr_lab | grep -m1 versionCode
  adb shell settings get system screen_brightness_mode
  adb shell dumpsys power | grep -m1 mWakefulness
}
trap restore EXIT INT TERM
adb install -r -d "$apk"
for attempt in 1 2 3; do
  adb shell input keyevent KEYCODE_WAKEUP
  adb shell input keyevent KEYCODE_MENU
  sleep 1
  if adb shell dumpsys window | grep -q 'isStatusBarKeyguard=false'; then break; fi
done
adb shell dumpsys window | grep -q 'isStatusBarKeyguard=false'
adb shell setprop debug.media_kit.p5_image_timeline 1
adb logcat -c
adb logcat -v threadtime > "$base-device.log" &
logcat_pid=$!
adb shell am start -n com.example.media_kit_hdr_lab/.MainActivity
for attempt in 1 2 3 4 5; do
  sleep 2
  if adb shell dumpsys window | grep -q 'mCurrentFocus=.*com.example.media_kit_hdr_lab' &&
     adb shell dumpsys window | grep -q 'isStatusBarKeyguard=false'; then break; fi
  adb shell input keyevent KEYCODE_WAKEUP
  adb shell input keyevent KEYCODE_MENU
  adb shell am start -n com.example.media_kit_hdr_lab/.MainActivity
done
adb shell dumpsys window | grep -q 'mCurrentFocus=.*com.example.media_kit_hdr_lab'
adb shell input tap 1560 720
sleep 5
grep -q 'ANDROID_HDR_OPEN sample=AndroidHdrSample.dolbyVisionP5' "$base-device.log" && echo "OPEN_OK"
t=0
for shot in 30 90 150; do
  if [ "$shot" -ge "$dur" ]; then break; fi
  sleep $((shot - t)); t=$shot
  adb exec-out screencap -p > "$base-t${shot}.png"
done
sleep $((dur - t)); t=$dur
adb exec-out screencap -p > "$base-t${t}.png"
sleep 5
echo "=== 关键证据 grep ==="
grep -m2 'P5_SECTION_INIT' "$base-device.log" | head -2
grep -m1 'P5_DOVI_RESCALE' "$base-device.log" || echo "NO_RESCALE_LOG"
grep -m1 'AUTO_COMPLETED' "$base-device.log" || echo "NO_COMPLETED"
grep -c 'Failed rendering frame' "$base-device.log" || true
grep -m3 'P5_TAIL_FALLBACK' "$base-device.log" || echo "NO_TAIL_FALLBACK"
echo "=== 退出闭合 ==="
adb shell input keyevent KEYCODE_BACK
sleep 6
grep -m2 'P5_IMAGE_FINAL' "$base-device.log" | head -2
