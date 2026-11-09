#!/system/bin/sh
# ff-attr dense sampler (device side, LG H870DS Android 7, mksh).
# usage: ff_sample.sh <outfile> <layer> <duration_s>
# Each iteration appends:
#   S|<i>|<uptime>|<epochrealtime>          marker (before dumps)
#   <desired> <actual> <ready>  (ns)        SF --latency rows for <layer>
#   ... media_session section (pkg, ends with queueTitle line)
# Iteration period measured ~100-140 ms (SF ~50 ms + media_session ~35 ms + overhead).
OUT=$1
LAYER=$2
DUR=$3
PKGRE='media-session com.example.piliplus.dev'
END=$(cut -d. -f1 /proc/uptime)
END=$((END + DUR))
i=0
while :; do
  NOW=$(cut -d. -f1 /proc/uptime)
  [ "$NOW" -ge "$END" ] && break
  printf 'S|%d|%s|%s\n' "$i" "$(cat /proc/uptime)" "$EPOCHREALTIME" >> "$OUT"
  dumpsys SurfaceFlinger --latency "$LAYER" >> "$OUT" 2>&1
  dumpsys media_session | sed -n "/$PKGRE/,/queueTitle/p" >> "$OUT" 2>&1
  i=$((i + 1))
done
printf 'E|%d|%s|%s\n' "$i" "$(cat /proc/uptime)" "$EPOCHREALTIME" >> "$OUT"
