#!/usr/bin/env python3
"""Summarize SurfaceFlinger BufferQueue events for one atrace layer."""

import argparse
import collections
import re
import statistics
import zlib
from pathlib import Path


MARKER = re.compile(
    r"-([0-9]+)\s+\(\s*[0-9]+\).*? (\d+\.\d+): "
    r"tracing_mark_write: ([BE])\|[0-9]+(?:\|(.*))?$"
)


def interval_summary(times: list[float]) -> str:
    gaps = sorted((later - earlier) * 1000 for earlier, later in zip(times, times[1:]))
    if not gaps:
        return "insufficient samples"
    return (
        f"span_s={times[-1] - times[0]:.3f} "
        f"interval_ms_min={gaps[0]:.3f} "
        f"median={statistics.median(gaps):.3f} "
        f"p95={gaps[int(0.95 * (len(gaps) - 1))]:.3f} "
        f"max={gaps[-1]:.3f}"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path)
    parser.add_argument("--layer", required=True)
    args = parser.parse_args()

    packed = args.trace.read_bytes().split(b"TRACE:\n", 1)[1]
    lines = zlib.decompress(packed).decode(errors="replace").splitlines()
    stacks: dict[str, list[str | None]] = collections.defaultdict(list)
    events: dict[str, list[float]] = collections.defaultdict(list)
    target = args.layer + ": "
    for line in lines:
        if "tracing_mark_write:" not in line:
            continue
        match = MARKER.search(line)
        if not match:
            continue
        tid, timestamp, kind, name = match.groups()
        if kind == "B":
            if name and name.startswith(target):
                parent = stacks[tid][-1] if stacks[tid] else None
                if parent in {"queueBuffer", "dequeueBuffer", "acquireBuffer", "releaseBuffer"}:
                    events[parent].append(float(timestamp))
            stacks[tid].append(name)
        elif stacks[tid]:
            stacks[tid].pop()

    for kind in ("queueBuffer", "acquireBuffer", "releaseBuffer", "dequeueBuffer"):
        times = events[kind]
        print(f"{kind}: count={len(times)} {interval_summary(times)}")
    queues, acquires = events["queueBuffer"], events["acquireBuffer"]
    if len(queues) == len(acquires) and queues:
        delays = [(acquire - queue) * 1000 for queue, acquire in zip(queues, acquires)]
        print(
            f"queue_to_acquire_ms: min={min(delays):.3f} "
            f"median={statistics.median(delays):.3f} max={max(delays):.3f} "
            "(ordered pairing; no frame ID proof)"
        )


if __name__ == "__main__":
    main()
