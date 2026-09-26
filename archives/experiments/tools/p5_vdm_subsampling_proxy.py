#!/usr/bin/env python3
"""Estimate RGB error from a BT.2020-NCL-style 10-bit 4:2:0 round trip.

This is a deliberately narrow proxy on P3/PQ code values. It does not model
P5 IPTPQc2, HEVC compression, Dolby reshape, or content mapping.
"""

import argparse
import subprocess

import numpy as np


KR = 0.2627
KB = 0.0593
KG = 1 - KR - KB


def quantize_10bit(values: np.ndarray) -> np.ndarray:
    return np.round(np.clip(values, 0, 1) * 1023) / 1023


def reconstruct(y: np.ndarray, cb: np.ndarray, cr: np.ndarray) -> np.ndarray:
    r = np.clip(y + 2 * (1 - KR) * (cr - 0.5), 0, 1)
    b = np.clip(y + 2 * (1 - KB) * (cb - 0.5), 0, 1)
    g = np.clip((y - KR * r - KB * b) / KG, 0, 1)
    return np.stack((r, g, b), axis=2)


def downsample_and_upsample(chroma: np.ndarray) -> np.ndarray:
    small = quantize_10bit(chroma.reshape(1080, 2, 1920, 2).mean((1, 3)))
    horizontal = np.clip((np.arange(3840, dtype=np.float32) - 0.5) / 2, 0, 1919)
    x0 = np.floor(horizontal).astype(int)
    wx = horizontal - x0
    wide = small[:, x0] * (1 - wx) + small[:, np.minimum(x0 + 1, 1919)] * wx
    vertical = np.clip((np.arange(2160, dtype=np.float32) - 0.5) / 2, 0, 1079)
    y0 = np.floor(vertical).astype(int)
    wy = vertical - y0
    return wide[y0] * (1 - wy[:, None]) + wide[np.minimum(y0 + 1, 1079)] * wy[:, None]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tiff")
    args = parser.parse_args()
    raw = subprocess.check_output(
        ["ffmpeg", "-v", "error", "-i", args.tiff, "-frames:v", "1",
         "-pix_fmt", "rgb48le", "-f", "rawvideo", "-"],
    )
    reference = np.frombuffer(raw, dtype="<u2")
    if reference.size != 3840 * 2160 * 3:
        raise ValueError("expected a 3840x2160 RGB48 TIFF")
    reference = reference.reshape(2160, 3840, 3).astype(np.float32) / 65535
    y = KR * reference[:, :, 0] + KG * reference[:, :, 1] + KB * reference[:, :, 2]
    cb = (reference[:, :, 2] - y) / (2 * (1 - KB)) + 0.5
    cr = (reference[:, :, 0] - y) / (2 * (1 - KR)) + 0.5
    luma = quantize_10bit(y)
    for name, u, v in (
        ("444_10bit", quantize_10bit(cb), quantize_10bit(cr)),
        ("420_10bit_bilinear", downsample_and_upsample(cb), downsample_and_upsample(cr)),
    ):
        difference = reconstruct(luma, u, v) - reference
        mae = np.abs(difference).mean((0, 1)).astype(np.float64) * 65535
        print(name, "RGB16_MAE", np.round(mae, 1).tolist())


if __name__ == "__main__":
    main()
