#!/usr/bin/env bash
# P0 HOME-return trace round driver (LG H870DS). Records host+device time for
# every command it issues. Never touches system settings/sysprops.
#
# usage: run_round.sh <round_dir> <launch: fresh|continue> <home: normal|fast> [pkg] [activity] [tap_x tap_y]
set -Eeuo pipefail
ROUND_DIR=$1; LAUNCH=$2; HOME_MODE=$3
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

ev round_begin "launch=$LAUNCH home=$HOME_MODE pkg=$PKG"
screen | tee "$ROUND_DIR/screen-before.txt"

if [[ "$LAUNCH" == fresh ]]; then
  adb -s "$S" shell am force-stop "$PKG"; sleep 1
  ev force_stop "pid_after=$(pid)"
  adb -s "$S" logcat -c -b main -b system -b crash -b events -b radio -b kernel
  ev logcat_cleared
  if [[ -n "${LAUNCH_CMD:-}" ]]; then
    adb -s "$S" shell $LAUNCH_CMD | tr -d '\r' | tee "$ROUND_DIR/launch-output.txt"
    ev am_start_fresh "pid=$(pid) cmd=$LAUNCH_CMD"
  else
    adb -s "$S" shell am start -n "$ACT" | tr -d '\r' | tee "$ROUND_DIR/launch-output.txt"
    ev am_start_fresh "pid=$(pid)"
  fi
  sleep 4
  if [[ "${NO_TAP:-0}" != 1 ]]; then
    adb -s "$S" shell input tap "$TAP_X" "$TAP_Y"
    ev tap_open "x=$TAP_X y=$TAP_Y"
  fi
  sleep "${PRE_HOME_WAIT:-16}"
  adb -s "$S" exec-out logcat -d -v threadtime -b all > "$ROUND_DIR/logcat-pre-home.txt"
  ev interim_dump "lines=$(wc -l < "$ROUND_DIR/logcat-pre-home.txt")"
  echo "--- pre-HOME hwdec evidence (last MKSURF/hwdec lines) ---"
  grep -E "MKSURF|hwdec|yuv420p10|surfacetexture|VO: \[" "$ROUND_DIR/logcat-pre-home.txt" | tail -12 || true
else
  adb -s "$S" logcat -c -b main -b system -b crash -b events -b radio -b kernel
  ev logcat_cleared "pid=$(pid)"
fi

PID_BEFORE=$(pid)
ev pid_before "pid=$PID_BEFORE"

if [[ "$HOME_MODE" == normal ]]; then
  ev home_send_begin
  adb -s "$S" shell input keyevent KEYCODE_HOME
  ev home_sent
  sleep 10
  ev return_send_begin "cmd=am start -n $ACT"
  adb -s "$S" shell am start -n "$ACT" | tr -d '\r' | tee "$ROUND_DIR/return-output.txt"
  ev return_sent
  sleep 20
else
  ev home_send_begin
  adb -s "$S" shell input keyevent KEYCODE_HOME
  ev home_sent
  ev return_send_begin "cmd=am start -n $ACT (immediately)"
  adb -s "$S" shell am start -n "$ACT" | tr -d '\r' | tee "$ROUND_DIR/return-output.txt"
  ev return_sent
  sleep 12
fi

PID_AFTER=$(pid)
ev pid_after "pid_before=$PID_BEFORE pid_after=$PID_AFTER"
adb -s "$S" shell dumpsys window | grep -E "mCurrentFocus|mFocusedApp" | tr -d '\r' | tee "$ROUND_DIR/focus-after.txt"
screen | tee "$ROUND_DIR/screen-after.txt"
adb -s "$S" exec-out logcat -d -v threadtime -b all > "$ROUND_DIR/logcat-full.txt"
ev full_dump "lines=$(wc -l < "$ROUND_DIR/logcat-full.txt")"
echo "--- post-return key lines ---"
grep -E "MKS-HOME-TRACE|MKSURF|bridge not initialized|yuv420p10|hwdec" "$ROUND_DIR/logcat-full.txt" | grep -vE "latch-timeout-diag" | tail -40 || true
ev round_end
