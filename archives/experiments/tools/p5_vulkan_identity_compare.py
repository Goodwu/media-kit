#!/usr/bin/env python3
"""Summarize the Vulkan identity probe against the fixed P5 PTS10 hot spots."""

import json
import argparse
import re
from pathlib import Path

COORDS = [
    (2577, 1221), (2576, 1221), (203, 1105), (1762, 939),
    (2215, 1113), (1785, 963), (2577, 1220), (2577, 1222),
    (384, 1080), (1920, 1080),
]
SOFTWARE_Y = [182, 193, 726, 706, 728, 708, 334, 120, 421, 415]
GL_RAW_Y = [276, 280, 668, 650, 673, 656, 339, 120, 422, 416]


def extract(path: Path):
    text = path.read_text()
    candidates = re.findall(r"samples=(.*?)matchedOutputOrdinal=500", text)
    if not candidates:
        raise ValueError(f"PTS10/ordinal500 not found in {path}")
    sample = candidates[-1].split("samples=")[-1]
    vals = re.findall(r"(\d+):\(([-\d.]+),([-\d.]+),([-\d.]+),([-\d.]+)\)", sample)
    if len(vals) != 10:
        raise ValueError(f"expected 10 samples, got {len(vals)} in {path}")
    return [float(v[2]) for v in vals]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("runs", nargs="+")
    parser.add_argument("--full", action="store_true", help="identity sampler used ITU full range")
    args = parser.parse_args()
    runs = [extract(Path(name)) for name in args.runs]
    if not runs:
        raise SystemExit("usage: p5_vulkan_identity_compare.py run.txt [run2.txt]")
    rows = []
    for i, (x, y) in enumerate(COORDS):
        vals = [run[i] for run in runs]
        rows.append({
            "x": x, "y": y, "software_y": SOFTWARE_Y[i], "gl_raw_y": GL_RAW_Y[i],
            "vulkan_identity_y": vals,
            "vulkan_code": [round(v * 1023) if args.full else round(v * 876 + 64)
                            for v in vals],
        })
    print(json.dumps({"range": "full" if args.full else "narrow",
                      "rows": rows, "runs_equal": all(run == runs[0] for run in runs)},
                     ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
