#!/usr/bin/env bash
# P3 phase2 (c) PiliPlus managed-host round driver (LG H870DS, Android 7).
# Derived from lab/run_lab_round.sh; differences for the PiliPlus host app:
#   * launch via bilibili deep link with ?t=<sec> to pin the start position
#     (overrides watch-history restore; prevents EOF mid-round)
#   * frame-advance evidence sampler: media_session PlaybackState +
#     SurfaceFlinger --latency on the video SurfaceView layer +
#     per-thread /proc/<pid>/task/*/stat utime snapshots, taken at
#     multiple time points pre-HOME / during-HOME / post-return
#   * modes: normal | fast | fullscreen | sdr
# Never touches system settings/sysprops. Test package; no restore needed.
#
# usage: run_pp_round.sh <round_dir> <mode>
# env: T_SEC=120 PRE_HOME_WAIT=32 HOME_WAIT=10 POST_WAIT=28
set -Eeuo pipefail
ROUND_DIR=$1; MODE=$2
SER=LGH870DS42e27764
PKG=com.example.piliplus.dev
ACT=$PKG/com.example.piliplus.MainActivity
DV_URL="https://www.bilibili.com/video/BV1vY4y1N7TY?t=${T_SEC:-120}"
LAYER="SurfaceView - $ACT"
T_SEC=${T_SEC:-120}
PRE_HOME_WAIT=${PRE_HOME_WAIT:-32}
HOME_WAIT=${HOME_WAIT:-10}
POST_WAIT=${POST_WAIT:-28}
mkdir -p "$ROUND_DIR"
EV="$ROUND_DIR/host-events.ndjson"
: > "$EV"
exec > >(tee "$ROUND_DIR/driver.log") 2>&1

hostms() { python3 -c 'import time;print(int(time.time()*1000))'; }
devms() { adb -s "$SER" shell 'echo $EPOCHREALTIME' | tr -d '\r' | awk '{printf "%d", $1*1000}'; }
ev() { # ev <event> [note]
  local h; h=$(hostms); local d; d=$(devms)
  printf '{"event":"%s","host_ms":%s,"device_ms":%s,"note":"%s"}\n' "$1" "$h" "$d" "${2:-}" >> "$EV"
  echo "[$(date +%H:%M:%S)] $1 host_ms=$h device_ms=$d ${2:-}"
}
pid() { adb -s "$SER" shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true; }
screen() { adb -s "$SER" shell dumpsys power | grep -E "Display Power: state|mWakefulness=" | tr -d '\r'; adb -s "$SER" shell dumpsys window 2>/dev/null | grep -oE "mCurrentFocus=Window\{[^}]*\}" | head -1 | tr -d '\r'; }
sample() { # sample <label>  -- frame-advance evidence bundle
  local lbl=$1 h d
  h=$(hostms); d=$(devms)
  adb -s "$SER" shell "dumpsys media_session" 2>/dev/null | sed -n '/media-session '"$PKG"'/,/queueTitle/p' > "$ROUND_DIR/sample-$lbl-mediasession.txt" || true
  adb -s "$SER" shell "dumpsys SurfaceFlinger --latency '$LAYER'" > "$ROUND_DIR/sample-$lbl-sflatency.txt" 2>&1 || true
  local p; p=$(pid)
  if [[ -n "$p" ]]; then
    adb -s "$SER" shell "for t in \$(ls /proc/$p/task); do cat /proc/$p/task/\$t/stat 2>/dev/null | cut -d' ' -f1,2,14,15; done" > "$ROUND_DIR/sample-$lbl-threads.txt" 2>/dev/null || true
  fi
  printf '{"event":"sample","label":"%s","host_ms":%s,"device_ms":%s,"pid":"%s"}\n' "$lbl" "$h" "$d" "${p:-}" >> "$EV"
  echo "[$(date +%H:%M:%S)] sample $lbl host_ms=$h device_ms=$d pid=${p:-} sf_lines=$(wc -l < "$ROUND_DIR/sample-$lbl-sflatency.txt" | tr -d ' ')"
}
shot() { adb -s "$SER" exec-out screencap -p > "$ROUND_DIR/$1.png" 2>/dev/null && ev screenshot "$1 lines=$(wc -c < "$ROUND_DIR/$1.png" | tr -d ' ')"; }

ev round_begin "mode=$MODE pkg=$PKG dv_url=$DV_URL pre_home_wait=$PRE_HOME_WAIT home_wait=$HOME_WAIT post_wait=$POST_WAIT"
screen | tee "$ROUND_DIR/screen-before.txt"
DROPBOX_BEFORE=$(adb -s "$SER" shell dumpsys dropbox 2>/dev/null | grep -cE "data_app_crash|data_app_anr|data_app_native_crash|SYSTEM_TOMBSTONE" | tr -d '\r' || true)
ev dropbox_before "crash_entries=$DROPBOX_BEFORE"

adb -s "$SER" shell am force-stop "$PKG"; sleep 1
ev force_stop "pid_after=$(pid)"
for b in main system crash events radio kernel; do
  if adb -s "$SER" logcat -c -b "$b" >/dev/null 2>&1; then echo "logcat -c -b $b rc=0"; else echo "logcat -c -b $b rc=$?"; fi
done
ev logcat_cleared "per-buffer"

if [[ "$MODE" == sdr ]]; then
  FEED_TAP_X=${FEED_TAP_X:-360}
  FEED_TAP_Y=${FEED_TAP_Y:-800}
  adb -s "$SER" shell am start -n "$ACT" | tr -d '\r' | tee "$ROUND_DIR/launch-output.txt"
  ev am_start_cold "pid=$(pid)"
  sleep 6
  shot sdr-home-feed
  adb -s "$SER" shell input tap "$FEED_TAP_X" "$FEED_TAP_Y"
  ev tap_first_feed_card "x=$FEED_TAP_X y=$FEED_TAP_Y"
  sleep 6
  shot sdr-video-opened
else
  adb -s "$SER" shell am start -a android.intent.action.VIEW -d "$DV_URL" -p "$PKG" | tr -d '\r' | tee "$ROUND_DIR/launch-output.txt"
  ev am_start_deeplink "pid=$(pid) url=$DV_URL"
fi

sleep 8
sample play_start
shot after-launch

if [[ "$MODE" == fullscreen ]]; then
  # show-panel + tap-fullscreen chained in ONE device shell: the control panel
  # auto-hides in ~3 s, so both taps must land inside that window
  adb -s "$SER" shell "input tap 720 540; sleep 0.6; input tap 1348 793"
  ev tap_fullscreen "chained show_panel(720,540)+fullscreen(1348,793)"
  sleep 4
  shot after-fullscreen
  # fullscreen detection: portrait detail page has bright content below y~1100;
  # fullscreen landscape fills the screen with dark video
  FS_STATE=$(python3 -c "
from PIL import Image
im = Image.open('$ROUND_DIR/after-fullscreen.png').convert('RGB')
px = im.load()
bright = sum(1 for x in range(0, 1440, 10) if sum(px[x, 1500]) > 400)
print('FULLSCREEN' if bright < 60 else 'PORTRAIT')
" 2>/dev/null || echo UNKNOWN)
  ev fullscreen_state "$FS_STATE"
  adb -s "$SER" shell "dumpsys window policy | grep -E 'mRotation|orientation'" | tr -d '\r' | head -4 > "$ROUND_DIR/orientation-after-fullscreen.txt" || true
  adb -s "$SER" shell "dumpsys window windows | grep -E 'mOrientation|mRotation'" | tr -d '\r' | head -4 >> "$ROUND_DIR/orientation-after-fullscreen.txt" || true
  sample fullscreen_prehome
fi

EXTRA_FS_WAIT=0
if [[ "$MODE" == fullscreen ]]; then EXTRA_FS_WAIT=9; fi
sleep $(( PRE_HOME_WAIT - 8 - EXTRA_FS_WAIT ))
sample pre_home_1
PID_BEFORE=$(pid)
ev pid_before "pid=$PID_BEFORE"
adb -s "$SER" exec-out logcat -d -v threadtime -b all > "$ROUND_DIR/logcat-pre-home.txt"
ev interim_dump "lines=$(wc -l < "$ROUND_DIR/logcat-pre-home.txt")"
echo "--- pre-HOME hwdec evidence ---"
grep -E "class=dvP84|mkst_create_decoder_window exit|MediaCodec create|makeComponentInstance|Now Executing|MKSURF-E1" "$ROUND_DIR/logcat-pre-home.txt" | cut -c1-190 | tail -8 || true

if [[ "$MODE" == fast ]]; then
  INNER="am start -a android.intent.action.MAIN -c android.intent.category.HOME --activity-no-animation; am start -n $ACT --activity-no-animation"
  ev home_send_begin "cmd=adb shell: $INNER"
  adb -s "$SER" shell "$INNER" 2>&1 | tr -d '\r' | tee "$ROUND_DIR/return-output.txt" >/dev/null
  ev home_sent "chained home+return shell returned (method F, sleep 0)"
  ev return_sent "chained"
else
  ev home_send_begin "cmd=input keyevent KEYCODE_HOME"
  adb -s "$SER" shell input keyevent KEYCODE_HOME
  ev home_sent
  sleep 4
  sample during_home_1
  sleep $(( HOME_WAIT - 4 - 3 ))
  sample during_home_2
  ev home_dwell_done "home_wait=$HOME_WAIT"
  ev return_send_begin "cmd=am start -n $ACT"
  adb -s "$SER" shell am start -n "$ACT" | tr -d '\r' | tee "$ROUND_DIR/return-output.txt" >/dev/null
  ev return_sent
fi

sleep 5
sample post_return_1
shot after-return
sleep 10
sample post_return_2
sleep $(( POST_WAIT - 15 ))
sample post_return_3

PID_AFTER=$(pid)
ev pid_after "pid_before=$PID_BEFORE pid_after=$PID_AFTER"
adb -s "$SER" shell dumpsys window 2>/dev/null | grep -E "mCurrentFocus|mFocusedApp" | tr -d '\r' | head -2 | tee "$ROUND_DIR/focus-after.txt"
screen | tee "$ROUND_DIR/screen-after.txt"
adb -s "$SER" exec-out logcat -d -v threadtime -b all > "$ROUND_DIR/logcat-full.txt"
ev full_dump "lines=$(wc -l < "$ROUND_DIR/logcat-full.txt")"
DROPBOX_AFTER=$(adb -s "$SER" shell dumpsys dropbox 2>/dev/null | grep -cE "data_app_crash|data_app_anr|data_app_native_crash|SYSTEM_TOMBSTONE" | tr -d '\r' || true)
ev dropbox_after "crash_entries_before=$DROPBOX_BEFORE after=$DROPBOX_AFTER"
echo "--- post-return key lines ---"
grep -E "MKS-HOME-TRACE.*(authorize|ensure_init\(lc_verify\) exit|create_decoder_window (enter|exit)|mkst_shutdown|surfaceCreated|surfaceDestroyed)|class=dvP84|MediaCodec create|makeComponentInstance|Now Executing|MKSURF-E1|FATAL|ANR in" "$ROUND_DIR/logcat-full.txt" | cut -c1-210 | tail -40 || true
ev round_end
