#!/usr/bin/env bash
# 播放矩阵轮次（Mi Note 3 jason 5b79aada）：全屏、最高亮度；结束卸载测试包、恢复原亮度、熄屏
# tap 采用旋转竞态修正：点击后验证 DIRECT_OPEN trigger，未命中换坐标重试
# usage: matrix-round-jason.sh <apk> <tag> <duration_seconds> <sample_enum>
set -Eeuo pipefail
apk=${1:?}; tag=${2:?}; dur=${3:?}; sample=${4:?}
serial=${ANDROID_SERIAL:-}
adb="adb ${serial:+-s $serial}"
base=/tmp/matrix-jason-${tag}
logcat_pid=
restore() {
  set +e
  if [[ -n "$logcat_pid" ]]; then kill "$logcat_pid" 2>/dev/null; wait "$logcat_pid" 2>/dev/null; fi
  $adb shell am force-stop com.example.media_kit_hdr_lab
  $adb uninstall com.example.media_kit_hdr_lab
  $adb shell setprop debug.media_kit.p5_image_timeline 0
  $adb shell settings put system screen_brightness 50
  $adb shell settings put system screen_brightness_mode 1
  $adb shell input keyevent KEYCODE_SLEEP
  $adb shell settings get system screen_brightness_mode
  $adb shell dumpsys power | grep -m1 mWakefulness
}
trap restore EXIT INT TERM
$adb install -r -d "$apk"
for attempt in 1 2 3; do
  $adb shell input keyevent KEYCODE_WAKEUP
  $adb shell input keyevent KEYCODE_MENU
  sleep 1
  if $adb shell dumpsys window | grep -q 'isKeyguardShowing=false'; then break; fi
done
$adb shell dumpsys window | grep -q 'isKeyguardShowing=false'
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
     $adb shell dumpsys window | grep -q 'isKeyguardShowing=false'; then break; fi
  $adb shell input keyevent KEYCODE_WAKEUP
  $adb shell input keyevent KEYCODE_MENU
  $adb shell am start -n com.example.media_kit_hdr_lab/.MainActivity
done
$adb shell dumpsys window | grep -q 'mCurrentFocus=.*com.example.media_kit_hdr_lab'
# 点击打开：先竖屏中心，旋转后换横屏中心；验证 DIRECT_OPEN trigger 落地
tapped=0
for attempt in 1 2 3 4 5 6; do
  if grep -q "ANDROID_DIRECT_OPEN trigger" "$base-device.log"; then tapped=1; break; fi
  if [ $((attempt % 2)) = 1 ]; then
    $adb shell input tap 540 960
  else
    $adb shell input tap 960 540
  fi
  sleep 4
done
if [ "$tapped" = 1 ]; then echo "TAP_OK"; else echo "TAP_MISSING"; fi
sleep 8
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
grep -m3 "CodecException\|Failed to configure\|Could not open codec\|AUTO_SOURCE ERROR" "$base-device.log" || true
grep -m2 'P5_SECTION_INIT' "$base-device.log" | head -2 || true
grep -m1 'P5_DOVI_RESCALE' "$base-device.log" || true
grep -m1 'AUTO_COMPLETED completed=true' "$base-device.log" || echo "NO_EOS"
echo "render_failures=$(grep -c 'Failed rendering frame' "$base-device.log" || true)"
grep -m3 'P5_TAIL_FALLBACK' "$base-device.log" || true
grep "PERF t=.* time-pos" "$base-device.log" | tail -3 || true
grep "ANDROID_P5_COUNTERS" "$base-device.log" | tail -2 || true
echo "=== 退出 ==="
$adb shell input keyevent KEYCODE_BACK
sleep 6
grep -m2 'P5_IMAGE_FINAL' "$base-device.log" | head -2 || true
grep -c 'FATAL EXCEPTION\|SIGSEGV' "$base-device.log" || true
