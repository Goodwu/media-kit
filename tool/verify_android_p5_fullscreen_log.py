#!/usr/bin/env python3
"""Check the log-observable part of a LYA-AL00 P5 Glass fullscreen run.

Physical 3120x1440 ROTATION_90 is required at each stable checkpoint.
This does not certify actual display presents or visible quality.
"""

import argparse
import gzip
import json
import re
import sys
from pathlib import Path


PERF_RE = re.compile(
    r"\bPERF t=(\d+) (time-pos|frame-drop-count|decoder-frame-drop-count|"
    r"container-fps|eof-reached|thermal-status)=([^\s]+)"
)
SIZE_RE = re.compile(r"\bVideoOutputManager\.setSurfaceSize: \d+ (\d+) (\d+)\b")
SOURCE_SIZE_RE = re.compile(
    r"\bANDROID_TEXTURE_OUTPUT_SIZE source=(\d+)x(\d+) target=(\d+)x(\d+)\b"
)
PHYSICAL_WINDOW_RE = re.compile(
    r"\bmBounds=Rect\(0, 0 - (\d+), (\d+)\).*"
    r"\bmWindowingMode=fullscreen\b.*\bmRotation=ROTATION_(\d+)\b"
)
CACHE_RE = re.compile(r"\bP5_EGL_CACHE: enabled=(\d+) property=([^\s]+)")
IMAGE_RE = re.compile(r"\bP5_IMAGE_FINAL acquired=(\d+) deleted=(\d+)")
RETIRE_RE = re.compile(r"\bP5_RETIRE_FINAL .*\bheld_after=(\d+) .*\bfallbacks=(\d+)")
DIAGNOSTIC_RE = re.compile(
    r"\bP5_PERF_(?:CLEAR_ONLY|MAP_ONLY|TWO_PASS|COLOR_STAGE|SAMPLE_ONLY|MAP_VARIANT)\b"
)
THREADTIME_PID_RE = re.compile(
    r"^\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+\s+(\d+)\s+\d+\s+"
)


def read_log(path: Path):
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rt", errors="replace") as stream:
        yield from stream


def inspect(path: Path, width: int, height: int, expected_cache: int,
            max_steady_vo_drops: int, max_total_vo_drops: int = 107):
    sizes = []
    source_sizes = []
    perf = {}
    physical_at_perf = {}
    physical_window = None
    cache = []
    fullscreen = False
    p5_open = False
    image_final = None
    retire_final = None
    fatal = []
    diagnostics = set()
    app_event_pids = {}
    p5_open_count = 0
    for line in read_log(path):
        def record_app_event(name):
            match = THREADTIME_PID_RE.match(line)
            app_event_pids.setdefault(name, set()).add(
                int(match[1]) if match else None
            )

        if match := SIZE_RE.search(line):
            sizes.append([int(match[1]), int(match[2])])
            record_app_event("output_size")
        if match := SOURCE_SIZE_RE.search(line):
            source_size = [int(value) for value in match.groups()]
            if source_size not in source_sizes:
                source_sizes.append(source_size)
            record_app_event("source_size")
        if "ANDROID_HDR_OPEN sample=AndroidHdrSample.dolbyVisionP5" in line:
            p5_open = True
            p5_open_count += 1
            record_app_event("p5_open")
        if "DIAG_FULLSCREEN_INPLACE complete" in line:
            fullscreen = True
            record_app_event("fullscreen")
        if "ActivityTaskManager:" in line:
            if match := PHYSICAL_WINDOW_RE.search(line):
                physical_window = [int(value) for value in match.groups()]
        if match := PERF_RE.search(line):
            checkpoint = int(match[1])
            perf.setdefault(checkpoint, {})[match[2]] = match[3]
            physical_at_perf[checkpoint] = physical_window
            record_app_event("perf")
        if match := CACHE_RE.search(line):
            cache.append(int(match[1]))
            record_app_event("cache")
        if match := IMAGE_RE.search(line):
            image_final = [int(match[1]), int(match[2])]
            record_app_event("image_final")
        if match := RETIRE_RE.search(line):
            retire_final = [int(match[1]), int(match[2])]
            record_app_event("retire_final")
        if "FATAL EXCEPTION" in line or "GL_OUT_OF_MEMORY" in line:
            fatal.append(line.strip()[:200])
        if match := DIAGNOSTIC_RE.search(line):
            diagnostics.add(match[0])

    errors = []
    open_pids = app_event_pids.get("p5_open", set())
    if p5_open_count != 1 or len(open_pids) != 1 or None in open_pids:
        errors.append(
            f"expected one threadtime P5 open in one process: "
            f"count={p5_open_count} pids={sorted(str(pid) for pid in open_pids)}"
        )
    else:
        expected_pid = next(iter(open_pids))
        for event, pids in app_event_pids.items():
            if pids != {expected_pid}:
                errors.append(
                    f"{event} belongs to another/missing process: "
                    f"expected={expected_pid} pids={sorted(str(pid) for pid in pids)}"
                )
    if not sizes:
        errors.append("missing setSurfaceSize")
    elif any(size != [width, height] for size in sizes):
        errors.append(f"unexpected output size: {sizes}")
    if not fullscreen:
        errors.append("missing in-place fullscreen completion")
    for checkpoint in (60, 90, 120, 150, 180):
        if physical_at_perf.get(checkpoint) != [3120, 1440, 90]:
            errors.append(
                f"missing physical landscape fullscreen at t{checkpoint}: "
                f"{physical_at_perf.get(checkpoint)}"
            )
    if not p5_open:
        errors.append("missing P5 sample open")
    expected_source_size = [3840, 2160, width, height]
    if not source_sizes or any(size != expected_source_size for size in source_sizes):
        errors.append(f"unexpected 4K source/output size: {source_sizes}")
    # The product mapper no longer has the optional EGLImage cache or its
    # init log. Preserve --cache for historical diagnostic runs only.
    if expected_cache is not None and (
        not cache or any(value != expected_cache for value in cache)
    ):
        errors.append(f"unexpected cache state: {cache}")
    if not perf.get(210, {}).get("eof-reached") == "yes":
        errors.append("missing EOS at t210")
    if not perf.get(210, {}).get("decoder-frame-drop-count") == "0":
        errors.append("decoder drop count is missing or nonzero at EOS")
    try:
        fps = float(perf[210]["container-fps"])
        if not 59.8 <= fps <= 60.1:
            errors.append(f"unexpected source fps: {fps}")
    except (KeyError, ValueError):
        errors.append("missing source fps")
    try:
        media_end = float(perf[210]["time-pos"])
        if not 177.5 <= media_end <= 178.2:
            errors.append(f"unexpected EOS media time: {media_end}")
    except (KeyError, ValueError):
        errors.append("missing EOS media time")
    if image_final is None or image_final[0] != image_final[1]:
        errors.append(f"AImage ownership did not close: {image_final}")
    if retire_final != [0, 0]:
        errors.append(f"retire queue did not close cleanly: {retire_final}")
    if fatal:
        errors.append(f"fatal/GL OOM log lines: {fatal[:3]}")
    if diagnostics:
        errors.append(f"diagnostic render path is not a playback gate: {sorted(diagnostics)}")

    drops = {}
    for time in (60, 90, 120, 150, 180, 210):
        try:
            drops[time] = int(perf[time]["frame-drop-count"])
        except (KeyError, ValueError):
            errors.append(f"missing VO drop count at t{time}")
    result = {
        "log": str(path),
        "output_sizes": sizes,
        "source_output_sizes": source_sizes,
        "p5_open_observed": p5_open,
        "p5_open_count": p5_open_count,
        "app_event_pids": {
            event: sorted(str(pid) for pid in pids)
            for event, pids in app_event_pids.items()
        },
        "cache_enabled": cache,
        "fullscreen_log_observed": fullscreen,
        "physical_window_at_perf": physical_at_perf,
        "vo_drops": drops,
        "decoder_drops_eos": perf.get(210, {}).get("decoder-frame-drop-count"),
        "media_time_eos": perf.get(210, {}).get("time-pos"),
        "image_final": image_final,
        "retire_final_held_fallbacks": retire_final,
        "diagnostic_render_paths": sorted(diagnostics),
        "errors": errors,
    }
    if 60 in drops and 180 in drops:
        result["vo_drops_t60_to_t180"] = drops[180] - drops[60]
        if max_steady_vo_drops >= 0 and result["vo_drops_t60_to_t180"] > max_steady_vo_drops:
            errors.append(
                f"steady VO drops {result['vo_drops_t60_to_t180']} exceed "
                f"limit {max_steady_vo_drops}"
            )
    observed_drops = [drops[time] for time in (60, 90, 120, 150, 180, 210)
                      if time in drops]
    if any(later < earlier for earlier, later in zip(observed_drops, observed_drops[1:])):
        errors.append("VO drop counter decreased between checkpoints")
    if 210 in drops and max_total_vo_drops >= 0 and drops[210] > max_total_vo_drops:
        errors.append(
            f"total VO drops {drops[210]} exceed limit {max_total_vo_drops}"
        )
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    parser.add_argument(
        "--cache", type=int, choices=(0, 1),
        help="require the cache state marker in historical diagnostic logs",
    )
    parser.add_argument(
        "--max-steady-vo-drops", type=int, default=72,
        help="maximum drops from t60 to t180; default 72 is an engineering 1%% limit; -1 disables",
    )
    parser.add_argument(
        "--max-total-vo-drops", type=int, default=107,
        help="maximum drops over the full 177.8s clip; default 107 is about 1%%; -1 disables",
    )
    args = parser.parse_args()
    result = inspect(args.log, args.width, args.height, args.cache,
                     args.max_steady_vo_drops, args.max_total_vo_drops)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 1 if result["errors"] else 0


if __name__ == "__main__":
    sys.exit(main())
