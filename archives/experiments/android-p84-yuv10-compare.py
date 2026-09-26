#!/usr/bin/env python3
"""Compare GPU raw-YUV samples with selected software HEVC frames.

The raw file is produced with:
ffmpeg -i SOURCE -vf "select='eq(n,0)+eq(n,103)+eq(n,204)'" \
  -fps_mode passthrough -frames:v 3 -pix_fmt yuv420p10le -f rawvideo FRAMES
"""

import argparse
from array import array
from pathlib import Path
import re
import sys


WIDTH, HEIGHT = 3840, 1920
DEFAULT_FRAME_INDICES = (0, 103, 204)
DEFAULT_PTS_US = (0, 3436766, 6806800)
XS = (0.1, 0.3, 0.5, 0.7, 0.9)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("log", type=Path)
    parser.add_argument("frames", type=Path)
    parser.add_argument("--indices", type=int, nargs=3,
                        default=DEFAULT_FRAME_INDICES)
    parser.add_argument("--pts-us", type=int, nargs=3,
                        default=DEFAULT_PTS_US)
    args = parser.parse_args()
    lines = [line for line in args.log.read_text().splitlines()
             if "P5_CODEC_PROBE image=" in line]
    assert len(lines) == len(args.indices), len(lines)
    samples = array("H")
    with args.frames.open("rb") as stream:
        samples.frombytes(stream.read())
    if sys.byteorder != "little":
        samples.byteswap()
    area = WIDTH * HEIGHT
    frame_size = area * 3 // 2
    assert len(samples) == len(args.indices) * frame_size, len(samples)
    raw_deltas = []
    scaled_deltas = []
    for index, line in enumerate(lines):
        pts = int(re.search(r"timestampAsPtsUs: (\d+)", line).group(1))
        assert pts == args.pts_us[index], (index, pts)
        gpu = [tuple(map(int, match)) for match in re.findall(
            r"x10-[\d.]+=(\d+),(\d+),(\d+)", line.split("rawYuvFull=")[1])]
        assert len(gpu) == len(XS), (index, gpu)
        base = index * frame_size
        print(f"software_frame={args.indices[index]} pts_us={pts}")
        for x, values in zip(XS, gpu):
            px = int(x * WIDTH)
            py = HEIGHT // 2
            reference = (
                samples[base + py * WIDTH + px],
                samples[base + area + (py // 2) * (WIDTH // 2) + px // 2],
                samples[base + area + area // 4 + (py // 2) * (WIDTH // 2) + px // 2],
            )
            delta = tuple(a - b for a, b in zip(values, reference))
            scaled_delta = tuple(a - round(b * 1023 / 1020)
                                 for a, b in zip(values, reference))
            raw_deltas.extend(delta)
            scaled_deltas.extend(scaled_delta)
            print(f"  x={x}: gpu={values} software={reference} "
                  f"delta={delta} scaled_delta={scaled_delta}")
    print(f"components={len(raw_deltas)} raw_delta={sorted(set(raw_deltas))} "
          f"scaled_delta={sorted(set(scaled_deltas))}")


if __name__ == "__main__":
    main()
