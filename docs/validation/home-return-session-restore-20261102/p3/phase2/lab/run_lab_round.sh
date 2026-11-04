#!/usr/bin/env bash
# P3 phase2 (b) Lab matrix round driver (LG H870DS). Derived from p0-trace/run_round.sh,
# run_round_fast.sh and p3/phase1/smoke-prefix/run_round_smoke.sh. Differences:
#   * per-buffer logcat clear (main system crash events radio kernel) in every mode
#   * modes: normal | fast | pause | openhome
#   * optional SF dump (SF_DUMP=1) taken during pre-HOME playback and after return
#   * optional key events (PRE_HOME_KEY, RESUME_KEY) for the resume-method trial
#   * dropbox crash listing after the round
# Never touches system settings/sysprops. Records host+device time for every command.
#
# usage: run_lab_round.sh <round_dir> <mode> [pkg] [activity] [tap_x] [tap_y]
#   normal   : cold start -> tap -> PRE_HOME_WAIT -> keyevent HOME -> 10 s -> am start -> POST_WAIT
#   fast     : cold start -> tap -> PRE_HOME_WAIT -> ONE adb shell: 'am start HOME --activity-no-animation;
#              am start ACT --activity-no-animation' (p0 method F, sleep 0) -> POST_WAIT
#   pause    : normal, but sends PRE_HOME_KEY (default KEYCODE_MEDIA_PAUSE) PRE_HOME_KEY_LEAD s before HOME
#              and RESUME_KEY (default KEYCODE_MEDIA_PLAY) RESUME_DELAY s after return
#   openhome : cold start -> tap -> OPEN_HOME_DELAY (default 0.5 s) -> keyevent HOME -> 10 s -> am start -> POST_WAIT
# env: PRE_HOME_WAIT=20 POST_WAIT=22 SF_DUMP=0 OPEN_HOME_DELAY=0.5 PRE_HOME_KEY= PRE_HOME_KEY_LEAD=3 RESUME_KEY= RESUME_DELAY=5
set -Eeuo pipefail
ROUND_DIR=$1; MODE=$2
PKG=${3:-com.example.media_kit_hdr_lab}
ACT=${4:-$PKG/.MainActivity}
TAP_X=${5:-1440}; TAP_Y=${6:-720}
S=LGH870DS42e27764
PRE_HOME_WAIT=${PRE_HOME_WAIT:-20}
POST_WAIT=${POST_WAIT:-22}
SF_DUMP=${SF_DUMP:-0}
OPEN_HOME_DELAY=${OPEN_HOME_DELAY:-0.5}
PRE_HOME_KEY=${PRE_HOME_KEY:-}
PRE_HOME_KEY_LEAD=${PRE_HOME_KEY_LEAD:-3}
RESUME_KEY=${RESUME_KEY:-}
RESUME_DELAY=${RESUME_DELAY:-5}
mkdir -p "$ROUND_DIR"
EV="$ROUND_DIR/host-events.ndjson"
: > "$EV"

hostms() { python3 -c 'import time;print(int(time.time()*1000))'; }
devms() { adb -s "$S" shell 'echo $EPOCHREALTIME' | tr -d '\r' | awk '{printf "%d", $1*1000}'; }
ev() { # ev <event> [note]
  local h; h=$(hostms); local d; d=$(devms)
  printf '{"event":"%s","host_ms":%s,"device_ms":%s,"note":"%s"}\n' "$1" "$h" "$d" "${2:-}" >> "$EV"
  echo "[$(date +%H:%M:%S)] $1 host_ms=$h device_ms=$d ${2:-}"
}
pid() { adb -s "$S" shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true; }
screen() { adb -s "$S" shell dumpsys power | grep -E "Display Power: state|mWakefulness=" | tr -d '\r'; adb -s "$S" shell dumpsys window | grep -oE "isStatusBarKeyguard=(true|false)|mShowingLockscreen=(true|false)" | tr -d '\r' | sort -u; }
sfdump() { adb -s "$S" shell dumpsys SurfaceFlinger > "$ROUND_DIR/$1" 2>&1 || true; ev sf_dump "$1 lines=$(wc -l < "$ROUND_DIR/$1")"; }

ev round_begin "mode=$MODE pkg=$PKG pre_home_wait=$PRE_HOME_WAIT post_wait=$POST_WAIT sf_dump=$SF_DUMP open_home_delay=$OPEN_HOME_DELAY pre_home_key=$PRE_HOME_KEY resume_key=$RESUME_KEY"
screen | tee "$ROUND_DIR/screen-before.txt"
DROPBOX_BEFORE=$(adb -s "$S" shell dumpsys dropbox 2>/dev/null | grep -cE "data_app_crash|data_app_anr|data_app_native_crash|SYSTEM_TOMBSTONE" | tr -d '\r' || true)
ev dropbox_before "crash_entries=$DROPBOX_BEFORE"

adb -s "$S" shell am force-stop "$PKG"; sleep 1
ev force_stop "pid_after=$(pid)"
for b in main system crash events radio kernel; do
  if adb -s "$S" logcat -c -b "$b"; then echo "logcat -c -b $b rc=0"; else echo "logcat -c -b $b rc=$?"; fi
done
ev logcat_cleared "per-buffer"
adb -s "$S" shell am start -n "$ACT" | tr -d '\r' | tee "$ROUND_DIR/launch-output.txt"
ev am_start_fresh "pid=$(pid)"
sleep 4
adb -s "$S" shell input tap "$TAP_X" "$TAP_Y"
ev tap_open "x=$TAP_X y=$TAP_Y"

if [[ "$MODE" == openhome ]]; then
  sleep "$OPEN_HOME_DELAY"
  ev openhome_delay_done "delay=$OPEN_HOME_DELAY"
else
  if [[ "$MODE" == pause && -n "$PRE_HOME_KEY" ]]; then
    sleep $(( PRE_HOME_WAIT - PRE_HOME_KEY_LEAD ))
    ev pre_home_key_begin "key=$PRE_HOME_KEY"
    adb -s "$S" shell input keyevent "$PRE_HOME_KEY"
    ev pre_home_key_sent "key=$PRE_HOME_KEY"
    sleep "$PRE_HOME_KEY_LEAD"
  else
    sleep "$PRE_HOME_WAIT"
  fi
  if [[ "$SF_DUMP" == 1 ]]; then sfdump sf-pre-home.txt; fi
  adb -s "$S" exec-out logcat -d -v threadtime -b all > "$ROUND_DIR/logcat-pre-home.txt"
  ev interim_dump "lines=$(wc -l < "$ROUND_DIR/logcat-pre-home.txt")"
  echo "--- pre-HOME hwdec evidence ---"
  grep -E "hwdecCurrent=|mkst_create_decoder_window exit|active-importer|PERF t=[0-9]+ (time-pos|pause)=" "$ROUND_DIR/logcat-pre-home.txt" | cut -c1-200 | tail -10 || true
fi

PID_BEFORE=$(pid)
ev pid_before "pid=$PID_BEFORE"

if [[ "$MODE" == fast ]]; then
  INNER="am start -a android.intent.action.MAIN -c android.intent.category.HOME --activity-no-animation; am start -n $ACT --activity-no-animation"
  ev home_send_begin "cmd=adb shell: $INNER"
  adb -s "$S" shell "$INNER" 2>&1 | tr -d '\r' | tee "$ROUND_DIR/return-output.txt"
  ev home_sent "chained home+return shell returned"
  ev return_send_begin "note-only: return was chained in the same shell as home (method F, sleep 0)"
  ev return_sent "chained shell done"
else
  ev home_send_begin
  adb -s "$S" shell input keyevent KEYCODE_HOME
  ev home_sent
  sleep 10
  ev return_send_begin "cmd=am start -n $ACT"
  adb -s "$S" shell am start -n "$ACT" | tr -d '\r' | tee "$ROUND_DIR/return-output.txt"
  ev return_sent
fi

if [[ -n "$RESUME_KEY" ]]; then
  sleep "$RESUME_DELAY"
  ev resume_key_begin "key=$RESUME_KEY"
  adb -s "$S" shell input keyevent "$RESUME_KEY"
  ev resume_key_sent "key=$RESUME_KEY"
  sleep $(( POST_WAIT - RESUME_DELAY ))
else
  sleep "$POST_WAIT"
fi

PID_AFTER=$(pid)
ev pid_after "pid_before=$PID_BEFORE pid_after=$PID_AFTER"
if [[ "$SF_DUMP" == 1 ]]; then sfdump sf-post-return.txt; fi
adb -s "$S" shell dumpsys window | grep -E "mCurrentFocus|mFocusedApp" | tr -d '\r' | tee "$ROUND_DIR/focus-after.txt"
screen | tee "$ROUND_DIR/screen-after.txt"
adb -s "$S" exec-out logcat -d -v threadtime -b all > "$ROUND_DIR/logcat-full.txt"
ev full_dump "lines=$(wc -l < "$ROUND_DIR/logcat-full.txt")"
DROPBOX_AFTER=$(adb -s "$S" shell dumpsys dropbox 2>/dev/null | grep -cE "data_app_crash|data_app_anr|data_app_native_crash|SYSTEM_TOMBSTONE" | tr -d '\r' || true)
ev dropbox_after "crash_entries_before=$DROPBOX_BEFORE after=$DROPBOX_AFTER"
echo "--- post-return key lines ---"
grep -E "MKS-HOME-TRACE.*(authorize|ensure_init\(lc_verify\) exit|create_decoder_window exit)|bridge not initialized|yuv420p10|hwdecCurrent=|active-importer|PERF t=[0-9]+ (time-pos|pause)=|BridgeActivationIssue|FATAL|ANR in" "$ROUND_DIR/logcat-full.txt" | cut -c1-220 | tail -30 || true
ev round_end
