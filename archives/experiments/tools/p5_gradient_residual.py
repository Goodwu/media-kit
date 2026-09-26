#!/usr/bin/env python3
"""Compare RGB16 render/master residuals by master-image local gradient."""

import argparse
import subprocess

import numpy as np


def rgb48(path: str, width: int, height: int) -> np.ndarray:
    output = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb48le", "-"],
        check=True,
        stdout=subprocess.PIPE,
    ).stdout
    values = np.frombuffer(output, dtype="<u2")
    if values.size != width * height * 3:
        raise ValueError(f"Unexpected RGB48 frame size: {path}: {values.size}")
    return values.reshape(height, width, 3)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("master")
    parser.add_argument("render")
    parser.add_argument("--width", type=int, default=3840)
    parser.add_argument("--height", type=int, default=2160)
    parser.add_argument("--stride", type=int, default=8)
    args = parser.parse_args()
    master = rgb48(args.master, args.width, args.height)
    render = rgb48(args.render, args.width, args.height)
    y = np.arange(args.stride // 2, args.height - 1, args.stride)
    x = np.arange(args.stride // 2, args.width - 1, args.stride)
    center = master[np.ix_(y, x)].astype(np.int32)
    actual = render[np.ix_(y, x)].astype(np.int32)
    dx = np.abs(
        master[np.ix_(y, x + 1)].astype(np.int32)
        - master[np.ix_(y, x - 1)].astype(np.int32)
    ).max(axis=2)
    dy = np.abs(
        master[np.ix_(y + 1, x)].astype(np.int32)
        - master[np.ix_(y - 1, x)].astype(np.int32)
    ).max(axis=2)
    gradient = np.maximum(dx, dy).ravel()
    error = np.abs((actual - center).reshape(-1, 3))
    print(f"samples={gradient.size} RGB16_MAE={np.mean(error, axis=0).round(1)}")
    for low, high in ((0, .25), (.25, .5), (.5, .75), (.75, .9), (.9, 1)):
        lower, upper = np.quantile(gradient, (low, high))
        selected = (gradient >= lower) & (gradient <= upper)
        print(
            f"gradient_quantile={low:.2f}-{high:.2f} "
            f"range={lower:.0f}-{upper:.0f} n={selected.sum()} "
            f"RGB16_MAE={np.mean(error[selected], axis=0).round(1)}"
        )


if __name__ == "__main__":
    main()
