#!/usr/bin/env python3
"""Compare software 10-bit, MediaCodec ByteBuffer 8-bit, and PRIVATE/OES GPU samples."""

import argparse
import json
from pathlib import Path

import numpy as np


def summarize(software: np.ndarray, bytebuffer: np.ndarray,
              gpu: np.ndarray) -> dict:
    reference8 = (software >> 2).astype(np.uint8)
    gpu8 = (gpu >> 2).astype(np.uint8)
    delta = gpu8.astype(np.int16) - bytebuffer.astype(np.int16)
    return {
        "samples": int(software.size),
        "bytebuffer8_vs_software10_shift2_mismatches": int(np.count_nonzero(
            bytebuffer != reference8)),
        "gpu10_vs_software10_mismatches": int(np.count_nonzero(gpu != software)),
        "gpu10_shift2_vs_bytebuffer8_mismatches": int(np.count_nonzero(delta)),
        "gpu10_shift2_vs_bytebuffer8_max_abs_code_error": int(np.abs(delta).max()),
        "gpu10_shift2_vs_bytebuffer8_mean_abs_code_error": float(
            np.abs(delta).mean()),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--software10", required=True, type=Path)
    parser.add_argument("--bytebuffer8", required=True, type=Path)
    parser.add_argument("--packed-y", required=True, type=Path)
    parser.add_argument("--packed-uv", required=True, type=Path)
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.width <= 0 or args.height <= 0 or args.width % 2 or args.height % 2:
        parser.error("width and height must be positive and even")
    y_size = args.width * args.height
    c_size = y_size // 4
    software = np.fromfile(args.software10, dtype="<u2")
    bytebuffer = np.fromfile(args.bytebuffer8, dtype="u1")
    packed_y = np.fromfile(args.packed_y, dtype="<u4")
    packed_uv = np.fromfile(args.packed_uv, dtype="<u4")
    total = y_size + 2 * c_size
    if software.size != total or bytebuffer.size != total:
        parser.error("software and ByteBuffer inputs must each contain one frame")
    if packed_y.size != y_size or packed_uv.size != c_size:
        parser.error("GPU readback sizes do not match declared dimensions")
    gpu = np.concatenate((packed_y & 1023, (packed_uv >> 10) & 1023,
                          (packed_uv >> 20) & 1023)).astype(np.uint16)
    result = {"width": args.width, "height": args.height,
              "reference_quantization": "software10 >> 2"}
    offset = 0
    for name, size in (("Y", y_size), ("Cb", c_size), ("Cr", c_size)):
        end = offset + size
        result[name] = summarize(software[offset:end], bytebuffer[offset:end],
                                 gpu[offset:end])
        offset = end
    rendered = json.dumps(result, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered)
    else:
        print(rendered, end="")


if __name__ == "__main__":
    main()
