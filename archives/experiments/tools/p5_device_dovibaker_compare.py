#!/usr/bin/env python3
"""Compare the device's actual P5 render output (RGBA16F float readback,
BT.2020/PQ/1000 nit target) against the DoViBaker independent reference at
the same PTS.

The DoViBaker frame is the RPU nonlinear-matrix result; apply the remaining
PQ EOTF, RPU linear matrix, HPE LMS-to-BT.2020 matrix, and PQ OETF (same
chain as tools/p5_dovibaker_compare.py, constants follow libplacebo). The
device readback is interleaved RGBA half-float with GL bottom-origin; the
baker output is top-origin RGB48.
"""

import argparse
import json
import subprocess

import numpy as np

HPE_LMS_TO_BT2020 = np.array(
    [
        [3.06441879, -2.16597676, 0.10155818],
        [-0.65612108, 1.78554118, -0.12943749],
        [0.01736321, -0.04725154, 1.03004253],
    ],
    dtype=np.float64,
)
PQ_M1 = 2610 / 16384
PQ_M2 = 2523 / 32
PQ_C1 = 3424 / 4096
PQ_C2 = 2413 / 128
PQ_C3 = 2392 / 128


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dovi-tool", required=True)
    parser.add_argument("--rpu", required=True)
    parser.add_argument("--frame", type=int, required=True)
    parser.add_argument("--baker-rgb48", required=True)
    parser.add_argument("--device-rgba16f", required=True)
    args = parser.parse_args()

    info = subprocess.check_output(
        [args.dovi_tool, "info", "-i", args.rpu, "-f", str(args.frame)],
        text=True,
    )
    rpu = json.loads(info[info.index("{") :])
    dm = rpu["vdr_dm_data"]
    linear = np.array(
        [dm[f"rgb_to_lms_coef{i}"] for i in range(9)], dtype=np.float64
    ).reshape(3, 3) / 16384
    matrix = HPE_LMS_TO_BT2020 @ linear

    baker = np.memmap(args.baker_rgb48, dtype="<u2", mode="r")
    if baker.size != 3840 * 2160 * 3:
        raise ValueError("DoViBaker frame must be 3840x2160 RGB48")
    baker = baker.reshape(2160, 3840, 3)

    device = np.memmap(args.device_rgba16f, dtype="<f2", mode="r")
    if device.size != 3840 * 2160 * 4:
        raise ValueError("device frame must be 3840x2160 RGBA16F")
    device = device.reshape(2160, 3840, 4)
    device = device[::-1, :, :3]  # GL bottom-origin to top-origin

    stats_abs = np.zeros(3, dtype=np.float64)
    stats_signed = np.zeros(3, dtype=np.float64)
    max_diff = np.zeros(3)
    p99_chunks = [[], [], []]
    for start in range(0, 2160, 60):
        stop = min(start + 60, 2160)
        coded_lms = baker[start:stop].astype(np.float64) / 65535
        powered = coded_lms ** (1 / PQ_M2)
        linear_lms = (
            np.maximum(powered - PQ_C1, 0) / (PQ_C2 - PQ_C3 * powered)
        ) ** (1 / PQ_M1)
        linear_rgb = np.maximum(linear_lms @ matrix.T, 0)
        powered_rgb = linear_rgb ** PQ_M1
        coded_rgb = np.clip(
            ((PQ_C1 + PQ_C2 * powered_rgb) / (1 + PQ_C3 * powered_rgb)) ** PQ_M2,
            0,
            1,
        )
        dev = device[start:stop].astype(np.float64)
        difference = (coded_rgb - dev) * 65535
        stats_abs += np.abs(difference).sum(axis=(0, 1))
        stats_signed += difference.sum(axis=(0, 1))
        max_diff = np.maximum(max_diff, np.abs(difference).max(axis=(0, 1)))
        for c in range(3):
            p99_chunks[c].append(np.abs(difference[:, :, c]).ravel())
        count = (stop) * 3840
    count = 2160 * 3840
    print(f"frame={args.frame} pixels={count}")
    print("RGB16_MAE=", np.round(stats_abs / count, 2).tolist())
    print("RGB16_bias=", np.round(stats_signed / count, 2).tolist())
    print("RGB16_max=", np.round(max_diff, 1).tolist())
    print(
        "RGB16_P99=",
        [round(float(np.percentile(np.concatenate(p99_chunks[c]), 99)), 1) for c in range(3)],
    )


if __name__ == "__main__":
    main()
