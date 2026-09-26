#!/usr/bin/env python3
"""Summarize per-loop mpv counters emitted by the Android P5 test page."""

import argparse
import re
import statistics
from pathlib import Path


COUNTER = re.compile(
    r"(?P<clock>\d\d:\d\d:\d\d\.\d+) .*?ANDROID_P5_COUNTERS "
    r"\{time-pos: (?P<position>[\d.]+), frame-drop-count: (?P<vo>\d+), "
    r"decoder-frame-drop-count: (?P<decoder>\d+)"
)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    args = parser.parse_args()

    loops: list[list[tuple[str, float, int, int]]] = []
    for line in args.log.open(errors="replace"):
        match = COUNTER.search(line)
        if not match:
            continue
        point = (
            match["clock"],
            float(match["position"]),
            int(match["vo"]),
            int(match["decoder"]),
        )
        if not loops or point[1] < loops[-1][-1][1] - 2:
            loops.append([])
        loops[-1].append(point)

    print(f"samples={sum(map(len, loops))} segments={len(loops)}")
    for index, segment in enumerate(loops, 1):
        first, last = segment[0], segment[-1]
        advances = [b[1] - a[1] for a, b in zip(segment, segment[1:])]
        cadence = (
            f"advance_median={statistics.median(advances):.3f} "
            f"advance_min={min(advances):.3f} advance_max={max(advances):.3f} "
            if advances
            else ""
        )
        print(
            f"segment={index} samples={len(segment)} "
            f"clock={first[0]}..{last[0]} "
            f"time_pos={first[1]:.3f}..{last[1]:.3f} "
            f"{cadence}"
            f"vo_drop_max={max(p[2] for p in segment)} "
            f"decoder_drop_max={max(p[3] for p in segment)}"
        )


if __name__ == "__main__":
    main()
