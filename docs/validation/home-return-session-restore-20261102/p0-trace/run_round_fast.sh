#!/usr/bin/env bash
# R4 fast HOME-return trace round driver (LG H870DS). Same protocol as run_round.sh
# (cold start -> tap -> play -> HOME -> return -> observe -> dump), but the HOME and
# return commands are chained inside ONE `adb shell` invocation to remove the adb
# round-trip between them. Records host+device time for every command it issues.
# Never touches system settings/sysprops.
#
# usage: run_round_fast.sh <round_dir> <method:A|B|C|D> [sleep_sec] [pkg] [activity] [tap_x] [tap_y]
#   A: adb shell 'input keyevent KEYCODE_HOME; am start -n <ACT>'
#   B: adb shell 'input keyevent KEYCODE_HOME; sleep <sleep_sec>; am start -n <ACT>'
#   C: adb shell 'am start -a android.intent.action.MAIN -c android.intent.category.HOME; am start -n <ACT>'
#   D: adb shell 'am start -a android.intent.action.MAIN -c android.intent.category.HOME; sleep <sleep_sec>; am start -n <ACT>'
#   E: A + --activity-no-animation on the return am start
#   F: C + --activity-no-animation on BOTH am starts (inserts 'sleep <sleep_sec>' between them when sleep_sec > 0)
#   G: A + --activity-no-animation --activity-single-top on the return am start
set -Eeuo pipefail
ROUND_DIR=$1; METHOD=$2
SLEEP=${3:-0}
PKG=${4:-com.example.media_kit_hdr_lab}
ACT=${5:-$PKG/.MainActivity}
TAP_X=${6:-1440}; TAP_Y=${7:-720}
S=LGH870DS42e27764
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
screen() { adb -s "$S" shell dumpsys power | grep -E "Display Power: state" | tr -d '\r'; adb -s "$S" shell dumpsys window | grep -oE "isStatusBarKeyguard=(true|false)" | tr -d '\r'; }

case "$METHOD" in
  A) INNER="input keyevent KEYCODE_HOME; am start -n $ACT" ;;
  B) INNER="input keyevent KEYCODE_HOME; sleep $SLEEP; am start -n $ACT" ;;
  C) INNER="am start -a android.intent.action.MAIN -c android.intent.category.HOME; am start -n $ACT" ;;
  D) INNER="am start -a android.intent.action.MAIN -c android.intent.category.HOME; sleep $SLEEP; am start -n $ACT" ;;
  E) INNER="input keyevent KEYCODE_HOME; am start -n $ACT --activity-no-animation" ;;
  F) MID=""; [[ "$SLEEP" != "0" ]] && MID="sleep $SLEEP; "
     INNER="am start -a android.intent.action.MAIN -c android.intent.category.HOME --activity-no-animation; ${MID}am start -n $ACT --activity-no-animation" ;;
  G) INNER="input keyevent KEYCODE_HOME; am start -n $ACT --activity-no-animation --activity-single-top" ;;
  *) echo "unknown method $METHOD" >&2; exit 2 ;;
esac

ev round_begin "launch=fresh method=$METHOD sleep=$SLEEP pkg=$PKG"
screen | tee "$ROUND_DIR/screen-before.txt"

adb -s "$S" shell am force-stop "$PKG"; sleep 1
ev force_stop "pid_after=$(pid)"
adb -s "$S" logcat -c -b main -b system -b crash -b events -b radio -b kernel
ev logcat_cleared
adb -s "$S" shell am start -n "$ACT" | tr -d '\r' | tee "$ROUND_DIR/launch-output.txt"
ev am_start_fresh "pid=$(pid)"
sleep 4
adb -s "$S" shell input tap "$TAP_X" "$TAP_Y"
ev tap_open "x=$TAP_X y=$TAP_Y"
sleep "${PRE_HOME_WAIT:-16}"
adb -s "$S" exec-out logcat -d -v threadtime -b all > "$ROUND_DIR/logcat-pre-home.txt"
ev interim_dump "lines=$(wc -l < "$ROUND_DIR/logcat-pre-home.txt")"
echo "--- pre-HOME hwdec evidence (last MKSURF/hwdec lines) ---"
grep -E "MKSURF create ok|MKSURF|hwdec|surfacetexture|HDR_SESSION_REPORT" "$ROUND_DIR/logcat-pre-home.txt" | tail -8 || true

PID_BEFORE=$(pid)
ev pid_before "pid=$PID_BEFORE"

ev home_send_begin "cmd=adb shell: $INNER"
adb -s "$S" shell "$INNER" 2>&1 | tr -d '\r' | tee "$ROUND_DIR/return-output.txt"
ev home_sent "chained home+return shell returned"
ev return_send_begin "note-only: return was chained in the same shell as home (no separate adb round trip)"
ev return_sent "chained shell done"
sleep 12

PID_AFTER=$(pid)
ev pid_after "pid_before=$PID_BEFORE pid_after=$PID_AFTER"
adb -s "$S" shell dumpsys window | grep -E "mCurrentFocus|mFocusedApp" | tr -d '\r' | tee "$ROUND_DIR/focus-after.txt"
screen | tee "$ROUND_DIR/screen-after.txt"
adb -s "$S" exec-out logcat -d -v threadtime -b all > "$ROUND_DIR/logcat-full.txt"
ev full_dump "lines=$(wc -l < "$ROUND_DIR/logcat-full.txt")"
echo "--- post-return key lines ---"
grep -E "MKS-HOME-TRACE|MKSURF|bridge not initialized|yuv420p10|hwdec" "$ROUND_DIR/logcat-full.txt" | grep -vE "latch-timeout-diag" | tail -40 || true
ev round_end
