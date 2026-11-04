#!/usr/bin/env bash
# ff-attr BASE seek, controlled attempt: fresh deep-link start -> stable play ->
# media dispatch rewind (app-defined skip) -> dense sample around it.
# (BASE1B: drag no-op; BASE1B2: fast_forward rejected by build; BASE1B3: rewind
#  landed on an already-buffering player after an unexplained 142s->307.8s jump,
#  not a clean reference -> this retry.)
# usage: run_ff_base_seek2.sh <round_dir>
set -Eeuo pipefail
ROUND_DIR=$1
SER=LGH870DS42e27764
PKG=com.example.piliplus.dev
ACT=$PKG/com.example.piliplus.MainActivity
DV_URL="https://www.bilibili.com/video/BV1vY4y1N7TY?t=120"
LAYER="SurfaceView - $ACT"
PRE_WAIT=${PRE_WAIT:-32}
DENSE_DUR=${DENSE_DUR:-16}
DEV_OUT=/data/local/tmp/ff_dense.txt
mkdir -p "$ROUND_DIR"
EV="$ROUND_DIR/host-events.ndjson"
: > "$EV"
exec > >(tee "$ROUND_DIR/driver.log") 2>&1
hostms() { python3 -c 'import time;print(int(time.time()*1000))'; }
devms() { adb -s "$SER" shell 'echo $EPOCHREALTIME' | tr -d '\r' | awk '{printf "%d", $1*1000}'; }
ev() { local h; h=$(hostms); local d; d=$(devms); printf '{"event":"%s","host_ms":%s,"device_ms":%s,"note":"%s"}\n' "$1" "$h" "$d" "${2:-}" >> "$EV"; echo "[$(date +%H:%M:%S)] $1 ${2:-}"; }
state() { adb -s "$SER" shell "dumpsys media_session" 2>/dev/null | sed -n '/media-session '"$PKG"'/,/queueTitle/p' | grep -oE 'state=[0-9]+, position=[0-9]+' | head -1 | tr -d '\r'; }
shot() { adb -s "$SER" exec-out screencap -p > "$ROUND_DIR/$1.png" 2>/dev/null; }
ev round_begin "mode=base_seek_controlled url=$DV_URL"
adb -s "$SER" shell am force-stop "$PKG"; sleep 1
for b in main system crash events radio kernel; do adb -s "$SER" logcat -c -b "$b" >/dev/null 2>&1 || true; done
ev logcat_cleared per-buffer
adb -s "$SER" shell am start -a android.intent.action.VIEW -d "$DV_URL" -p "$PKG" >/dev/null
ev am_start_deeplink "pid=$(adb -s "$SER" shell pidof $PKG | tr -d '\r')"
sleep 8
echo "state +8s: $(state)"
sleep $(( PRE_WAIT - 8 ))
echo "state pre-seek: $(state)"
adb -s "$SER" shell "dumpsys SurfaceFlinger --latency '$LAYER'" > "$ROUND_DIR/sample-pre-seek-sflatency.txt" 2>&1 || true
ev pre_seek_state "$(state)"
shot pre-seek
adb -s "$SER" shell "rm -f $DEV_OUT"
adb -s "$SER" shell "nohup sh /data/local/tmp/ffattr/ff_sample.sh $DEV_OUT '$LAYER' $DENSE_DUR >/dev/null 2>&1 &"
ev dense_sampler_started "dur=$DENSE_DUR"
sleep 1
adb -s "$SER" shell "printf 'C_SEEK_CMD|%s|%s\n' \"\$(cat /proc/uptime)\" \"\$EPOCHREALTIME\" >> $DEV_OUT"
ev marker C_SEEK_CMD
adb -s "$SER" shell media dispatch rewind
ev c_seek_sent "media dispatch rewind"
sleep $(( DENSE_DUR - 2 ))
adb -s "$SER" pull "$DEV_OUT" "$ROUND_DIR/dense-c.txt" >/dev/null
adb -s "$SER" shell "rm -f $DEV_OUT"
ev dense_pulled "file=dense-c.txt lines=$(wc -l < "$ROUND_DIR/dense-c.txt" | tr -d ' ')"
echo "state post: $(state)"
shot post-seek
sleep 3
echo "state post2: $(state)"
adb -s "$SER" exec-out logcat -d -v threadtime -b all > "$ROUND_DIR/logcat-full.txt"
ev full_dump "lines=$(wc -l < "$ROUND_DIR/logcat-full.txt")"
echo "--- seek-window codec lines ---"
grep -E "Now Flushing|Now Executing|port settings change|makeComponentInstance" "$ROUND_DIR/logcat-full.txt" | cut -c1-150 | head -12 || true
ev round_end
