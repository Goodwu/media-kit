#!/usr/bin/env bash
# CORE-reviewed eight-row P5/P8.4/HDR10/HLG × HDR gate matrix.
set -Eeuo pipefail
exec python3 "$(cd "$(dirname "$0")" && pwd)/routing_matrix.py" "$@"
