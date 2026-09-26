#!/usr/bin/env python3
"""Compare a top-left GBR float32 frame with a bottom-left RGBA half frame.

This is a diagnostic comparator, not a Dolby Vision conformance test.
The caller must independently prove input frame and target-policy identity.
"""

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True,
                        help="top-left GBR planar float32 little-endian frame")
    parser.add_argument("--phone", type=Path, required=True,
                        help="bottom-left RGBA interleaved float16 little-endian frame")
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.width <= 0 or args.height <= 0:
        parser.error("width and height must be positive")
    width, height = args.width, args.height
    expected_host = width * height * 3 * 4
    expected_phone = width * height * 4 * 2
    if args.host.stat().st_size != expected_host:
        parser.error(f"host bytes must be {expected_host}")
    if args.phone.stat().st_size != expected_phone:
        parser.error(f"phone bytes must be {expected_phone}")

    host = np.memmap(args.host, dtype="<f4", mode="r", shape=(3, height, width))
    phone = np.memmap(args.phone, dtype="<f2", mode="r", shape=(height, width, 4))
    report = {
        "host": {"path": str(args.host.resolve()), "sha256": sha256(args.host),
                 "format": "gbrpf32le", "origin": "top-left"},
        "phone": {"path": str(args.phone.resolve()), "sha256": sha256(args.phone),
                  "format": "rgba16f-le", "origin": "bottom-left"},
        "width": width, "height": height, "comparison": "same coordinates after vertical origin conversion",
        "channels": {},
    }
    for name, phone_channel, host_plane in (("R", 0, 2), ("G", 1, 0), ("B", 2, 1)):
        actual = np.asarray(phone[:, :, phone_channel], dtype=np.float32)
        reference = np.asarray(host[host_plane, ::-1, :])
        if not np.isfinite(actual).all() or not np.isfinite(reference).all():
            raise ValueError(f"nonfinite {name} input")
        error = np.abs(actual - reference)
        row, col = np.unravel_index(int(np.argmax(error)), error.shape)
        report["channels"][name] = {
            "mae": float(np.mean(error, dtype=np.float64)),
            "median": float(np.quantile(error, 0.5)),
            "p95": float(np.quantile(error, 0.95)),
            "p99": float(np.quantile(error, 0.99)),
            "max": float(error[row, col]),
            "max_xy": [int(col), int(row)],
            "max_host": float(reference[row, col]),
            "max_phone": float(actual[row, col]),
            "above_0_01": int(np.count_nonzero(error > 0.01)),
            "above_0_05": int(np.count_nonzero(error > 0.05)),
        }
    output = json.dumps(report, indent=2)
    if args.output:
        args.output.write_text(output + "\n")
    print(output)


if __name__ == "__main__":
    main()
