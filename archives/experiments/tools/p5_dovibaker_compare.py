#!/usr/bin/env python3
"""Compare one DoViBaker intermediate frame with mpv and optional VDM.

DoViBaker's P5 frame output in this experiment is the RPU nonlinear-matrix
result. Apply the remaining PQ EOTF, RPU linear matrix, HPE LMS-to-BT.2020
matrix, and PQ OETF before comparing it with a BT.2020/PQ image. This checks
the independent reshape path; the final HPE matrix follows libplacebo and is
therefore not an independent end-to-end color reference. The optional VDM
comparison also assumes that the TIFF is P3-D65/PQ/full-range as published;
identical image mastering between the MP4 and TIFF is unproven.
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


def rgb_to_xyz(primaries: list[tuple[float, float]]) -> np.ndarray:
    white_xy = (0.3127, 0.3290)
    white = np.array(
        [white_xy[0] / white_xy[1], 1, (1 - sum(white_xy)) / white_xy[1]]
    )
    chromaticities = np.array(
        [[x / y, 1, (1 - x - y) / y] for x, y in primaries]
    ).T
    return chromaticities @ np.diag(np.linalg.solve(chromaticities, white))


BT2020_TO_P3 = np.linalg.solve(
    rgb_to_xyz([(0.680, 0.320), (0.265, 0.690), (0.150, 0.060)]),
    rgb_to_xyz([(0.708, 0.292), (0.170, 0.797), (0.131, 0.046)]),
)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dovi-tool", required=True)
    parser.add_argument("--rpu", required=True)
    parser.add_argument("--frame", type=int, required=True)
    parser.add_argument("--baker-rgb48", required=True)
    parser.add_argument("--mpv-png", required=True)
    parser.add_argument("--vdm-tiff")
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
    mpv_bytes = subprocess.check_output(
        [
            "ffmpeg", "-v", "error", "-i", args.mpv_png, "-frames:v", "1",
            "-pix_fmt", "rgba64le", "-f", "rawvideo", "-",
        ]
    )
    mpv = np.frombuffer(mpv_bytes, dtype="<u2")
    if mpv.size != 3840 * 2160 * 4:
        raise ValueError("mpv image must be 3840x2160 RGBA64")
    mpv = mpv.reshape(2160, 3840, 4)[:, :, :3]

    vdm = None
    if args.vdm_tiff:
        vdm_bytes = subprocess.check_output(
            [
                "ffmpeg", "-v", "error", "-i", args.vdm_tiff,
                "-frames:v", "1", "-pix_fmt", "rgb48le", "-f", "rawvideo", "-",
            ]
        )
        vdm = np.frombuffer(vdm_bytes, dtype="<u2")
        if vdm.size != 3840 * 2160 * 3:
            raise ValueError("VDM image must be 3840x2160 RGB48")
        vdm = vdm.reshape(2160, 3840, 3)

    absolute_sum = np.zeros(3, dtype=np.float64)
    signed_sum = np.zeros(3, dtype=np.float64)
    vdm_absolute_sum = np.zeros(3, dtype=np.float64)
    vdm_signed_sum = np.zeros(3, dtype=np.float64)
    count = 0
    for start in range(0, 2160, 80):
        stop = min(start + 80, 2160)
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
        ) * 65535
        difference = coded_rgb - mpv[start:stop].astype(np.float64)
        absolute_sum += np.abs(difference).sum(axis=(0, 1))
        signed_sum += difference.sum(axis=(0, 1))
        if vdm is not None:
            linear_p3 = np.maximum(linear_rgb @ BT2020_TO_P3.T, 0)
            powered_p3 = linear_p3 ** PQ_M1
            coded_p3 = np.clip(
                ((PQ_C1 + PQ_C2 * powered_p3) / (1 + PQ_C3 * powered_p3)) ** PQ_M2,
                0,
                1,
            ) * 65535
            vdm_difference = coded_p3 - vdm[start:stop].astype(np.float64)
            vdm_absolute_sum += np.abs(vdm_difference).sum(axis=(0, 1))
            vdm_signed_sum += vdm_difference.sum(axis=(0, 1))
        count += (stop - start) * 3840
    print(f"frame={args.frame}")
    print("RGB16_MAE=", np.round(absolute_sum / count, 2).tolist())
    print("RGB16_bias=", np.round(signed_sum / count, 2).tolist())
    if vdm is not None:
        print("VDM_P3_RGB16_MAE=", np.round(vdm_absolute_sum / count, 2).tolist())
        print("VDM_P3_RGB16_bias=", np.round(vdm_signed_sum / count, 2).tolist())


if __name__ == "__main__":
    main()
