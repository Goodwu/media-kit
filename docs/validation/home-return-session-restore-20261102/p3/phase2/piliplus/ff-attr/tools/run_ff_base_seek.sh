#!/usr/bin/env bash
# ff-attr BASE seek retry: phase B failed with seekbar micro-drag (no seek fired;
# evidence: continuous presents, zero flush). Retry with `media dispatch
# rewind` (app-defined skip; delta recorded from position publish).
# usage: run_ff_base_seek.sh <round_dir>
set -Eeuo pipefail
ROUND_DIR=$1
SER=LGH870DS42e27764
PKG=com.example.piliplus.dev
ACT=$PKG/com.example.piliplus.MainActivity
LAYER="SurfaceView - $ACT"
DENSE_DUR=${DENSE_DUR:-14}
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

ev round_begin "mode=base_seek_retry (video already playing in-app, no relaunch)"
for b in main system crash events radio kernel; do adb -s "$SER" logcat -c -b "$b" >/dev/null 2>&1 || true; done
ev logcat_cleared "per-buffer"
echo "state pre: $(state)"
shot pre-seek
adb -s "$SER" shell "rm -f $DEV_OUT"
adb -s "$SER" shell "nohup sh /data/local/tmp/ffattr/ff_sample.sh $DEV_OUT '$LAYER' $DENSE_DUR >/dev/null 2>&1 &"
ev dense_sampler_started "dur=$DENSE_DUR"
sleep 1
adb -s "$SER" shell "printf 'B2_SEEK_CMD|%s|%s\n' \"\$(cat /proc/uptime)\" \"\$EPOCHREALTIME\" >> $DEV_OUT"
ev marker B2_SEEK_CMD
adb -s "$SER" shell media dispatch rewind
ev b2_seek_sent "media dispatch rewind"
sleep $(( DENSE_DUR - 2 ))
adb -s "$SER" pull "$DEV_OUT" "$ROUND_DIR/dense-b2.txt" >/dev/null
adb -s "$SER" shell "rm -f $DEV_OUT"
ev dense_pulled "file=dense-b2.txt lines=$(wc -l < "$ROUND_DIR/dense-b2.txt" | tr -d ' ')"
echo "state post: $(state)"
shot post-seek
sleep 2
echo "state post2: $(state)"
adb -s "$SER" exec-out logcat -d -v threadtime -b all > "$ROUND_DIR/logcat-full.txt"
ev full_dump "lines=$(wc -l < "$ROUND_DIR/logcat-full.txt")"
echo "--- seek-window control lines ---"
grep -cE "makeComponentInstance|mkst_create_decoder_window|authorize" "$ROUND_DIR/logcat-full.txt" || true
grep -E "Now Flushing|Now Executing|port settings change" "$ROUND_DIR/logcat-full.txt" | cut -c1-160 | head -10 || true
ev round_end
