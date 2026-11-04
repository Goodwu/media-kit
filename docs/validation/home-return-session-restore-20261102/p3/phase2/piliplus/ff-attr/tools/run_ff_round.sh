#!/usr/bin/env bash
# ff-attr round driver: return -> first-frame latency attribution (dense sampling).
# Modeled on ../tools/run_pp_round.sh (PiliPlus phase2), differences:
#   * dense device-side sampler (tools/ff_sample.sh) running from just before the
#     return command for DENSE_DUR (~24 s): SF --latency + media_session every
#     iteration (~100-140 ms period), self-timestamped uptime+EPOCHREALTIME
#   * RETURN_CMD marker appended to the dense file right before `am start` return
#   * dumpsys media.codec probed but empty on this API24 build -> codec states
#     come from logcat MediaCodec/ACodec lines (per task fallback)
# usage: run_ff_round.sh <round_dir> <mode:dv|sdr> [home_wait]
# env: T_SEC=120 PRE_HOME_WAIT=32 HOME_WAIT=10 DENSE_DUR=24
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
DENSE_DUR=${DENSE_DUR:-24}
HERE=$(cd "$(dirname "$0")" && pwd)
DEV_OUT=/data/local/tmp/ff_dense.txt
mkdir -p "$ROUND_DIR"
EV="$ROUND_DIR/host-events.ndjson"
: > "$EV"
exec > >(tee "$ROUND_DIR/driver.log") 2>&1

hostms() { python3 -c 'import time;print(int(time.time()*1000))'; }
devms() { adb -s "$SER" shell 'echo $EPOCHREALTIME' | tr -d '\r' | awk '{printf "%d", $1*1000}'; }
ev() {
  local h; h=$(hostms); local d; d=$(devms)
  printf '{"event":"%s","host_ms":%s,"device_ms":%s,"note":"%s"}\n' "$1" "$h" "$d" "${2:-}" >> "$EV"
  echo "[$(date +%H:%M:%S)] $1 host_ms=$h device_ms=$d ${2:-}"
}
pid() { adb -s "$SER" shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true; }
screen() { adb -s "$SER" shell dumpsys power | grep -E "Display Power: state|mWakefulness=" | tr -d '\r'; adb -s "$SER" shell dumpsys window 2>/dev/null | grep -oE "mCurrentFocus=Window\{[^}]*\}" | head -1 | tr -d '\r'; }
sample() { # sparse bundle (same as phase2 rounds, for comparability)
  local lbl=$1 h d
  h=$(hostms); d=$(devms)
  adb -s "$SER" shell "dumpsys media_session" 2>/dev/null | sed -n '/media-session '"$PKG"'/,/queueTitle/p' > "$ROUND_DIR/sample-$lbl-mediasession.txt" || true
  adb -s "$SER" shell "dumpsys SurfaceFlinger --latency '$LAYER'" > "$ROUND_DIR/sample-$lbl-sflatency.txt" 2>&1 || true
  local p; p=$(pid)
  if [[ -n "$p" ]]; then
    adb -s "$SER" shell "for t in \$(ls /proc/$p/task); do cat /proc/$p/task/\$t/stat 2>/dev/null | cut -d' ' -f1,2,14,15; done" > "$ROUND_DIR/sample-$lbl-threads.txt" 2>/dev/null || true
  fi
  printf '{"event":"sample","label":"%s","host_ms":%s,"device_ms":%s,"pid":"%s"}\n' "$lbl" "$h" "$d" "${p:-}" >> "$EV"
  echo "[$(date +%H:%M:%S)] sample $lbl host_ms=$h device_ms=$d pid=${p:-}"
}
shot() { adb -s "$SER" exec-out screencap -p > "$ROUND_DIR/$1.png" 2>/dev/null && ev screenshot "$1 bytes=$(wc -c < "$ROUND_DIR/$1.png" | tr -d ' ')"; }
dense_start() { # dense_start <dur_s>
  adb -s "$SER" shell "rm -f $DEV_OUT"
  adb -s "$SER" shell "nohup sh $HERE_DEV/ff_sample.sh $DEV_OUT '$LAYER' $1 >/dev/null 2>&1 &" || true
  ev dense_sampler_started "dur=$1 out=$DEV_OUT"
}

# push device sampler (idempotent)
HERE_DEV=/data/local/tmp/ffattr
adb -s "$SER" shell "mkdir -p $HERE_DEV"
adb -s "$SER" push "$HERE/ff_sample.sh" "$HERE_DEV/ff_sample.sh" >/dev/null

ev round_begin "mode=$MODE pkg=$PKG dv_url=$DV_URL pre_home_wait=$PRE_HOME_WAIT home_wait=$HOME_WAIT dense_dur=$DENSE_DUR"
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

sleep $(( PRE_HOME_WAIT - 8 ))
sample pre_home_1
PID_BEFORE=$(pid)
ev pid_before "pid=$PID_BEFORE"
adb -s "$SER" exec-out logcat -d -v threadtime -b all > "$ROUND_DIR/logcat-pre-home.txt"
ev interim_dump "lines=$(wc -l < "$ROUND_DIR/logcat-pre-home.txt")"
echo "--- pre-HOME hwdec evidence ---"
grep -E "class=dvP84|mkst_create_decoder_window exit|MediaCodec create|makeComponentInstance|Now Executing" "$ROUND_DIR/logcat-pre-home.txt" | cut -c1-190 | tail -6 || true

# HOME
ev home_send_begin "cmd=input keyevent KEYCODE_HOME"
adb -s "$SER" shell input keyevent KEYCODE_HOME
ev home_sent
sleep 4
sample during_home_1
sleep $(( HOME_WAIT - 4 - 3 ))
sample during_home_2
ev home_dwell_done "home_wait=$HOME_WAIT"

# dense sampling window: start ~1 s before return command, run DENSE_DUR
dense_start "$DENSE_DUR"
sleep 1
adb -s "$SER" shell "printf 'RETURN_CMD|%s|%s\n' \"\$(cat /proc/uptime)\" \"\$EPOCHREALTIME\" >> $DEV_OUT"
ev return_cmd_marker "appended to $DEV_OUT"
ev return_send_begin "cmd=am start -n $ACT"
adb -s "$SER" shell am start -n "$ACT" | tr -d '\r' | tee "$ROUND_DIR/return-output.txt" >/dev/null
ev return_sent

# wait for dense sampler to finish (it started ~1 s before return)
sleep $(( DENSE_DUR ))
adb -s "$SER" pull "$DEV_OUT" "$ROUND_DIR/dense-samples.txt" >/dev/null
adb -s "$SER" shell "rm -f $DEV_OUT"
ev dense_pulled "lines=$(wc -l < "$ROUND_DIR/dense-samples.txt" | tr -d ' ')"

sample post_return_late
shot after-return
PID_AFTER=$(pid)
ev pid_after "pid_before=$PID_BEFORE pid_after=$PID_AFTER"
adb -s "$SER" shell dumpsys window 2>/dev/null | grep -E "mCurrentFocus|mFocusedApp" | tr -d '\r' | head -2 | tee "$ROUND_DIR/focus-after.txt"
screen | tee "$ROUND_DIR/screen-after.txt"
adb -s "$SER" exec-out logcat -d -v threadtime -b all > "$ROUND_DIR/logcat-full.txt"
ev full_dump "lines=$(wc -l < "$ROUND_DIR/logcat-full.txt")"
DROPBOX_AFTER=$(adb -s "$SER" shell dumpsys dropbox 2>/dev/null | grep -cE "data_app_crash|data_app_anr|data_app_native_crash|SYSTEM_TOMBSTONE" | tr -d '\r' || true)
ev dropbox_after "crash_entries_before=$DROPBOX_BEFORE after=$DROPBOX_AFTER"
echo "--- post-return key lines ---"
grep -E "MKS-HOME-TRACE.*(authorize|ensure_init\(lc_verify\) exit|create_decoder_window (enter|exit)|mkst_shutdown|surfaceCreated|surfaceDestroyed)|class=dvP84|MediaCodec create|makeComponentInstance|Now Executing|FATAL|ANR in" "$ROUND_DIR/logcat-full.txt" | cut -c1-210 | tail -40 || true
ev round_end
