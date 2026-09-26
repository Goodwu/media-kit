#!/usr/bin/env python3
"""Sample Android GPU frequency with host and device timestamps as NDJSON.

This is observational only. It does not change GPU policy or device settings.
"""

import argparse
import datetime
import json
import subprocess
import sys
import time
from pathlib import Path


DEVICE_READ = (
    "cat /proc/uptime; "
    "cat /sys/class/devfreq/gpufreq/cur_freq"
)


def sample(adb, serial):
    before = time.monotonic_ns()
    result = subprocess.run(
        [adb, "-s", serial, "shell", DEVICE_READ],
        capture_output=True,
        text=True,
        timeout=5,
        check=True,
    )
    after = time.monotonic_ns()
    lines = result.stdout.splitlines()
    if len(lines) != 2:
        raise ValueError(f"expected uptime and frequency, got {lines!r}")
    device_uptime = float(lines[0].split()[0])
    frequency_hz = int(lines[1].strip())
    if device_uptime < 0 or frequency_hz <= 0:
        raise ValueError(f"invalid device sample: {lines!r}")
    return {
        "host_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "host_monotonic_mid_ns": (before + after) // 2,
        "adb_round_trip_ms": round((after - before) / 1_000_000, 3),
        "device_uptime_s": device_uptime,
        "gpu_frequency_hz": frequency_hz,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--duration", type=float, required=True)
    parser.add_argument("--interval", type=float, default=1.0)
    parser.add_argument("--adb", default="adb")
    args = parser.parse_args()
    if args.duration <= 0 or args.interval <= 0:
        parser.error("duration and interval must be positive")
    deadline = time.monotonic() + args.duration
    next_sample = time.monotonic()
    count = 0
    try:
        # Exclusive creation protects an existing evidence file.
        with args.output.open("x", encoding="utf-8") as stream:
            while time.monotonic() < deadline:
                record = sample(args.adb, args.serial)
                record["serial"] = args.serial
                record["sample_index"] = count
                stream.write(json.dumps(record, separators=(",", ":")) + "\n")
                stream.flush()
                count += 1
                next_sample += args.interval
                time.sleep(max(0, min(next_sample - time.monotonic(),
                                      deadline - time.monotonic())))
    except (OSError, subprocess.SubprocessError, ValueError) as error:
        print(f"sampling stopped after {count} valid samples: {error}",
              file=sys.stderr)
        return 2
    print(f"recorded {count} samples to {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
