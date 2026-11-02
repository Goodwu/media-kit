#!/usr/bin/env python3
"""Frame-interval stats from `dumpsys SurfaceFlinger --latency` captures.

Usage: frame_stats.py <latency_file> ...
Rows: desired-present  actual-present  ready ns (0,0,0 = padding).
"""
import sys


def stats(path: str) -> None:
    rows = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = fh.read().splitlines()
    if not lines:
        print(f"{path}: EMPTY")
        return
    refresh = lines[0].strip()
    for line in lines[1:]:
        parts = line.split()
        if len(parts) >= 2 and parts[1] not in ("0",):
            try:
                v = int(parts[1])
            except ValueError:
                continue
            if v <= 0 or v >= 2**62:  # SF reset sentinels (e.g. INT64_MAX)
                continue
            rows.append(v)
    rows.sort()
    print(f"== {path.split('/')[-1]}")
    print(f"   refresh_period_ns={refresh} frames={len(rows)}")
    if len(rows) < 3:
        return
    diffs = [b - a for a, b in zip(rows, rows[1:]) if b - a > 0]
    if not diffs:
        print("   no positive intervals")
        return
    diffs.sort()
    span = (rows[-1] - rows[0]) / 1e9
    med = diffs[len(diffs) // 2] / 1e6
    mean = sum(diffs) / len(diffs) / 1e6
    fps = len(diffs) / span if span else 0
    p95 = diffs[int(len(diffs) * 0.95)] / 1e6 if len(diffs) > 20 else diffs[-1] / 1e6
    long_gaps = sum(1 for d in diffs if d / 1e6 > 100)
    print(
        f"   window={span:.1f}s median_interval={med:.2f}ms mean={mean:.2f}ms "
        f"fps={fps:.2f} p95_interval={p95:.1f}ms gaps>100ms={long_gaps}"
    )


for p in sys.argv[1:]:
    stats(p)
