#!/usr/bin/env python3
"""Freeze the observed P5 mapping contract from a complete VO log.

This is an engineering policy identity, not a Dolby conformance reference.
Input/APK/native hashes must be measured independently and supplied by caller.
"""

import argparse
import gzip
import hashlib
import json
import re
import sys
from pathlib import Path


SECTIONS = {
    "color": {
        "source_sys", "source_prim", "source_trc", "source_hdr_min",
        "source_hdr_max", "source_max_cll", "source_nominal_nits",
        "target_prim", "target_trc", "target_hdr_min", "target_hdr_max",
        "target_nominal_nits",
    },
    "map": {
        "tone", "tone_param", "gamut", "gamut_mode", "intent", "metadata",
        "lut_size", "lut3d", "tricubic", "gamut_expansion", "inverse",
        "contrast_recovery", "contrast_smoothness", "force_lut",
        "visualize", "show_clipping",
    },
    "tone_constants": {
        "knee_adaptation", "knee_minimum", "knee_maximum", "knee_default",
        "knee_offset", "slope_tuning", "slope_offset", "spline_contrast",
        "reinhard_contrast", "linear_knee", "exposure",
    },
    "gamut_constants": {
        "perceptual_deadzone", "perceptual_strength", "colorimetric_gamma",
        "softclip_knee", "softclip_desat", "peak_enabled", "peak_smoothing",
        "peak_scene_low", "peak_scene_high", "peak_percentile",
        "peak_black_cutoff", "peak_delayed",
    },
    "render": {
        "dither_enabled", "dither_method", "dither_lut",
        "dither_temporal", "dither_transfer", "error_diffusion",
        "target_bits_color", "target_bits_sample",
    },
}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
POLICY_TAG_RE = re.compile(r"\bP5_POLICY(?:\([^)]*\))?:\s*")


def read_log(path: Path):
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rt", errors="replace") as stream:
        yield from stream


def extract(log_lines):
    groups = []
    current = {}
    diagnostic = set()
    for line in log_lines:
        if match := re.search(r"\b(P5_PERF_[A-Z_]+)\b", line):
            diagnostic.add(match[1])
        tag = POLICY_TAG_RE.search(line)
        if not tag:
            continue
        payload = line[tag.end():].strip()
        section, _, fields = payload.partition(" ")
        if section not in SECTIONS:
            raise ValueError(f"unknown P5_POLICY section: {section}")
        if section == "color" and current:
            groups.append(current)
            current = {}
        if section in current:
            raise ValueError(f"duplicate P5_POLICY section: {section}")
        parsed = {}
        for field in fields.split():
            key, separator, value = field.partition("=")
            if not separator or not value or key in parsed:
                raise ValueError(f"malformed P5_POLICY field: {field}")
            parsed[key] = value
        if set(parsed) != SECTIONS[section]:
            raise ValueError(
                f"P5_POLICY {section} fields differ: "
                f"missing={sorted(SECTIONS[section] - set(parsed))} "
                f"extra={sorted(set(parsed) - SECTIONS[section])}"
            )
        current[section] = parsed
    if current:
        groups.append(current)
    if diagnostic:
        raise ValueError(f"diagnostic render path: {sorted(diagnostic)}")
    if not groups:
        raise ValueError("no P5_POLICY records")
    if any(set(group) != set(SECTIONS) for group in groups):
        raise ValueError("incomplete P5_POLICY group")
    if any(group != groups[0] for group in groups[1:]):
        raise ValueError("conflicting P5_POLICY groups")
    return groups[0], len(groups)


def sha_arg(value: str):
    value = value.lower()
    if not SHA256_RE.fullmatch(value):
        raise argparse.ArgumentTypeError("expected 64 hexadecimal SHA-256 digits")
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--source-sha256", type=sha_arg, required=True)
    parser.add_argument("--apk-sha256", type=sha_arg, required=True)
    parser.add_argument("--libmpv-sha256", type=sha_arg, required=True)
    parser.add_argument("--target-id", required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        observed, occurrences = extract(read_log(args.log))
    except ValueError as error:
        parser.error(str(error))
    contract = {
        "schema": "p5-engineering-policy-v2",
        "source_sha256": args.source_sha256,
        "apk_sha256": args.apk_sha256,
        "libmpv_sha256": args.libmpv_sha256,
        "target_id": args.target_id,
        "observed": observed,
    }
    canonical = json.dumps(contract, sort_keys=True, separators=(",", ":"))
    result = {
        "engineering_policy_id": "sha256:" + hashlib.sha256(canonical.encode()).hexdigest(),
        "policy_occurrences": occurrences,
        "contract": contract,
        "reference_level": "observed-engineering-policy; not Dolby conformance",
    }
    rendered = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.write_text(rendered)
    else:
        sys.stdout.write(rendered)
    return 0


if __name__ == "__main__":
    sys.exit(main())
