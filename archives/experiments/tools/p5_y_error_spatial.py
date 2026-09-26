#!/usr/bin/env python3
"""Describe spatial structure of a packed10 P5 Y readback against native YUV10."""

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--packed-y", type=Path, required=True)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    w, h = args.width, args.height
    if w <= 0 or h <= 0 or w % 2 or h % 2:
        parser.error("width and height must be positive and even")
    if args.packed_y.stat().st_size != w * h * 4:
        parser.error("packed Y must have exactly width*height uint32 samples")
    if args.reference.stat().st_size != w * h * 3:
        parser.error("reference must contain exactly one yuv420p10le frame")

    packed = np.memmap(args.packed_y, dtype="<u4", mode="r", shape=(h, w))
    reference = np.memmap(args.reference, dtype="<u2", mode="r", shape=(w * h * 3 // 2,))
    actual_y = (packed & 1023).astype(np.int16)
    expected_y = reference[: w * h].reshape(h, w).astype(np.int16)
    delta = actual_y - expected_y
    ys, xs = np.nonzero(delta)
    if not len(xs):
        components = []
    else:
        points = set(zip(xs.tolist(), ys.tolist()))
        components = []
        while points:
            seed = points.pop()
            stack = [seed]
            count = 0
            x0 = x1 = seed[0]
            y0 = y1 = seed[1]
            signed_sum = 0
            low, high = 1024, -1024
            while stack:
                x, y = stack.pop()
                value = int(delta[y, x])
                count += 1
                signed_sum += value
                low, high = min(low, value), max(high, value)
                x0, x1 = min(x0, x), max(x1, x)
                y0, y1 = min(y0, y), max(y1, y)
                for neighbor in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                    if neighbor in points:
                        points.remove(neighbor)
                        stack.append(neighbor)
            components.append({
                "pixels": count,
                "bbox_xyxy": [x0, y0, x1, y1],
                "mean_signed_code_delta": round(signed_sum / count, 6),
                "min_code_delta": low,
                "max_code_delta": high,
            })
        components.sort(key=lambda item: item["pixels"], reverse=True)

    result = {
        "contract": "packed Y low 10 bits vs yuv420p10le Y; same PTS and orientation",
        "width": w,
        "height": h,
        "packed_y_sha256": sha256(args.packed_y),
        "reference_sha256": sha256(args.reference),
        "mismatch_pixels": int(len(xs)),
        "positive_delta_pixels": int(np.count_nonzero(delta > 0)),
        "negative_delta_pixels": int(np.count_nonzero(delta < 0)),
        "component_connectivity": 4,
        "component_count": len(components),
        "singleton_components": sum(c["pixels"] == 1 for c in components),
        "components_at_least_10_pixels": sum(c["pixels"] >= 10 for c in components),
        "pixels_in_components_at_least_10": sum(c["pixels"] for c in components if c["pixels"] >= 10),
        "largest_components": components[:15],
    }
    rendered = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.write_text(rendered)
    else:
        print(rendered, end="")


if __name__ == "__main__":
    main()
