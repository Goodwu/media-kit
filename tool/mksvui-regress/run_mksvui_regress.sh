#!/usr/bin/env bash
# MKSVUI host regression (D2 collection of the D1 /private/tmp/mksvui harness).
#
# Locks the decoder-origin classification fix chain's first link — the HEVC SPS
# VUI colour probe in the FFmpeg fork's mediacodecdec_common.c — as a rerunnable
# host gate: extracts the parser block from the live fork source, compiles it
# with ASan+UBSan, and asserts the fixture expectation table plus a
# deterministic malformed-input fuzz smoke.
#
# Usage:
#   ./run_mksvui_regress.sh [--fuzz-iters N] [--no-san] [--keep]
# Env:
#   FFMPEG_SRC          fork checkout (default ~/src/FFmpeg)
#   MKSVUI_REGRESS_LOG  where to write the run log (default /tmp/mksvui-regress/<ts>.log)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
FIXTURES="$HERE/fixtures"
FFMPEG_SRC="${FFMPEG_SRC:-$HOME/src/FFmpeg}"
FUZZ_ITERS=20000
SAN="-fsanitize=address,undefined -fno-sanitize-recover=all"
KEEP=0
while [ $# -gt 0 ]; do
    case "$1" in
        --fuzz-iters) FUZZ_ITERS="$2"; shift 2 ;;
        --no-san) SAN=""; shift ;;
        --keep) KEEP=1; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

WORK="/tmp/mksvui-regress"
LOG="${MKSVUI_REGRESS_LOG:-$WORK/run-$(date +%Y%m%d-%H%M%S).log}"
mkdir -p "$WORK"

echo "== MKSVUI host regression =="
echo "ffmpeg-src: $FFMPEG_SRC"
echo "workdir:    $WORK  (fixtures: $FIXTURES)"
echo "sanitizers: ${SAN:-off}   fuzz-iters: $FUZZ_ITERS"

# 1. extract the parser block from the live product source
python3 "$HERE/build_harness_from_source.py" \
    --ffmpeg-src "$FFMPEG_SRC" --out "$WORK/harness_regress.c"

# 2. compile
CC="${CC:-cc}"
# shellcheck disable=SC2086
$CC -O1 -g $SAN -o "$WORK/harness_regress" "$WORK/harness_regress.c"

# 3. run assertions (harness exit code is the verdict; the C cases
#    synA/synB/synU also validate the synthetic-fixture generator)
set +e
"$WORK/harness_regress" "$FIXTURES" "$FUZZ_ITERS" 2>&1 | tee "$LOG"
RC="${PIPESTATUS[0]}"
set -e

echo "log: $LOG"
if [ "$RC" -eq 0 ]; then
    echo "RESULT: PASS"
else
    echo "RESULT: FAIL (rc=$RC)"
fi
[ "$KEEP" -eq 1 ] || rm -f "$WORK/harness_regress" "$WORK/harness_regress.c"
exit "$RC"
