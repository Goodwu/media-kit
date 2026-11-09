#!/usr/bin/env bash
# show_panel.sh <out_png> -- toggle-tap video center until panel visible; up to 4 tries
S=LGH870DS42e27764
OUT=$1
for i in 1 2 3 4; do
  adb -s $S shell input tap 720 540
  sleep 0.4
  adb -s $S exec-out screencap -p > "$OUT"
  python3 - "$OUT" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert('RGB')
px = im.load()
rows = [y for y in range(140, 880, 4) if sum(1 for x in range(0, 1440, 6) if sum(px[x,y]) > 150) > 8]
print('PANEL_VISIBLE' if rows else 'PANEL_HIDDEN')
PY
  if grep -q PANEL_VISIBLE /dev/stdin <<< "$(python3 - "$OUT" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert('RGB')
px = im.load()
rows = [y for y in range(140, 880, 4) if sum(1 for x in range(0, 1440, 6) if sum(px[x,y]) > 150) > 8]
print('PANEL_VISIBLE' if rows else 'PANEL_HIDDEN')
PY
)"; then echo "visible on try $i"; exit 0; fi
done
echo "panel never visible"; exit 1
