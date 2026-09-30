#!/usr/bin/env bash
# 合并验收轮：播放中直接 Engine 销毁（broker 路径零崩溃 + 资源闭环）
set -Eeuo pipefail
apk=${1:?}; tag=$2
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
sleep 25   # 销毁于 25s 墙钟触发
echo "=== 销毁后进程状态 ==="
echo "pid_after_destroy=$(adb shell pidof com.example.media_kit_hdr_lab)"
adb exec-out screencap -p > "$base-postdestroy.png"
sleep 10
echo "pid_after_10s=$(adb shell pidof com.example.media_kit_hdr_lab)"
sleep 15
echo "pid_after_25s=$(adb shell pidof com.example.media_kit_hdr_lab)"
echo "=== 关键证据 ==="
grep -m2 'ANDROID_ENGINE_DESTROY' "$base-device.log"
grep -m2 'P5_IMAGE_FINAL' "$base-device.log" | head -2
grep -m2 'MpvOwnerBroker\|owner_broker\|BROKER' "$base-device.log" | head -2
echo "crash_count=$(grep -c 'FATAL EXCEPTION\|SIGSEGV\|Fatal signal' "$base-device.log")"
echo "=== mpv 线程残留（销毁后应为空） ==="
pid=$(adb shell pidof com.example.media_kit_hdr_lab | tr -d '\r\n')
[ -n "$pid" ] && adb shell ps -T -p "$pid" | grep -c "mpv\|lifecycle" || echo "0"
