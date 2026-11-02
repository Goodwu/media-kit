#!/bin/bash
# Verifier helper: one LYA playback round for the prod3 fusion package.
# Usage: run_round.sh <out_dir> <A|B|C> [duration_s]
#   A: debug.mks.* all empty
#   B: debug.mks.yuv_fusion=0
#   C: debug.mks.yuv_fusion_table=1
# Only adb reads/writes against serial 3EP7N18C28016072. Never uninstalls.
set -u
S=3EP7N18C28016072
PKG=com.example.media_kit_hdr_lab
OUT="$1"; MODE="$2"; DUR="${3:-120}"
mkdir -p "$OUT"
adb() { command adb -s "$S" "$@"; }
ts() { date +%H:%M:%S; }
log() { echo "[$(ts)] $*" | tee -a "$OUT/timeline.txt"; }

log "round=$MODE out=$OUT dur=${DUR}s"
adb shell am force-stop "$PKG"
sleep 1
adb logcat -c
adb logcat -c   # clear twice: some buffers lag

# --- properties (clear via shell quoting; adb setprop with empty arg is swallowed) ---
adb shell "setprop debug.mks.yuv_fusion ''"
adb shell "setprop debug.mks.yuv_fusion_table ''"
case "$MODE" in
  A) ;;
  B) adb shell setprop debug.mks.yuv_fusion 0 ;;
  C) adb shell setprop debug.mks.yuv_fusion_table 1 ;;
  *) log "unknown mode $MODE"; exit 1 ;;
esac
{
  echo "# getprop | grep debug.mks"
  adb shell "getprop | grep debug.mks" | tr -d '\r'
  echo "yuv_fusion=[$(adb shell getprop debug.mks.yuv_fusion | tr -d '\r')]"
  echo "yuv_fusion_table=[$(adb shell getprop debug.mks.yuv_fusion_table | tr -d '\r')]"
} > "$OUT/props.txt"
cat "$OUT/props.txt" | tee -a "$OUT/timeline.txt"

# --- pre-start device state (re-assert landscape lock: the system resets user_rotation to 0 after the app exits) ---
adb shell settings put system accelerometer_rotation 0
adb shell settings put system user_rotation 1
{
  adb shell dumpsys window | grep -E 'mCurrentFocus|isStatusBarKeyguard' | tr -d '\r'
  adb shell dumpsys power | grep -E 'mWakefulness=|Display Power' | tr -d '\r'
  for p in screen_brightness screen_brightness_mode accelerometer_rotation user_rotation screen_off_timeout; do
    echo "$p=$(adb shell settings get system $p | tr -d '\r')"
  done
  echo "gpufreq cur=$(adb shell cat /sys/class/devfreq/gpufreq/cur_freq | tr -d '\r')"
} > "$OUT/state_prestart.txt"

log "am start"
adb shell am start -n "$PKG/.MainActivity" | tr -d '\r' | tee -a "$OUT/timeline.txt"
sleep 4
{
  adb shell dumpsys window | grep -E 'mCurrentFocus|isStatusBarKeyguard|mUserRotation' | tr -d '\r'
  adb shell dumpsys input | grep -E 'SurfaceOrientation' | tr -d '\r' | head -2
} > "$OUT/state_pretap.txt"
cat "$OUT/state_pretap.txt" | tee -a "$OUT/timeline.txt"
if ! grep -q "$PKG" "$OUT/state_pretap.txt"; then log "WARN: focus is not $PKG before tap"; fi
if grep -q 'isStatusBarKeyguard=true' "$OUT/state_pretap.txt"; then log "WARN: keyguard showing before tap"; fi

log "tap 1560 720"
adb shell input tap 1560 720
TAP_TS=$(date +%s)

# --- wait for playback-open marker ---
T0=""
for i in $(seq 1 30); do
  if adb logcat -d 2>/dev/null | grep -qE 'ANDROID_HDR_OPEN|HdrDiag HDR decision|VIDEOPARAMS'; then T0=$(date +%s); break; fi
  sleep 1
done
if [ -z "$T0" ]; then
  log "FAIL: no playback-open marker within 30s of tap"
  adb logcat -d > "$OUT/logcat_fail.txt"
  adb shell screencap -p /sdcard/mks_round_fail.png && adb pull /sdcard/mks_round_fail.png "$OUT/screencap_fail.png" >/dev/null
  adb shell dumpsys window | grep -E 'mCurrentFocus' | tr -d '\r' | tee -a "$OUT/timeline.txt"
  adb shell am force-stop "$PKG"
  exit 2
fi
log "playback-open marker seen $((T0-TAP_TS))s after tap"
adb logcat -d | grep -E 'ANDROID_HDR_OPEN|HdrDiag HDR decision|VIDEOPARAMS' | head -4 | cut -c1-300 | tee -a "$OUT/timeline.txt"
PID=$(adb shell pidof "$PKG" | tr -d '\r')
log "pid=$PID"

# --- discover SurfaceFlinger layers after a few seconds of playback ---
sleep 6
adb shell dumpsys SurfaceFlinger --list | tr -d '\r' > "$OUT/sf_layers.txt"
grep -i "$PKG\|SurfaceView\|SurfaceTexture\|media_kit" "$OUT/sf_layers.txt" | tee -a "$OUT/timeline.txt"

# --- sampling loop over DUR seconds from T0 ---
: > "$OUT/top_samples.txt"
: > "$OUT/gpufreq_samples.txt"
: > "$OUT/focus_samples.txt"
SHOT_DONE=0
LAT_N=0
while :; do
  NOW=$(date +%s); EL=$((NOW-T0))
  [ "$EL" -ge "$DUR" ] && break
  # every ~15s: top + gpufreq + focus
  if [ $((EL % 15)) -lt 3 ]; then
    { echo "### t=+${EL}s $(ts)"; adb shell top -b -n 1 -p "$PID" -o PID,%CPU,%MEM,CMDLINE 2>/dev/null | tr -d '\r' | tail -2; } >> "$OUT/top_samples.txt"
    echo "t=+${EL}s cur_freq=$(adb shell cat /sys/class/devfreq/gpufreq/cur_freq | tr -d '\r')" >> "$OUT/gpufreq_samples.txt"
    echo "t=+${EL}s $(adb shell dumpsys window | grep -E 'mCurrentFocus' | tr -d '\r')" >> "$OUT/focus_samples.txt"
  fi
  # SF latency windows at ~30s, ~60s, ~90s
  if { [ "$EL" -ge 30 ] && [ "$LAT_N" -eq 0 ]; } || { [ "$EL" -ge 60 ] && [ "$LAT_N" -eq 1 ]; } || { [ "$EL" -ge 90 ] && [ "$LAT_N" -eq 2 ]; }; then
    LAT_N=$((LAT_N+1))
    log "sf latency window #$LAT_N at +${EL}s"
    # Collect layer names first; adb shell inside a read-loop would eat stdin.
    LAYERS=()
    while IFS= read -r layer; do [ -n "$layer" ] && LAYERS+=("$layer"); done < <(grep -E "^(SurfaceView - )?$PKG/" "$OUT/sf_layers.txt")
    for layer in "${LAYERS[@]}"; do
      safe=$(echo "$layer" | tr -c 'A-Za-z0-9._#-' '_' | sed 's/#/_N/g' | rev | cut -c1-90 | rev)
      adb shell "dumpsys SurfaceFlinger --latency '$layer'" </dev/null | tr -d '\r' > "$OUT/sf_latency_${LAT_N}_${safe}.txt"
    done
    adb shell dumpsys SurfaceFlinger </dev/null | tr -d '\r' > "$OUT/sf_dump_${LAT_N}.txt"
  fi
  # screencap at ~60s
  if [ "$EL" -ge 60 ] && [ "$SHOT_DONE" -eq 0 ]; then
    SHOT_DONE=1
    log "screencap at +${EL}s"
    adb shell screencap -p /sdcard/mks_round_shot.png && adb pull /sdcard/mks_round_shot.png "$OUT/screencap_60s.png" >/dev/null
    adb shell rm -f /sdcard/mks_round_shot.png
  fi
  sleep 3
done
# second screencap near end for frame-advance comparison
adb shell screencap -p /sdcard/mks_round_shot2.png && adb pull /sdcard/mks_round_shot2.png "$OUT/screencap_end.png" >/dev/null
adb shell rm -f /sdcard/mks_round_shot2.png

# --- end of round: health, logs ---
ALIVE=$(adb shell pidof "$PKG" | tr -d '\r')
log "end: pid_at_start=$PID pid_at_end=[$ALIVE]"
{
  echo "pid_at_start=$PID"
  echo "pid_at_end=$ALIVE"
  adb shell dumpsys window | grep -E 'mCurrentFocus|isStatusBarKeyguard' | tr -d '\r'
  echo "--- dropbox entries (crash/anr) in last 10 min ---"
  adb shell dumpsys dropbox | tr -d '\r' | grep -E 'crash|anr|tombstone|ANR' | tail -20
  echo "--- dumpsys activity processes (hdr_lab) ---"
  adb shell dumpsys activity processes | tr -d '\r' | grep -i "hdr_lab" | head -10
} > "$OUT/health_end.txt"
adb logcat -d -v threadtime > "$OUT/logcat_full.txt"
adb logcat -d -b crash -v threadtime > "$OUT/logcat_crash.txt" 2>/dev/null
adb shell am force-stop "$PKG"
log "force-stop done; files in $OUT"
