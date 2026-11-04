#!/usr/bin/env bash
# phase3-poc round driver (keyframe-resume PoC, PiliPlus dev @ LG-H870DS).
# usage: run_poc_round.sh <round_dir> <type:kn|kf|kp|ks>
#   kn : normal HOME (keyevent) dwell 10 s -> am start return -> observe
#   kf : fast HOME (method F: chained MAIN/HOME + return, --activity-no-animation)
#   kp : media_session pause -> verify frozen -> HOME -> return -> assert still
#        paused -> dispatch play
#   ks : media dispatch rewind (SK-DV-1 method), manual-seek control round
# All rounds: cold start deep link BV1vY4y1N7TY?t=120, >=30 s stable play,
# dense SF --latency + media_session sampling from ~1 s before the trigger,
# full logcat dump at round end. Modeled on ../phase2 ff-attr run_ff_round.sh.
# env: T_SEC=120 PLAY_WAIT=32 HOME_WAIT=10 DENSE_DUR=26
set -Eeuo pipefail
ROUND_DIR=$1; TYPE=$2
SER=LGH870DS42e27764
PKG=com.example.piliplus.dev
ACT=$PKG/com.example.piliplus.MainActivity
DV_URL="https://www.bilibili.com/video/BV1vY4y1N7TY?t=${T_SEC:-120}"
LAYER="SurfaceView - $ACT"
T_SEC=${T_SEC:-120}
PLAY_WAIT=${PLAY_WAIT:-32}
HOME_WAIT=${HOME_WAIT:-10}
DENSE_DUR=${DENSE_DUR:-26}
HERE=$(cd "$(dirname "$0")" && pwd)
DEV_OUT=/data/local/tmp/poc_dense.txt
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
mstate() { adb -s "$SER" shell "dumpsys media_session" 2>/dev/null | sed -n '/media-session '"$PKG"'/,/queueTitle/p' | grep -oE 'state=[0-9]+, position=[0-9]+, buffered position=[0-9]+, speed=[0-9.]+, updated=[0-9]+' | head -1 | tr -d '\r'; }
sample() { # sparse bundle
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
  adb -s "$SER" shell "nohup sh /data/local/tmp/poc/ff_sample.sh $DEV_OUT '$LAYER' $1 >/dev/null 2>&1 &" || true
  ev dense_sampler_started "dur=$1 out=$DEV_OUT"
}

# push device sampler (idempotent)
adb -s "$SER" shell "mkdir -p /data/local/tmp/poc"
adb -s "$SER" push "$HERE/ff_sample.sh" /data/local/tmp/poc/ff_sample.sh >/dev/null

ev round_begin "type=$TYPE pkg=$PKG dv_url=$DV_URL play_wait=$PLAY_WAIT home_wait=$HOME_WAIT dense_dur=$DENSE_DUR prop=$(adb -s "$SER" shell getprop debug.mks.home_trace | tr -d '\r')"
screen | tee "$ROUND_DIR/screen-before.txt"
DROPBOX_BEFORE=$(adb -s "$SER" shell dumpsys dropbox 2>/dev/null | grep -cE "data_app_crash|data_app_anr|data_app_native_crash|SYSTEM_TOMBSTONE" | tr -d '\r' || true)
ev dropbox_before "crash_entries=$DROPBOX_BEFORE"

adb -s "$SER" shell am force-stop "$PKG"; sleep 1
ev force_stop "pid_after=$(pid)"
for b in main system crash events radio kernel; do
  if adb -s "$SER" logcat -c -b "$b" >/dev/null 2>&1; then echo "logcat -c -b $b rc=0"; else echo "logcat -c -b $b rc=$?"; fi
done
ev logcat_cleared "per-buffer"

adb -s "$SER" shell am start -a android.intent.action.VIEW -d "$DV_URL" -p "$PKG" | tr -d '\r' | tee "$ROUND_DIR/launch-output.txt"
ev am_start_deeplink "pid=$(pid) url=$DV_URL"

sleep 8
sample play_start
shot after-launch

sleep $(( PLAY_WAIT - 8 ))
sample pre_trigger_1
echo "state pre-trigger: $(mstate)" | tee "$ROUND_DIR/state-pre-trigger.txt"
PID_BEFORE=$(pid)
ev pid_before "pid=$PID_BEFORE"
adb -s "$SER" exec-out logcat -d -v threadtime -b all > "$ROUND_DIR/logcat-pre-trigger.txt"
ev interim_dump "lines=$(wc -l < "$ROUND_DIR/logcat-pre-trigger.txt")"
echo "--- pre-trigger hwdec evidence ---"
grep -E "class=dvP84|mkst_create_decoder_window exit|makeComponentInstance|Now Executing" "$ROUND_DIR/logcat-pre-trigger.txt" | cut -c1-190 | tail -6 || true

case "$TYPE" in
kn|kp)
  if [[ "$TYPE" == kp ]]; then
    # API24 device: `cmd media_session` has no implementation; the legacy
    # `media dispatch` shell command is the verified-working path (phase2
    # ff-attr/ff-seek). Attempt1 with `cmd media_session dispatch` was a no-op.
    adb -s "$SER" shell media dispatch pause
    ev pause_dispatched "media dispatch pause"
    sleep 3
    S1=$(mstate); sleep 3; S2=$(mstate)
    echo "paused-check-1: $S1" | tee "$ROUND_DIR/pause-verify.txt"
    echo "paused-check-2: $S2" | tee -a "$ROUND_DIR/pause-verify.txt"
    ev pause_verify "s1=$S1 s2=$S2"
  fi
  adb -s "$SER" shell input keyevent KEYCODE_HOME
  ev home_sent "keyevent HOME"
  sleep 4
  sample during_home_1
  sleep $(( HOME_WAIT - 4 - 3 ))
  sample during_home_2
  echo "state during-home: $(mstate)" | tee -a "$ROUND_DIR/state-pre-trigger.txt"
  ev home_dwell_done "home_wait=$HOME_WAIT"
  dense_start "$DENSE_DUR"
  sleep 1
  adb -s "$SER" shell "printf 'RETURN_CMD|%s|%s\n' \"\$(cat /proc/uptime)\" \"\$EPOCHREALTIME\" >> $DEV_OUT"
  ev return_cmd_marker "appended to $DEV_OUT"
  adb -s "$SER" shell am start -n "$ACT" | tr -d '\r' | tee "$ROUND_DIR/return-output.txt" >/dev/null
  ev return_sent "am start -n $ACT"
  if [[ "$TYPE" == kp ]]; then
    sleep 8
    P1=$(mstate); sleep 4; P2=$(mstate); sleep 4; P3=$(mstate)
    { echo "post-return-paused-1(+8s): $P1"; echo "post-return-paused-2(+12s): $P2"; echo "post-return-paused-3(+16s): $P3"; } | tee "$ROUND_DIR/post-return-pause-assert.txt"
    ev kp_pause_assert "p1=$P1 p2=$P2 p3=$P3"
    sleep 4
    adb -s "$SER" shell media dispatch play
    ev play_dispatched "media dispatch play"
  fi
  ;;
kf)
  dense_start "$DENSE_DUR"
  sleep 1
  adb -s "$SER" shell "printf 'KF_CMD|%s|%s\n' \"\$(cat /proc/uptime)\" \"\$EPOCHREALTIME\" >> $DEV_OUT"
  ev kf_cmd_marker "appended to $DEV_OUT"
  INNER="am start -a android.intent.action.MAIN -c android.intent.category.HOME --activity-no-animation; am start -n $ACT --activity-no-animation"
  ev fast_home_begin "cmd=adb shell: $INNER"
  adb -s "$SER" shell "$INNER" 2>&1 | tr -d '\r' | tee "$ROUND_DIR/return-output.txt" >/dev/null
  ev fast_home_return_sent "chained home+return returned (method F, sleep 0)"
  ;;
ks)
  dense_start "$DENSE_DUR"
  sleep 1
  adb -s "$SER" shell "printf 'SK_SEEK_CMD|%s|%s\n' \"\$(cat /proc/uptime)\" \"\$EPOCHREALTIME\" >> $DEV_OUT"
  ev seek_cmd_marker "appended to $DEV_OUT"
  adb -s "$SER" shell media dispatch rewind
  ev rewind_key_sent "media dispatch rewind (app-mapped small skip, SK-DV-1 method)"
  ;;
*) echo "unknown type $TYPE" >&2; exit 2;;
esac

sleep $(( DENSE_DUR ))
adb -s "$SER" pull "$DEV_OUT" "$ROUND_DIR/dense-samples.txt" >/dev/null
adb -s "$SER" shell "rm -f $DEV_OUT"
ev dense_pulled "lines=$(wc -l < "$ROUND_DIR/dense-samples.txt" | tr -d ' ')"

sample post_round
shot round-end
PID_AFTER=$(pid)
ev pid_after "pid_before=$PID_BEFORE pid_after=$PID_AFTER"
adb -s "$SER" shell dumpsys window 2>/dev/null | grep -E "mCurrentFocus|mFocusedApp" | tr -d '\r' | head -2 | tee "$ROUND_DIR/focus-after.txt"
screen | tee "$ROUND_DIR/screen-after.txt"
adb -s "$SER" exec-out logcat -d -v threadtime -b all > "$ROUND_DIR/logcat-full.txt"
ev full_dump "lines=$(wc -l < "$ROUND_DIR/logcat-full.txt")"
DROPBOX_AFTER=$(adb -s "$SER" shell dumpsys dropbox 2>/dev/null | grep -cE "data_app_crash|data_app_anr|data_app_native_crash|SYSTEM_TOMBSTONE" | tr -d '\r' || true)
ev dropbox_after "crash_entries_before=$DROPBOX_BEFORE after=$DROPBOX_AFTER"
echo "--- round key lines (chain + recovery-seek) ---"
grep -E "MKS-HOME-TRACE.*(authorize|recovery-seek|surfaceCreated|surfaceDestroyed|create_decoder_window (enter|exit)|ensure_init\(lc_verify\) exit|mkst_shutdown)|class=dvP84|makeComponentInstance|Now Executing|bridge not initialized|FATAL|ANR in" "$ROUND_DIR/logcat-full.txt" | cut -c1-230 | tail -60 || true
ev round_end
