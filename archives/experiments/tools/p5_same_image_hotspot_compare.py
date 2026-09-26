#!/usr/bin/env python3
"""Compare P5 raw-YUV hotspot readback to software and earlier mpv sidecar."""

import argparse
import json
import re
from pathlib import Path

import numpy as np


def parse_points(path: Path) -> dict[tuple[int, int], tuple[int, int, int]]:
    text = path.read_text()
    anchor = "timestampAsPtsUs=10000000"
    if text.count(anchor) != 1:
        raise ValueError(f"expected exactly one PTS10 image in {path}")
    record = text.split(anchor, 1)[1].split("hardwareBufferFormat=805", 1)[0]
    if "matchedOutputOrdinal=500" not in record:
        raise ValueError(f"target ordinal missing in {path}")
    raw = record.split("rawYuvFull=", 1)[1].split("floatFboStatus=", 1)[0]
    matches = re.findall(r"pt-(\d+),(\d+)=(\d+),(\d+),(\d+) err=0x0", raw)
    points = {(int(x), int(y)): (int(a), int(b), int(c))
              for x, y, a, b, c in matches}
    if len(matches) != 10 or len(points) != 10:
        raise ValueError(f"expected 10 unique error-free points in {path}")
    return points


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", action="append", type=Path, required=True)
    parser.add_argument("--software", type=Path, required=True)
    parser.add_argument("--mpv-packed-y", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    width, height = 3840, 2160
    software = np.fromfile(args.software, dtype="<u2")
    mpv = np.fromfile(args.mpv_packed_y, dtype="<u4")
    if software.size != width * height * 3 // 2 or mpv.size != width * height:
        raise ValueError("unexpected buffer size")
    y = software[:width * height].reshape(height, width)
    cb = software[width * height:width * height * 5 // 4].reshape(height // 2, width // 2)
    cr = software[width * height * 5 // 4:].reshape(height // 2, width // 2)
    mpv_y = (mpv.reshape(height, width) & 1023).astype(np.uint16)
    runs = [parse_points(path) for path in args.run]
    if any(run.keys() != runs[0].keys() for run in runs[1:]):
        raise ValueError("run coordinate sets differ")
    rows = []
    for x, yy in sorted(runs[0]):
        actual = runs[0][x, yy]
        src = (int(y[yy, x]), int(cb[yy // 2, x // 2]), int(cr[yy // 2, x // 2]))
        sw_expected = tuple(round(value * 1023 / 1020) for value in src)
        mpv_value = int(mpv_y[yy, x])
        mpv_expected = round(mpv_value * 1023 / 1020)
        rows.append({"x": x, "y": yy, "software_yuv": src,
                     "mpv_y": mpv_value, "gpu_raw_yuv": actual,
                     "software_scaled_y": sw_expected[0],
                     "mpv_scaled_y": mpv_expected,
                     "gpu_y_matches_mpv": actual[0] == mpv_expected,
                     "gpu_y_matches_software": actual[0] == sw_expected[0],
                     "repeat_identical": all(run[x, yy] == actual for run in runs[1:])})
    result = {"pts_us": 10000000, "output_ordinal": 500,
              "run_count": len(runs), "points": rows,
              "all_gpu_y_match_mpv": all(row["gpu_y_matches_mpv"] for row in rows),
              "all_repeats_identical": all(row["repeat_identical"] for row in rows)}
    rendered = json.dumps(result, indent=2) + "\n"
    if args.output:
        args.output.write_text(rendered)
    else:
        print(rendered, end="")


if __name__ == "__main__":
    main()
