#!/usr/bin/env python3
"""Compare two raw RGBA16F L2C dumps without registration or fitting."""

import argparse
import json
from pathlib import Path

import numpy as np


def load(path: Path, width: int, height: int) -> np.ndarray:
    expected = width * height * 4 * 2
    if path.stat().st_size != expected:
        raise ValueError(f"{path}: size {path.stat().st_size}, expected {expected}")
    data = np.memmap(path, dtype="<f2", mode="r", shape=(height, width, 4))
    if not np.isfinite(data).all():
        raise ValueError(f"{path}: NaN or Inf")
    return data


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("phone", type=Path)
    parser.add_argument("host", type=Path)
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    parser.add_argument("--flip-host-y", action="store_true")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    phone = load(args.phone, args.width, args.height)
    host = load(args.host, args.width, args.height)
    if args.flip_host_y:
        host = host[::-1]
    report = {
        "width": args.width,
        "height": args.height,
        "host_y_flipped": args.flip_host_y,
        "channels": {},
    }
    for c, name in enumerate("RGBA"):
        actual = phone[:, :, c].astype(np.float32)
        expected = host[:, :, c].astype(np.float32)
        diff = np.abs(actual - expected)
        y, x = np.unravel_index(np.argmax(diff), diff.shape)
        report["channels"][name] = {
            "equal_count": int(np.count_nonzero(diff == 0)),
            "median_abs": float(np.median(diff)),
            "p99_abs": float(np.percentile(diff, 99)),
            "max_abs": float(diff[y, x]),
            "max_xy": [int(x), int(y)],
            "phone_at_max": float(actual[y, x]),
            "host_at_max": float(expected[y, x]),
            "components_gt_0_01": int(np.count_nonzero(diff > 0.01)),
        }
    rgb_diff = np.max(np.abs(phone[:, :, :3].astype(np.float32) -
                             host[:, :, :3].astype(np.float32)), axis=2)
    report["rgb_pixel_counts"] = {
        "gt_0_005": int(np.count_nonzero(rgb_diff > 0.005)),
        "gt_0_01": int(np.count_nonzero(rgb_diff > 0.01)),
        "gt_0_05": int(np.count_nonzero(rgb_diff > 0.05)),
        "gt_0_1": int(np.count_nonzero(rgb_diff > 0.1)),
        "gt_0_01_even_x": int(np.count_nonzero(rgb_diff[:, ::2] > 0.01)),
        "gt_0_01_odd_x": int(np.count_nonzero(rgb_diff[:, 1::2] > 0.01)),
    }
    output = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.write_text(output)
    else:
        print(output, end="")


if __name__ == "__main__":
    main()
