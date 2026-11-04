#!/usr/bin/env bash
# ff-attr BASE round: in-app reference costs, no HOME (decoder stays alive).
#  phase A pause_resume: media dispatch play-pause -> pause 3 s -> play-pause
#           -> dense-sample to first new SF present after resume
#  phase B seek: seekbar micro-drag (+/- a few s; actual delta recorded from
#           media_session position) -> dense-sample to first new SF present
#           If drag ineffective (>20 s or 0 s), retry once with media dispatch
#           fast-forword (typo'd key name on this build).
# usage: run_ff_base.sh <round_dir>
# env: T_SEC=120 PRE_HOME_WAIT=32 DENSE_DUR=16
set -Eeuo pipefail
ROUND_DIR=$1
SER=LGH870DS42e27764
PKG=com.example.piliplus.dev
ACT=$PKG/com.example.piliplus.MainActivity
DV_URL="https://www.bilibili.com/video/BV1vY4y1N7TY?t=${T_SEC:-120}"
LAYER="SurfaceView - $ACT"
T_SEC=${T_SEC:-120}
PRE_HOME_WAIT=${PRE_HOME_WAIT:-32}
DENSE_DUR=${DENSE_DUR:-16}
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
state() { adb -s "$SER" shell "dumpsys media_session" 2>/dev/null | sed -n '/media-session '"$PKG"'/,/queueTitle/p' | grep -oE 'state=[0-9]+, position=[0-9]+' | head -1 | tr -d '\r'; }
sample() {
  local lbl=$1 h d
  h=$(hostms); d=$(devms)
  adb -s "$SER" shell "dumpsys media_session" 2>/dev/null | sed -n '/media-session '"$PKG"'/,/queueTitle/p' > "$ROUND_DIR/sample-$lbl-mediasession.txt" || true
  adb -s "$SER" shell "dumpsys SurfaceFlinger --latency '$LAYER'" > "$ROUND_DIR/sample-$lbl-sflatency.txt" 2>&1 || true
  printf '{"event":"sample","label":"%s","host_ms":%s,"device_ms":%s,"pid":"%s"}\n' "$lbl" "$h" "$d" "$(pid)" >> "$EV"
  echo "[$(date +%H:%M:%S)] sample $lbl $(cat "$ROUND_DIR/sample-$lbl-mediasession.txt" | grep -oE 'state=[0-9]+, position=[0-9]+' | head -1)"
}
shot() { adb -s "$SER" exec-out screencap -p > "$ROUND_DIR/$1.png" 2>/dev/null && ev screenshot "$1 bytes=$(wc -c < "$ROUND_DIR/$1.png" | tr -d ' ')"; }
dense_start() {
  adb -s "$SER" shell "rm -f $DEV_OUT"
  adb -s "$SER" shell "nohup sh /data/local/tmp/ffattr/ff_sample.sh $DEV_OUT '$LAYER' $1 >/dev/null 2>&1 &" || true
  ev dense_sampler_started "dur=$1 out=$DEV_OUT"
}
dense_pull() {
  sleep "$1"
  adb -s "$SER" pull "$DEV_OUT" "$ROUND_DIR/$2" >/dev/null
  adb -s "$SER" shell "rm -f $DEV_OUT"
  ev dense_pulled "file=$2 lines=$(wc -l < "$ROUND_DIR/$2" | tr -d ' ')"
}
marker() { adb -s "$SER" shell "printf '%s|%s|%s\n' '$1' \"\$(cat /proc/uptime)\" \"\$EPOCHREALTIME\" >> $DEV_OUT"; ev marker "$1"; }

adb -s "$SER" shell "mkdir -p /data/local/tmp/ffattr"
adb -s "$SER" push "$HERE/ff_sample.sh" /data/local/tmp/ffattr/ff_sample.sh >/dev/null

ev round_begin "mode=base dv_url=$DV_URL pre_home_wait=$PRE_HOME_WAIT dense_dur=$DENSE_DUR"
adb -s "$SER" shell am force-stop "$PKG"; sleep 1
for b in main system crash events radio kernel; do adb -s "$SER" logcat -c -b "$b" >/dev/null 2>&1 || true; done
ev logcat_cleared "per-buffer"
adb -s "$SER" shell am start -a android.intent.action.VIEW -d "$DV_URL" -p "$PKG" | tr -d '\r' | tee "$ROUND_DIR/launch-output.txt" >/dev/null
ev am_start_deeplink "pid=$(pid)"
sleep 8
sample play_start
shot after-launch
sleep $(( PRE_HOME_WAIT - 8 ))
sample pre_phase
PID_BEFORE=$(pid)
ev pid_before "pid=$PID_BEFORE"
echo "state now: $(state)"
adb -s "$SER" exec-out logcat -d -v threadtime -b all > "$ROUND_DIR/logcat-pre-phase.txt"

### Phase A: pause -> 3 s -> resume
dense_start "$DENSE_DUR"
sleep 1
sample a_playing
marker A_PAUSE_CMD
adb -s "$SER" shell media dispatch play-pause
ev a_pause_sent "media dispatch play-pause"
sleep 3
sample a_paused
marker A_RESUME_CMD
adb -s "$SER" shell media dispatch play-pause
ev a_resume_sent "media dispatch play-pause"
dense_pull "$(( DENSE_DUR - 4 ))" dense-a.txt
sample a_after

### Phase B: in-place seek
sleep 3
sample b_pre_seek
dense_start "$DENSE_DUR"
sleep 1
marker B_SEEK_CMD
# portrait detail page: seekbar near y~786 (fullscreen button at (1348,793) in PP-S1)
adb -s "$SER" shell input swipe 720 786 745 786 250
ev b_seek_drag "swipe 720,786 -> 745,786 (250 ms)"
sleep "$(( DENSE_DUR - 2 ))"
adb -s "$SER" pull "$DEV_OUT" "$ROUND_DIR/dense-b.txt" >/dev/null
adb -s "$SER" shell "rm -f $DEV_OUT"
ev dense_pulled "file=dense-b.txt lines=$(wc -l < "$ROUND_DIR/dense-b.txt" | tr -d ' ')"
sample b_after
STATE_B=$(state)
echo "post-seek state: $STATE_B"

PID_AFTER=$(pid)
ev pid_after "pid_before=$PID_BEFORE pid_after=$PID_AFTER"
adb -s "$SER" exec-out logcat -d -v threadtime -b all > "$ROUND_DIR/logcat-full.txt"
ev full_dump "lines=$(wc -l < "$ROUND_DIR/logcat-full.txt")"
echo "--- BASE control lines (expect NONE in phase window) ---"
grep -E "MKS-HOME-TRACE.*(authorize begin|authorize result|create_decoder_window|mkst_shutdown|surfaceCreated|surfaceDestroyed)|makeComponentInstance|Now Executing|MediaCodec create" "$ROUND_DIR/logcat-full.txt" | cut -c1-210 | tail -30 || true
ev round_end
