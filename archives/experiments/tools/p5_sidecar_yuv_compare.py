#!/usr/bin/env python3
"""Compare P5 packed10 sidecar readback with one native yuv420p10le frame."""

import argparse
import json
from pathlib import Path

import numpy as np


def describe(actual: np.ndarray, expected: np.ndarray) -> dict:
    delta = actual.astype(np.int32) - expected.astype(np.int32)
    ys, xs = np.nonzero(delta)
    return {
        "mismatch_count": int(xs.size),
        "sample_count": int(delta.size),
        "mean_abs_code_error": float(np.abs(delta).mean()),
        "max_abs_code_error": int(np.abs(delta).max()),
        "mismatch_bbox_xyxy": [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())]
        if xs.size else None,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--packed-y", type=Path, required=True)
    parser.add_argument("--packed-uv", type=Path, required=True)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.width <= 0 or args.height <= 0 or args.width % 2 or args.height % 2:
        parser.error("width and height must be positive and even")

    pixels = args.width * args.height
    chroma_pixels = pixels // 4
    packed_y = np.fromfile(args.packed_y, dtype="<u4")
    packed_uv = np.fromfile(args.packed_uv, dtype="<u4")
    reference = np.fromfile(args.reference, dtype="<u2")
    if packed_y.size != pixels or packed_uv.size != chroma_pixels:
        parser.error("packed readback does not match the declared dimensions")
    if reference.size != pixels + 2 * chroma_pixels:
        parser.error("reference must contain exactly one yuv420p10le frame")

    y = (packed_y.reshape(args.height, args.width) & 1023).astype(np.uint16)
    packed_uv = packed_uv.reshape(args.height // 2, args.width // 2)
    cb = ((packed_uv >> 10) & 1023).astype(np.uint16)
    cr = ((packed_uv >> 20) & 1023).astype(np.uint16)
    ref_y = reference[:pixels].reshape(args.height, args.width)
    ref_cb = reference[pixels:pixels + chroma_pixels].reshape(args.height // 2, args.width // 2)
    ref_cr = reference[pixels + chroma_pixels:].reshape(args.height // 2, args.width // 2)

    result = {
        "width": args.width,
        "height": args.height,
        "orientation": "readback rows as stored; no vertical flip",
        "Y": describe(y, ref_y),
        "Cb": describe(cb, ref_cb),
        "Cr": describe(cr, ref_cr),
        "Y_vertically_flipped_mismatch_count": int(np.count_nonzero(y[::-1] != ref_y)),
        "Cb_vertically_flipped_mismatch_count": int(np.count_nonzero(cb[::-1] != ref_cb)),
    }
    rendered = json.dumps(result, indent=2, ensure_ascii=False) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered)
    else:
        print(rendered, end="")


if __name__ == "__main__":
    main()
