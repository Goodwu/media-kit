#!/usr/bin/env python3
"""Sample composed screen pixels after a UI trigger; preserve timing bounds.

This measures host-observed screenshots, not SurfaceFlinger present timestamps.
Use only as a visible-content sampling probe, never as an exact first-present KPI.
"""

import argparse
import io
import json
import subprocess
import time
from pathlib import Path

from PIL import Image, ImageStat


def adb(serial: str, *args: str) -> bytes:
    return subprocess.run(
        ["adb", "-s", serial, *args], check=True, capture_output=True
    ).stdout


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--serial", required=True)
    parser.add_argument("--tap", nargs=2, type=int, required=True, metavar=("X", "Y"))
    parser.add_argument("--roi", nargs=4, type=int, required=True, metavar=("X0", "Y0", "X1", "Y1"))
    parser.add_argument("--samples", type=int, default=20)
    parser.add_argument("--interval-ms", type=int, default=250)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    trigger_begin_ns = time.perf_counter_ns()
    adb(args.serial, "shell", "input", "tap", *map(str, args.tap))
    trigger_end_ns = time.perf_counter_ns()
    manifest = args.output / "samples.jsonl"
    with manifest.open("w") as out:
        out.write(json.dumps({
            "kind": "trigger",
            "tap": args.tap,
            "roi": args.roi,
            "host_begin_ns": trigger_begin_ns,
            "host_end_ns": trigger_end_ns,
            "clock": "host monotonic perf_counter_ns",
            "scope": "ADB screenshot after Flutter/SurfaceFlinger composition; sampled only",
        }) + "\n")
        for index in range(args.samples):
            capture_begin_ns = time.perf_counter_ns()
            png = adb(args.serial, "exec-out", "screencap", "-p")
            capture_end_ns = time.perf_counter_ns()
            image = Image.open(io.BytesIO(png)).convert("RGB")
            crop = image.crop(tuple(args.roi))
            stats = ImageStat.Stat(crop)
            filename = f"roi-{index:03d}.jpg"
            crop.save(args.output / filename, quality=88)
            out.write(json.dumps({
                "kind": "sample",
                "index": index,
                "file": filename,
                "capture_begin_ns": capture_begin_ns,
                "capture_end_ns": capture_end_ns,
                "since_trigger_begin_ms": round((capture_begin_ns - trigger_begin_ns) / 1e6, 2),
                "since_trigger_end_ms": round((capture_end_ns - trigger_end_ns) / 1e6, 2),
                "mean_rgb": [round(v, 2) for v in stats.mean],
                "std_rgb": [round(v, 2) for v in stats.stddev],
            }) + "\n")
            out.flush()
            next_ns = trigger_begin_ns + (index + 1) * args.interval_ms * 1_000_000
            remaining = (next_ns - time.perf_counter_ns()) / 1e9
            if remaining > 0:
                time.sleep(remaining)


if __name__ == "__main__":
    main()
