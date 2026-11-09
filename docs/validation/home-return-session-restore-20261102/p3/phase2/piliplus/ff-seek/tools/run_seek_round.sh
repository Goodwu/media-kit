#!/usr/bin/env bash
# ff-seek round driver: stable play -> UI seekbar drag -> dense SF/media_session
# sampling around the seek; measures seek -> first new video frame.
# Reuses ff-attr dense sampler (ff_sample.sh) and host/device dual timestamps.
# usage: run_seek_round.sh <round_dir> <mode:dv|dv430|sdr|eof> <delta_s>
#   dv    : deep link BV1vY4y1N7TY?t=120, seek by <delta_s> (signed)
#   dv430 : deep link ?t=430 (for -5min backward), seek by <delta_s>
#   sdr   : cold start + tap first feed card, seek by <delta_s>
#   eof   : deep link ?t=120, seek to absolute TARGET_T (default 1195 s)
# env: PRE_WAIT=40 DENSE_DUR=26 T_SEC=120 TARGET_T=1195 SWIPE_MS=600
# Seekbar geometry (SK-PROBE calibration, portrait detail page):
#   y=900, x(t) = X0 + K*t, X0=14, K=1.1917 px/s, duration 1200 s (DV source).
#   SDR source duration unknown -> probed at runtime from overlay screenshot;
#   for sdr mode the drag is RELATIVE: x2 = x1 + delta/dur*(1440-2*X0).
set -Eeuo pipefail
ROUND_DIR=$1; MODE=$2; DELTA=${3:-0}
SER=LGH870DS42e27764
PKG=com.example.piliplus.dev
ACT=$PKG/com.example.piliplus.MainActivity
DV_URL="https://www.bilibili.com/video/BV1vY4y1N7TY?t=${T_SEC:-120}"
LAYER="SurfaceView - $ACT"
X0=14; K=1.1917
PRE_WAIT=${PRE_WAIT:-40}
DENSE_DUR=${DENSE_DUR:-26}
TARGET_T=${TARGET_T:-1195}
SWIPE_MS=${SWIPE_MS:-600}
DEVROOT=/data/local/tmp/ffseek
DEV_OUT=$DEVROOT/dense.txt
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$ROUND_DIR"
EV="$ROUND_DIR/host-events.ndjson"
: > "$EV"
exec > >(tee "$ROUND_DIR/driver.log") 2>&1

hostms() { python3 -c 'import time;print(int(time.time()*1000))'; }
ev() { local h; h=$(hostms); local d; d=$(adb -s "$SER" shell 'echo $EPOCHREALTIME' | tr -d '\r' | awk '{printf "%d", $1*1000}'); printf '{"event":"%s","host_ms":%s,"device_ms":%s,"note":"%s"}\n' "$1" "$h" "$d" "${2:-}" >> "$EV"; echo "[$(date +%H:%M:%S)] $1 ${2:-}"; }
pid() { adb -s "$SER" shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true; }
state() { adb -s "$SER" shell "dumpsys media_session" 2>/dev/null | sed -n '/media-session '"$PKG"'/,/queueTitle/p' | grep -oE 'state=[0-9]+, position=[0-9]+, buffered position=[0-9]+, speed=[0-9.]+, updated=[0-9]+' | head -1 | tr -d '\r'; }
shot() { adb -s "$SER" exec-out screencap -p > "$ROUND_DIR/$1.png" 2>/dev/null; }
overlay_time_shot() { # tap video (non-button area) to show controls, screenshot time text
  adb -s "$SER" shell input tap 200 250; sleep 0.7
  adb -s "$SER" exec-out screencap -p > "$ROUND_DIR/$1.png" 2>/dev/null
  python3 - "$ROUND_DIR/$1.png" "$ROUND_DIR/$1-time.png" <<'PY'
import sys
from PIL import Image
img = Image.open(sys.argv[1])
img.crop((900, 780, 1440, 895)).resize((810, 172)).save(sys.argv[2])
PY
}
overlay_hide_verify() { # toggle overlay OFF and verify bare seekbar (green fill at y=900)
  # overlay is toggle-on-tap and does NOT auto-hide; it covers the detail seekbar
  local ok=0 k
  for k in 1 2 3; do
    adb -s "$SER" shell input tap 200 250
    sleep 1.2
    adb -s "$SER" exec-out screencap -p > "$ROUND_DIR/seekbar-check.png" 2>/dev/null
    if python3 - "$ROUND_DIR/seekbar-check.png" <<'PY'
import sys
from PIL import Image
img = Image.open(sys.argv[1]); px = img.load()
green = [x for x in range(1440) if px[x,900][1] > 80 and px[x,900][0] < 40]
sys.exit(0 if green else 1)
PY
    then ok=1; ev overlay_hidden_verified "attempt#$k green_fill_x=$(python3 -c "
from PIL import Image
img = Image.open('$ROUND_DIR/seekbar-check.png'); px = img.load()
green = [x for x in range(1440) if px[x,900][1] > 80 and px[x,900][0] < 40]
print(max(green) if green else -1)")"; break; fi
    ev overlay_hide_retry "attempt#$k no green fill at y=900"
  done
  [[ "$ok" == "1" ]] || { ev overlay_hide_failed "seekbar not visible, abort"; echo "OVERLAY HIDE FAILED"; exit 4; }
}

adb -s "$SER" shell "mkdir -p $DEVROOT"
adb -s "$SER" push "$HERE/ff_sample.sh" $DEVROOT/ff_sample.sh >/dev/null

ev round_begin "mode=$MODE delta=$DELTA pre_wait=$PRE_WAIT dense_dur=$DENSE_DUR target_t=$TARGET_T"
adb -s "$SER" shell dumpsys power | grep -E "mWakefulness=|Display Power: state" | tr -d '\r' | tee "$ROUND_DIR/screen-before.txt"
DROPBOX_BEFORE=$(adb -s "$SER" shell dumpsys dropbox 2>/dev/null | grep -cE "data_app_crash|data_app_anr|data_app_native_crash|SYSTEM_TOMBSTONE" | tr -d '\r' || true)
ev dropbox_before "crash_entries=$DROPBOX_BEFORE"

adb -s "$SER" shell am force-stop "$PKG"; sleep 1
for b in main system crash events radio kernel; do adb -s "$SER" logcat -c -b "$b" >/dev/null 2>&1 || true; done
ev logcat_cleared per-buffer

if [[ "$MODE" == sdr ]]; then
  FEED_TAP_X=${FEED_TAP_X:-360}; FEED_TAP_Y=${FEED_TAP_Y:-800}
  adb -s "$SER" shell am start -n "$ACT" >/dev/null
  ev am_start_cold "pid=$(pid)"
  sleep 6; shot sdr-home-feed
  adb -s "$SER" shell input tap "$FEED_TAP_X" "$FEED_TAP_Y"
  ev tap_first_feed_card "x=$FEED_TAP_X y=$FEED_TAP_Y"
  sleep 6; shot sdr-video-opened
else
  adb -s "$SER" shell am start -a android.intent.action.VIEW -d "$DV_URL" -p "$PKG" >/dev/null
  ev am_start_deeplink "pid=$(pid) url=$DV_URL"
fi

sleep 8
ensure_portrait() { # fullscreen residue makes y=900 seekbar absent; exit via overlay back-arrow
  local k ok=0
  for k in 1 2 3; do
    adb -s "$SER" exec-out screencap -p > "$ROUND_DIR/layout-check.png" 2>/dev/null
    if python3 - "$ROUND_DIR/layout-check.png" <<'PY'
import sys
from PIL import Image
img = Image.open(sys.argv[1]); px = img.load()
# portrait detail page: white tab strip below video (y 990-1080); fullscreen: video there
w = [px[x,1030][:3] for x in range(200, 1300, 10)]
bright = sum(1 for c in w if sum(c) > 690)
sys.exit(0 if bright > 60 else 1)
PY
    then ok=1; ev portrait_verified "attempt#$k"; break; fi
    ev fullscreen_detected "attempt#$k exiting via overlay back-arrow"
    adb -s "$SER" shell input tap 720 1440; sleep 0.9   # ensure overlay ON
    adb -s $SER shell input tap 90 120; sleep 1.6        # back arrow -> detail page
  done
  [[ "$ok" == "1" ]] || { ev portrait_check_failed "abort"; echo "PORTRAIT CHECK FAILED"; exit 6; }
}
ensure_portrait
shot after-launch
sleep $(( PRE_WAIT - 8 ))
ST_PRE=$(state)
echo "state pre-seek: $ST_PRE"
ev state_pre "$ST_PRE"

# compute current position AFTER gate (fresh publish base): state + uptime one read
compute_pos() {
read -r POS_MS UP_MS UPDATED STATE <<< "$(adb -s "$SER" shell "dumpsys media_session; cat /proc/uptime" | tr -d '\r' | python3 -c "
import sys, re
txt = sys.stdin.read()
m = re.search(r'state=(\d+), position=(\d+), buffered position=\d+, speed=[\d.]+, updated=(\d+)', txt)
u = re.search(r'^(\d+)\.\d+', txt, re.M)
if not (m and u): sys.exit('no state/uptime')
print(m.group(2), int(u.group(1))*1000, m.group(3), m.group(1))
")"
POS_NOW_S=$(python3 -c "print(round(($POS_MS + ($UP_MS - $UPDATED))/1000.0, 1))")
echo "published pos=${POS_MS}ms updated=$UPDATED uptime=${UP_MS}ms -> pos_now=${POS_NOW_S}s state=$STATE"
ev pos_computed "published_ms=$POS_MS updated=$UPDATED uptime_ms=$UP_MS pos_now_s=$POS_NOW_S"
}
drag_coords() {
ADV_S=${ADV_S:-4}
if [[ "$MODE" == eof ]]; then
  X1=$(python3 -c "print(round($X0 + $K*($POS_NOW_S+$ADV_S)))")
  X2=$(python3 -c "print(round($X0 + $K*$TARGET_T))")
  TGT_S=$TARGET_T
elif [[ "$MODE" == sdr ]]; then
  X1=$(python3 -c "print(round($X0 + (1440-2*$X0)*($POS_NOW_S+$ADV_S)/$SDR_DUR_S))")
  X2=$(python3 -c "print(round($X0 + (1440-2*$X0)*($POS_NOW_S+$DELTA)/$SDR_DUR_S))")
  TGT_S=$(python3 -c "print(round($POS_NOW_S+$DELTA,1))")
else
  X1=$(python3 -c "print(round($X0 + $K*($POS_NOW_S+$ADV_S)))")
  X2=$(python3 -c "print(round($X0 + $K*($POS_NOW_S+$DELTA)))")
  TGT_S=$(python3 -c "print(round($POS_NOW_S+$DELTA,1))")
fi
echo "drag plan: x1=$X1 -> x2=$X2 y=900 ${SWIPE_MS}ms (pos_now=${POS_NOW_S}s target=${TGT_S}s)"
ev drag_plan "x1=$X1 x2=$X2 y=900 swipe_ms=$SWIPE_MS pos_now=${POS_NOW_S}s target=${TGT_S}s"
}

# stability gate: seek drags are no-ops while buffering/paused (SK-DV-2 lesson);
# require state=3 whose publish is >12 s old (not just-resumed), max 90 s wait
GATE_OK=0
for i in $(seq 1 90); do
  G=$(adb -s "$SER" shell "dumpsys media_session; cat /proc/uptime" | tr -d '\r' | python3 -c "
import sys, re
txt = sys.stdin.read()
m = re.search(r'state=(\d+), position=(\d+), buffered position=\d+, speed=[\d.]+, updated=(\d+)', txt)
u = re.search(r'^(\d+)\.(\d+)', txt, re.M)
if not (m and u): print('ERR'); sys.exit()
up = int(float(u.group(0))*1000); age = up - int(m.group(3))
ok = 1 if (m.group(1)=='3' and age > 12000) else 0
print(ok, m.group(1), age)" 2>/dev/null || echo "ERR")
  set -- $G
  if [[ "$1" == "1" ]]; then GATE_OK=1; ev stability_gate_passed "poll#$i state=$2 publish_age_ms=$3"; break; fi
  if [[ "$1" == "ERR" ]]; then echo "gate read error poll#$i"; fi
  sleep 1
done
if [[ "$GATE_OK" != "1" ]]; then
  ev stability_gate_failed "aborting round (no 12s-stable playing state in 90s)"
  echo "STABILITY GATE FAILED - aborting"; exit 3
fi

# overlay interactions AFTER gate: pre time shot, then hide overlay + verify
# bare seekbar (overlay is toggle, covers the detail seekbar at y=900)
overlay_time_shot pre-seek-time
overlay_hide_verify
# post-overlay state re-check: a stall/error during overlay taps kills the drag
ST_RECHECK=$(adb -s "$SER" shell "dumpsys media_session" 2>/dev/null | sed -n '/media-session '"$PKG"'/,/queueTitle/p' | grep -oE 'state=[0-9]+' | head -1 | tr -d '\r')
if [[ "$ST_RECHECK" != "state=3" ]]; then
  ev abort_state_changed_after_overlay "state=$ST_RECHECK (stall or player closed during overlay taps)"
  echo "ABORT: state=$ST_RECHECK after overlay interactions"; exit 5
fi
ev pre_drag_state_ok "$ST_RECHECK"

compute_pos
drag_coords
adb -s "$SER" shell "rm -f $DEV_OUT"
adb -s "$SER" shell "nohup sh $DEVROOT/ff_sample.sh $DEV_OUT '$LAYER' $DENSE_DUR >/dev/null 2>&1 &"
ev dense_sampler_started "dur=$DENSE_DUR"
sleep 1
adb -s "$SER" shell "printf 'SK_SEEK_CMD|%s|%s\n' \"\$(cat /proc/uptime)\" \"\$EPOCHREALTIME\" >> $DEV_OUT"
ev marker SK_SEEK_CMD
if [[ "$MODE" == rewind ]]; then
  # fallback small-seek path: media dispatch rewind (app maps it to ~+11.6s forward,
  # per ff-attr BASE1C; drag below ~60px threshold is a no-op on this build)
  adb -s "$SER" shell media dispatch rewind
  ev rewind_key_sent "media dispatch rewind (app-mapped small skip)"
else
  adb -s "$SER" shell input swipe "$X1" 900 "$X2" 900 "$SWIPE_MS"
  ev swipe_sent "x1=$X1 x2=$X2 dur=${SWIPE_MS}ms"
fi
sleep 1.4
overlay_time_shot post-seek-time
ev post_seek_time_shot

sleep $(( DENSE_DUR - 4 ))
adb -s "$SER" pull "$DEV_OUT" "$ROUND_DIR/dense-samples.txt" >/dev/null
adb -s "$SER" shell "rm -f $DEV_OUT"
ev dense_pulled "lines=$(wc -l < "$ROUND_DIR/dense-samples.txt" | tr -d ' ')"
shot post-stability
ST_POST=$(state)
echo "state post: $ST_POST"
ev state_post "$ST_POST"

PID_AFTER=$(pid)
ev pid_after "pid=$PID_AFTER"
adb -s "$SER" exec-out logcat -d -v threadtime -b all > "$ROUND_DIR/logcat-full.txt"
ev full_dump "lines=$(wc -l < "$ROUND_DIR/logcat-full.txt" | tr -d ' ')"
DROPBOX_AFTER=$(adb -s "$SER" shell dumpsys dropbox 2>/dev/null | grep -cE "data_app_crash|data_app_anr|data_app_native_crash|SYSTEM_TOMBSTONE" | tr -d '\r' || true)
ev dropbox_after "crash_entries_before=$DROPBOX_BEFORE after=$DROPBOX_AFTER"
echo "--- codec lines in round window ---"
grep -E "Now Flushing|Now Executing|port settings change|owns [0-9]/[0-9] input|makeComponentInstance|mkst_|authorize" "$ROUND_DIR/logcat-full.txt" | cut -c1-170 | head -25 || true
ev round_end
