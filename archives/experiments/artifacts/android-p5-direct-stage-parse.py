#!/usr/bin/env python3
"""Summarize sparse P5 timing logs without treating CPU waits as GPU execution."""

import json
import re
import statistics
import sys
from pathlib import Path

TAGS = ("P5_RAW_TIME", "P5_VO_TIME", "P5_VO_FLIP")
FIELD = re.compile(r"([a-z_]+)=(-?\d+)")


def summarize(path):
    buckets = {tag: {} for tag in TAGS}
    for line in Path(path).read_text(errors="replace").splitlines():
        tag = next((tag for tag in TAGS if f"/{tag}(" in line), None)
        if tag is None:
            continue
        values = {key: int(value) for key, value in FIELD.findall(line)}
        if not 50 <= values.get("frame", -1) <= 2500:
            continue
        for key, value in values.items():
            if key.endswith("_us"):
                buckets[tag].setdefault(key, []).append(value)
    result = {}
    for tag, fields in buckets.items():
        result[tag] = {}
        for key, values in fields.items():
            ordered = sorted(values)
            result[tag][key] = {
                "n": len(values),
                "median_us": statistics.median(values),
                "p95_us": ordered[int(0.95 * (len(values) - 1))],
                "max_us": ordered[-1],
            }
    return result


if __name__ == "__main__":
    print(json.dumps({Path(path).name: summarize(path) for path in sys.argv[1:]},
                     ensure_ascii=False, indent=2))
