#!/usr/bin/env python3
"""Summarize nested atrace slices for one app thread from an atrace -z dump."""

import argparse
import bisect
import collections
import re
import statistics
import zlib
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("trace", type=Path)
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--tid", type=int, required=True)
    args = parser.parse_args()

    data = args.trace.read_bytes()
    marker = b"TRACE:\n"
    offset = data.find(marker)
    if offset < 0:
        raise SystemExit("atrace TRACE marker not found")
    data = zlib.decompress(data[offset + len(marker) :])
    pattern = re.compile(
        rb"-" + str(args.tid).encode() + rb" \(" + str(args.pid).encode()
        + rb"\).*? (\d+\.\d+): tracing_mark_write: ([BE])\|"
        + str(args.pid).encode() + rb"(?:\|([^\n]+))?"
    )

    stack: list[tuple[str, float]] = []
    durations: dict[tuple[str, str], list[float]] = collections.defaultdict(list)
    queue_waits: list[tuple[float, float]] = []
    mali_fence_init: dict[tuple[str, int, int], float] = {}
    mali_fence_complete: list[tuple[float, float | None]] = []
    mali_signals: list[float] = []
    display_signals: list[float] = []
    vo_wakeups: list[float] = []
    raster_updates: list[float] = []
    texture_queue_levels: list[tuple[float, int]] = []
    unmatched = 0
    for line in data.splitlines():
        fence = re.search(
            rb" (\d+\.\d+): dma_fence_(init|signaled): driver=mali "
            rb"timeline=([^ ]+) context=(\d+) seqno=(\d+)", line
        )
        if fence:
            key = (fence.group(3).decode(), int(fence.group(4)), int(fence.group(5)))
            if fence.group(2) == b"init":
                mali_fence_init[key] = float(fence.group(1))
            else:
                mali_fence_complete.append(
                    (float(fence.group(1)), mali_fence_init.get(key))
                )
        signal = re.search(rb" (\d+\.\d+): dma_fence_signaled: driver=([^ ]+)", line)
        if signal:
            if signal.group(2) == b"mali":
                mali_signals.append(float(signal.group(1)))
            elif signal.group(2) == b"hisi_dss":
                display_signals.append(float(signal.group(1)))
        wakeup = re.search(
            rb" (\d+\.\d+): sched_wakeup: .* pid="
            + str(args.tid).encode() + rb" ", line
        )
        if wakeup:
            vo_wakeups.append(float(wakeup.group(1)))
        update = re.search(
            rb" (\d+\.\d+): tracing_mark_write: B\|"
            + str(args.pid).encode() + rb"\|updateTexImage", line
        )
        if update and b"raster" in line.split(b"(", 1)[0]:
            raster_updates.append(float(update.group(1)))
        queue_level = re.search(
            rb" (\d+\.\d+): tracing_mark_write: C\|"
            + str(args.pid).encode()
            + rb"\|SurfaceTexture-0-" + str(args.pid).encode()
            + rb"-0\|(\d+)", line
        )
        if queue_level:
            texture_queue_levels.append(
                (float(queue_level.group(1)), int(queue_level.group(2)))
            )
        match = pattern.search(line)
        if not match:
            continue
        when = float(match.group(1))
        if match.group(2) == b"B":
            stack.append((match.group(3).decode(errors="replace"), when))
        elif stack:
            name, start = stack.pop()
            parent = stack[-1][0] if stack else "<root>"
            durations[name, parent].append((when - start) * 1000)
            if name == "waitForever" and parent == "queueBuffer":
                queue_waits.append((start, when))
        else:
            unmatched += 1

    print(f"decoded_bytes={len(data)} unclosed={len(stack)} unmatched={unmatched}")
    for name, parent in (
        ("eglSwapBuffers", "<root>"),
        ("queueBuffer", "eglSwapBuffers"),
        ("queueBuffer", "queueBuffer"),
        ("waitForever", "queueBuffer"),
        ("dequeueBuffer", "<root>"),
    ):
        values = sorted(durations.get((name, parent), []))
        if not values:
            print(f"{name} parent={parent} count=0")
            continue
        print(
            f"{name} parent={parent} count={len(values)} "
            f"median_ms={statistics.median(values):.3f} "
            f"p95_ms={values[int(0.95 * (len(values) - 1))]:.3f} "
            f"max_ms={values[-1]:.3f}"
        )

    for name, times in (
        ("mali_dma_fence_signal", mali_signals),
        ("hisi_display_fence_signal", display_signals),
        ("vo_thread_wakeup", vo_wakeups),
    ):
        within_half_ms = 0
        within_one_ms = 0
        for _, end in queue_waits:
            index = bisect.bisect_right(times, end) - 1
            if index < 0:
                continue
            gap_ms = (end - times[index]) * 1000
            within_half_ms += gap_ms <= 0.5
            within_one_ms += gap_ms <= 1.0
        print(
            f"{name} events={len(times)} "
            f"wait_ends_with_prior_event_0.5ms={within_half_ms}/{len(queue_waits)} "
            f"within_1ms={within_one_ms}/{len(queue_waits)}"
        )

    signal_times = [item[0] for item in mali_fence_complete]
    paired_fence_ages = [
        (signal - created) * 1000
        for signal, created in mali_fence_complete
        if created is not None
    ]
    near_wait_ages = []
    near_wait_before = []
    for start, end in queue_waits:
        index = bisect.bisect_right(signal_times, end) - 1
        if index < 0:
            continue
        signal, created = mali_fence_complete[index]
        if end - signal <= 0.0005 and created is not None:
            near_wait_ages.append((signal - created) * 1000)
            near_wait_before.append((start - created) * 1000)
    if paired_fence_ages:
        print(
            f"paired_mali_fences={len(paired_fence_ages)} "
            f"init_to_signal_median_ms={statistics.median(paired_fence_ages):.3f}"
        )
    if near_wait_ages:
        print(
            f"near_wait_mali_signals={len(near_wait_ages)} "
            f"fence_init_to_signal_median_ms={statistics.median(near_wait_ages):.3f} "
            f"fence_init_to_wait_start_median_ms={statistics.median(near_wait_before):.3f}"
        )

    update_intervals = [
        (later - earlier) * 1000
        for earlier, later in zip(raster_updates, raster_updates[1:])
    ]
    after_wait = []
    for _, end in queue_waits:
        index = bisect.bisect_left(raster_updates, end)
        if index < len(raster_updates):
            after_wait.append((raster_updates[index] - end) * 1000)
    levels = collections.Counter(level for _, level in texture_queue_levels)
    if update_intervals and after_wait:
        print(
            f"raster_updateTexImage={len(raster_updates)} "
            f"interval_median_ms={statistics.median(update_intervals):.3f} "
            f"next_after_wait_median_ms={statistics.median(after_wait):.3f} "
            f"queue_level_counts={dict(sorted(levels.items()))}"
        )


if __name__ == "__main__":
    main()
