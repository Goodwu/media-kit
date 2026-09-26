#!/usr/bin/env python3
"""Compare a small P5 packed10 GPU readback with pre-encode YUV samples.

The expected odd-column shift is specific to the opt-in chroma-phase probe.
The Y clamp to 1020 is the observed contract of this vendor OES/code-scale
path, not a HEVC or Dolby Vision conformance rule.
"""

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np


def packed(path: Path, width: int, height: int) -> np.ndarray:
    data = np.fromfile(path, dtype="<u4")
    if data.size != width * height:
        raise ValueError(f"{path}: expected {width * height} packed pixels, got {data.size}")
    words = data.reshape(height, width)
    return np.stack([(words >> shift) & 1023 for shift in (0, 10, 20)], axis=-1)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--off", type=Path, required=True)
    parser.add_argument("--on", type=Path, required=True)
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    parser.add_argument("--frame", type=int, default=0)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    w, h = args.width, args.height
    if w % 2 or h % 2:
        raise ValueError("YUV420 dimensions must be even")
    raw = np.load(args.reference)["yuv"][args.frame]
    if raw.size != w * h * 3 // 2:
        raise ValueError("reference frame size does not match YUV420")
    plane = w * h
    y = raw[:plane].reshape(h, w)
    cb = raw[plane : plane + plane // 4].reshape(h // 2, w // 2)
    cr = raw[plane + plane // 4 :].reshape(h // 2, w // 2)
    off = packed(args.off, w, h)
    on = packed(args.on, w, h)
    x = np.arange(w)
    rows = np.arange(h)[:, None] // 2
    left_x = x[None, :] // 2
    right_x = np.minimum((x[None, :] + 1) // 2, w // 2 - 1)
    y_expected = np.minimum(y, 1020)
    expected_off = np.stack([y_expected, cb[rows, left_x], cr[rows, left_x]], axis=-1)
    expected_on = np.stack([y_expected, cb[rows, right_x], cr[rows, right_x]], axis=-1)
    report = {
        "reference_sha256": sha256(args.reference),
        "off_sha256": sha256(args.off),
        "on_sha256": sha256(args.on),
        "frame": args.frame,
        "width": w,
        "height": h,
        "expected_y": "min(pre_encode_y, 1020) for this vendor OES/code-scale path",
        "off_mismatch_y_cb_cr": [int(np.count_nonzero(off[:, :, c] != expected_off[:, :, c])) for c in range(3)],
        "on_mismatch_y_cb_cr": [int(np.count_nonzero(on[:, :, c] != expected_on[:, :, c])) for c in range(3)],
        "on_vs_off_y_differences": int(np.count_nonzero(on[:, :, 0] != off[:, :, 0])),
        "on_vs_off_even_cb_cr_differences": [int(np.count_nonzero(on[:, ::2, c] != off[:, ::2, c])) for c in (1, 2)],
        "on_vs_off_odd_cb_cr_differences": [int(np.count_nonzero(on[:, 1::2, c] != off[:, 1::2, c])) for c in (1, 2)],
        "unscaled_y_difference_count": int(np.count_nonzero(off[:, :, 0] != y)),
    }
    report["pass"] = (
        report["off_mismatch_y_cb_cr"] == [0, 0, 0]
        and report["on_mismatch_y_cb_cr"] == [0, 0, 0]
        and report["on_vs_off_y_differences"] == 0
        and report["on_vs_off_even_cb_cr_differences"] == [0, 0]
    )
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    if not report["pass"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
