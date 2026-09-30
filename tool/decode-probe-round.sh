#!/usr/bin/env bash
# 解码纯吞吐探针轮（Mi Note 3）：全片 surface 模式解码，无渲染；结束卸载、恢复亮度、熄屏
set -Eeuo pipefail
serial=${ANDROID_SERIAL:-}
adb="adb ${serial:+-s $serial}"
base=/tmp/matrix-jason-decode-probe
logcat_pid=
restore() {
  set +e
  if [[ -n "$logcat_pid" ]]; then kill "$logcat_pid" 2>/dev/null; wait "$logcat_pid" 2>/dev/null; fi
  $adb shell am force-stop com.example.media_kit_hdr_lab
  $adb uninstall com.example.media_kit_hdr_lab
  $adb shell svc power stayon false
  $adb shell settings put system screen_brightness 50
  $adb shell settings put system screen_brightness_mode 1
  $adb shell input keyevent KEYCODE_SLEEP
  $adb shell settings get system screen_brightness_mode
  $adb shell dumpsys power | grep -m1 mWakefulness
}
trap restore EXIT INT TERM
$adb install -r -d /tmp/matrix-decode-probe.apk
for attempt in 1 2 3; do
  $adb shell input keyevent KEYCODE_WAKEUP
  $adb shell input keyevent KEYCODE_MENU
  sleep 1
  if $adb shell dumpsys window | grep -q 'isKeyguardShowing=false'; then break; fi
done
$adb shell dumpsys window | grep -q 'isKeyguardShowing=false'
$adb shell settings put system screen_brightness_mode 0
$adb shell settings put system screen_brightness 255
$adb shell svc power stayon usb
$adb logcat -c
$adb logcat -v threadtime > "$base-device.log" &
logcat_pid=$!
$adb shell am start -n com.example.media_kit_hdr_lab/.MainActivity
for attempt in 1 2 3 4 5; do
  sleep 2
  if $adb shell dumpsys window | grep -q 'mCurrentFocus=.*com.example.media_kit_hdr_lab' &&
     $adb shell dumpsys window | grep -q 'isKeyguardShowing=false'; then break; fi
  $adb shell am start -n com.example.media_kit_hdr_lab/.MainActivity
done
$adb shell dumpsys window | grep -q 'mCurrentFocus=.*com.example.media_kit_hdr_lab'
echo "probe started, waiting (full-film decode ~2-4min)..."
# 探针完成标志：P5_CODEC_PROBE outputFps= 行出现
for i in $(seq 1 100); do
  sleep 5
  if grep -q "P5_CODEC_PROBE outputFps" "$base-device.log"; then echo "PROBE_DONE"; break; fi
  if grep -q "P5_CODEC_PROBE ERROR" "$base-device.log"; then echo "PROBE_ERROR"; break; fi
done
sleep 3
echo "=== 探针结果 ==="
command grep "P5_CODEC_PROBE" "$base-device.log" | command grep -v "image_part" | tail -30
