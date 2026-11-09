#!/usr/bin/env bash
# ff-seek round driver v2: stable play -> video-area swipe-seek gesture ->
# dense SF/media_session sampling; measures seek-release -> first new frame.
# v1 lessons (SK-DV-2 attempts 1-4, kept as *-attempt[1-4] dirs):
#   - detail-page seekbar drag (y=900) is UNRELIABLE on this build (no-op in
#     fresh sessions; occasionally engages; sometimes flips fullscreen)
#   - drag is a no-op while buffering/paused; overlay (toggle, slow auto-hide)
#     covers the bar; fullscreen residue breaks y=900 assumptions
#   - RELIABLE seek primitive: horizontal swipe ON THE VIDEO (bilibili-style
#     swipe-seek gesture, y=400): delta ~ k * px * duration_s, k~0.05 s/(px*s)
#     (calibrated 2026-11-03: 800px*1.2s=46-66s, 1300px*3s=209-210s), shows a
#     "±MM:SS -> MM:SS / 20:00" UI that we screenshot as landing ground truth;
#     works during buffering; fires on release.
# usage: run_seek_round2.sh <round_dir> <mode:dv|dv430|sdr|eof|rewind> <delta_s>
#   dv/dv430: deep link t=120/t=430, gesture seek by delta_s (signed)
#   sdr     : cold start + tap first feed card, gesture seek by delta_s
#             (GEST_K may be re-exported after a per-video calibration swipe)
#   eof     : deep link t=120, gesture seek to absolute TARGET_T (default 1195)
#   rewind  : media dispatch rewind (app maps to ~+9-12s forward; SK-DV-1 path)
# env: PRE_WAIT=40 DENSE_DUR=30 TARGET_T=1195 GEST_K=0.05 GEST_PX=1300 Y=400
set -Eeuo pipefail
ROUND_DIR=$1; MODE=$2; DELTA=${3:-0}
SER=LGH870DS42e27764
PKG=com.example.piliplus.dev
ACT=$PKG/com.example.piliplus.MainActivity
DV_URL="https://www.bilibili.com/video/BV1vY4y1N7TY?t=${T_SEC:-120}"
LAYER="SurfaceView - $ACT"
PRE_WAIT=${PRE_WAIT:-40}
DENSE_DUR=${DENSE_DUR:-30}
TARGET_T=${TARGET_T:-1195}
GEST_K=${GEST_K:-0.05}
GEST_PX=${GEST_PX:-1300}
GY=${GY:-400}
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
seek_ui_shot() { # gesture UI "±MM:SS -> MM:SS / DDD" band (no tap, no UI disturbance)
  adb -s $SER exec-out screencap -p > "$ROUND_DIR/$1.png" 2>/dev/null
  python3 - "$ROUND_DIR/$1.png" "$ROUND_DIR/$1-band.png" <<'PY'
import sys
from PIL import Image
img = Image.open(sys.argv[1])
img.crop((0, 700, 1440, 980)).resize((1080, 210)).save(sys.argv[2])
PY
}

adb -s "$SER" shell "mkdir -p $DEVROOT"
adb -s "$SER" push "$HERE/ff_sample.sh" $DEVROOT/ff_sample.sh >/dev/null

ev round_begin "mode=$MODE delta=$DELTA pre_wait=$PRE_WAIT dense_dur=$DENSE_DUR target_t=$TARGET_T k=$GEST_K"
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

# fullscreen residue guard (attempt4 lesson): exit via overlay back-arrow
ensure_portrait() {
  local k ok=0
  for k in 1 2 3; do
    adb -s "$SER" exec-out screencap -p > "$ROUND_DIR/layout-check.png" 2>/dev/null
    if python3 - "$ROUND_DIR/layout-check.png" <<'PY'
import sys
from PIL import Image
img = Image.open(sys.argv[1]); px = img.load()
w = [px[x,1030][:3] for x in range(200, 1300, 10)]
bright = sum(1 for c in w if sum(c) > 690)
sys.exit(0 if bright > 60 else 1)
PY
    then ok=1; ev portrait_verified "attempt#$k"; break; fi
    ev fullscreen_detected "attempt#$k exiting via overlay back-arrow"
    adb -s "$SER" shell input tap 720 1440; sleep 0.9
    adb -s "$SER" shell input tap 90 120; sleep 1.6
  done
  [[ "$ok" == "1" ]] || { ev portrait_check_failed "abort"; echo "PORTRAIT CHECK FAILED"; exit 6; }
}
ensure_portrait
shot after-launch
sleep $(( PRE_WAIT - 8 ))
ST_PRE=$(state)
echo "state pre-seek: $ST_PRE"
ev state_pre "$ST_PRE"

# stability gate (attempt1 lesson): gesture works even in s6, but we require a
# settled playing base for the measurement; s3 with publish >12 s old
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
  sleep 1
done
[[ "$GATE_OK" == "1" ]] || { ev stability_gate_failed "abort"; exit 3; }

# position at gate pass (publish arithmetic; slider/gesture seeks do not publish)
read -r POS_MS UP_MS UPDATED STATE <<< "$(adb -s "$SER" shell "dumpsys media_session; cat /proc/uptime" | tr -d '\r' | python3 -c "
import sys, re
txt = sys.stdin.read()
m = re.search(r'state=(\d+), position=(\d+), buffered position=\d+, speed=[\d.]+, updated=(\d+)', txt)
u = re.search(r'^(\d+)\.\d+', txt, re.M)
if not (m and u): sys.exit('no state')
print(m.group(2), int(u.group(1))*1000, m.group(3), m.group(1))
")"
POS_NOW_S=$(python3 -c "print(round(($POS_MS + ($UP_MS - $UPDATED))/1000.0, 1))")
echo "published pos=${POS_MS}ms updated=$UPDATED uptime=${UP_MS}ms -> pos_now=${POS_NOW_S}s state=$STATE"
ev pos_computed "published_ms=$POS_MS updated=$UPDATED uptime_ms=$UP_MS pos_now_s=$POS_NOW_S"

# gesture plan
if [[ "$MODE" == eof ]]; then
  NEED_S=$(python3 -c "print($TARGET_T - $POS_NOW_S)")
else
  NEED_S=$DELTA
fi
GEST_DUR_MS=$(python3 -c "
need=$NEED_S; k=$GEST_K; px=$GEST_PX
d = abs(need)/(k*px)*1000
print(int(min(max(d, 400), 20000)))")
if python3 -c "exit(0 if $NEED_S >= 0 else 1)"; then XA=70; XB=$((70+GEST_PX)); DIRM=fwd; else XA=1370; XB=$((1370-GEST_PX)); DIRM=back; fi
echo "gesture plan: $DIRM ${GEST_PX}px over ${GEST_DUR_MS}ms (need ${NEED_S}s from pos ${POS_NOW_S}s, k=$GEST_K)"
ev gesture_plan "dir=$DIRM px=$GEST_PX dur_ms=$GEST_DUR_MS need_s=$NEED_S pos_now_s=$POS_NOW_S k=$GEST_K"

# dense sampling starts ~1s before the gesture
adb -s "$SER" shell "rm -f $DEV_OUT"
adb -s "$SER" shell "nohup sh $DEVROOT/ff_sample.sh $DEV_OUT '$LAYER' $DENSE_DUR >/dev/null 2>&1 &"
ev dense_sampler_started "dur=$DENSE_DUR"
sleep 1
adb -s "$SER" shell "printf 'SK_SEEK_CMD|%s|%s\n' \"\$(cat /proc/uptime)\" \"\$EPOCHREALTIME\" >> $DEV_OUT"
ev marker SK_SEEK_CMD
if [[ "$MODE" == rewind ]]; then
  adb -s "$SER" shell media dispatch rewind
  ev rewind_key_sent "media dispatch rewind (app-mapped small skip)"
  adb -s "$SER" shell "printf 'SK_SEEK_RELEASE|%s|%s\n' \"\$(cat /proc/uptime)\" \"\$EPOCHREALTIME\" >> $DEV_OUT"
  ev marker SK_SEEK_RELEASE
else
  adb -s "$SER" shell input swipe "$XA" "$GY" "$XB" "$GY" "$GEST_DUR_MS"
  adb -s "$SER" shell "printf 'SK_SEEK_RELEASE|%s|%s\n' \"\$(cat /proc/uptime)\" \"\$EPOCHREALTIME\" >> $DEV_OUT"
  ev swipe_sent "x $XA->$XB y=$GY dur=${GEST_DUR_MS}ms (release marker after)"
fi
sleep 0.9
seek_ui_shot seek-ui
ev seek_ui_shot done

sleep $(( DENSE_DUR - 5 ))
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
