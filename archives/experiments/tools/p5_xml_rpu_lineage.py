#!/usr/bin/env python3
"""Compare Sol Levante Dolby XML metadata with exported per-frame P5 RPU JSON.

The Level 1 floors are empirical for this asset. A match establishes metadata
lineage, not identical picture mastering or correct consumer-display color.
"""

import argparse
import json
import math
from pathlib import Path
import xml.etree.ElementTree as ET


LEVEL2_FIELDS = (
    "trim_slope",
    "trim_offset",
    "trim_power",
    "trim_chroma_weight",
    "trim_saturation_gain",
    "ms_weight",
)


def metadata_block(frame, level):
    blocks = frame["vdr_dm_data"]["cmv29_metadata"]["ext_metadata_blocks"]
    return next((block[level] for block in blocks if level in block), None)


def parse_numbers(value):
    return tuple(float(part) for part in value.split(","))


def quantize(value):
    return min(4095, max(0, math.floor(value + 0.5)))


def level2_codes(trim):
    lift, gain, gamma = trim[3:6]
    gamma = min(1.0, max(-1.0, gamma))
    return {
        "trim_slope": quantize(((gain + 2) * (1 - lift / 2) - 2) * 2048 + 2048),
        "trim_offset": quantize((gain + 2) * (lift / 2) * 2048 + 2048),
        "trim_power": quantize((2 / (1 + gamma / 2) - 2) * 2048 + 2048),
        "trim_chroma_weight": quantize(trim[6] * 2048 + 2048),
        "trim_saturation_gain": quantize(trim[7] * 2048 + 2048),
        "ms_weight": quantize(trim[8] * 2048 + 2048),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--xml", type=Path, required=True)
    parser.add_argument("--rpu-json", type=Path, required=True)
    args = parser.parse_args()
    rpus = json.loads(args.rpu_json.read_text())
    shots = ET.parse(args.xml).findall(".//Shot")
    timeline = [None] * len(rpus)
    starts = []
    override_count = 0
    previous_end = 0
    for shot in shots:
        start = int(shot.findtext("Record/In"))
        duration = int(shot.findtext("Record/Duration"))
        if start != previous_end or start + duration > len(timeline):
            raise ValueError(f"non-contiguous shot at {start}")
        starts.append(start)
        current_l1 = parse_numbers(
            shot.findtext('./PluginNode/DolbyEDR[@level="1"]/ImageCharacter')
        )
        current_l2 = parse_numbers(
            shot.findtext('./PluginNode/DolbyEDR[@level="2"]/Trim')
        )
        overrides = {}
        for frame in shot.findall("Frame"):
            offset = int(frame.findtext("EditOffset"))
            if offset < 0 or offset >= duration or offset in overrides:
                raise ValueError(f"invalid frame override at {start}+{offset}")
            overrides[offset] = (
                parse_numbers(
                    frame.findtext('./PluginNode/DolbyEDR[@level="1"]/ImageCharacter')
                ),
                parse_numbers(frame.findtext('./PluginNode/DolbyEDR[@level="2"]/Trim')),
            )
        override_count += len(overrides)
        for offset in range(duration):
            if offset in overrides:
                current_l1, current_l2 = overrides[offset]
            timeline[start + offset] = (current_l1, current_l2)
        previous_end = start + duration
    if previous_end != len(rpus):
        raise ValueError(f"XML covers {previous_end} frames, RPU has {len(rpus)}")
    actual_starts = [
        i for i, rpu in enumerate(rpus)
        if rpu["vdr_dm_data"]["scene_refresh_flag"] == 1
    ]

    result = {
        "frames": len(rpus),
        "shots": len(shots),
        "frame_overrides": override_count,
        "scene_starts_match": len(set(starts) & set(actual_starts)),
        "scene_starts_exact": starts == actual_starts,
        "level1_avg_exact": 0,
        "level1_max_exact": 0,
        "level2_active_exact": 0,
        "level2_codes_exact": 0,
        "level2_active_frames": 0,
        "level2_target_max_pq_2081": 0,
    }
    mismatches = []
    if starts != actual_starts:
        mismatches.append(("scene_starts", "XML and RPU lists differ"))
    for i, (xml_l1, xml_l2) in enumerate(timeline):
        l1 = metadata_block(rpus[i], "Level1")
        l2 = metadata_block(rpus[i], "Level2")
        if l1 is None or l2 is None:
            mismatches.append((i, "missing Level1 or Level2"))
            continue
        expected_avg = max(819, round(xml_l1[1] * 4095))
        expected_max = max(2081, round(xml_l1[2] * 4095))
        xml_active = any(value != 0 for value in xml_l2)
        rpu_active = any(l2[field] != 2048 for field in LEVEL2_FIELDS)
        if l1["avg_pq"] == expected_avg:
            result["level1_avg_exact"] += 1
        else:
            mismatches.append((i, "Level1 avg"))
        if l1["max_pq"] == expected_max:
            result["level1_max_exact"] += 1
        else:
            mismatches.append((i, "Level1 max"))
        if xml_active == rpu_active:
            result["level2_active_exact"] += 1
        else:
            mismatches.append((i, "Level2 activity"))
        if all(l2[field] == code for field, code in level2_codes(xml_l2).items()):
            result["level2_codes_exact"] += 1
        else:
            mismatches.append((i, "Level2 codes"))
        result["level2_active_frames"] += int(xml_active)
        result["level2_target_max_pq_2081"] += int(l2["target_max_pq"] == 2081)
    result["mismatch_count"] = len(mismatches)
    result["first_mismatches"] = mismatches[:10]
    print(json.dumps(result, indent=2))
    if mismatches:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
