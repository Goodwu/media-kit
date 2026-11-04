#!/usr/bin/env python3
"""Analyze LG P84 GPU timing rounds produced by lg_p84_instant_perf.py.

Parses each round directory's flutter-logcat.txt for the mpv MKS GPU timing
records (MKS-GPU-SAMPLES / MKS-GPU-PASS / MKS-GPU counters) and the round
summary for validity gates. Timing categories come from separate sessions and
are never combined into a per-frame total; frequency normalization is the
round's stable-window median gpuclk. The PTS window is a fixed analysis
convention, not a measurement guarantee.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import re
import statistics
import sys
from typing import Any

SAMPLES_RE = re.compile(
    r"MKS-GPU-SAMPLES kind=(?P<kind>\S+) instance=(?P<instance>\S+) pid=(?P<pid>\d+) "
    r"start_ns=(?P<start>-?\d+) count=(?P<count>\d+) data=(?P<data>\S*)")
SAMPLE_ITEM_RE = re.compile(
    r"^(?P<seq>\d+):(?P<pts>-?\d+(?:\.\d+)?):(?P<issue>-?\d+):(?P<ns>\d+)$")
PASS_RE = re.compile(
    r"MKS-GPU-PASS instance=(?P<instance>\S+) mono_ns=(?P<mono>-?\d+) final=(?P<final>\d) "
    r"stage=(?P<stage>\S+) index=(?P<index>\d+) signature=(?P<sig>\d+) samples=(?P<samples>\d+) "
    r"last_ns=(?P<last>\d+) avg_ns=(?P<avg>\d+) peak_ns=(?P<peak>\d+) "
    r"callback_frame_id=(?P<frame_id>\d+) callback_pts=(?P<pts>-?\d+(?:\.\d+)?) "
    r"attribution=rolling-history desc=(?P<desc>.*)$")
COUNTER_RE = re.compile(
    r"MKS-GPU kind=(?P<kind>\S+) instance=(?P<instance>\S+) pid=(?P<pid>\d+) "
    r"start_ns=(?P<start>-?\d+) mono_ns=(?P<mono>-?\d+) final=(?P<final>\d) "
    r"attempts=(?P<attempts>\d+) issued=(?P<issued>\d+) results=(?P<results>\d+) "
    r"sum_ns=(?P<sum>\d+) min_ns=(?P<min>\d+) max_ns=(?P<max>\d+) "
    r"disjoint_drop=(?P<disjoint>\d+) ring_full=(?P<ring>\d+) nested_skip=(?P<nested>\d+) "
    r"context_skip=(?P<ctx>\d+) pending_drop=(?P<pending>\d+) begin_failed=(?P<begin>\d+)")
UNSUPPORTED_RE = re.compile(r"MKS-GPU kind=(?P<kind>\S+) supported=0 reason=(?P<reason>\S+)")


def parse_logcat(path: Path) -> dict[str, Any]:
    samples: list[dict[str, Any]] = []
    passes: list[dict[str, Any]] = []
    counters: dict[str, dict[str, Any]] = {}
    unsupported: dict[str, str] = {}
    for line in path.read_text(errors="replace").splitlines():
        for match in SAMPLES_RE.finditer(line):
            for item in match.group("data").split(","):
                fields = SAMPLE_ITEM_RE.match(item)
                if fields:
                    samples.append({"kind": match.group("kind"),
                                    "seq": int(fields.group("seq")),
                                    "pts": float(fields.group("pts")),
                                    "issue_ns": int(fields.group("issue")),
                                    "elapsed_ns": int(fields.group("ns"))})
        for match in PASS_RE.finditer(line):
            passes.append({"stage": match.group("stage"), "index": int(match.group("index")),
                           "samples": int(match.group("samples")), "last_ns": int(match.group("last")),
                           "avg_ns": int(match.group("avg")), "peak_ns": int(match.group("peak")),
                           "callback_pts": float(match.group("pts")), "desc": match.group("desc").strip()})
        for match in COUNTER_RE.finditer(line):
            row = {key: int(value) for key, value in match.groupdict().items() if key in
                   ("attempts", "issued", "results", "sum", "min", "max", "disjoint",
                    "ring", "nested", "ctx", "pending", "begin")}
            counters[match.group("kind")] = row  # counters are cumulative; keep the last
        for match in UNSUPPORTED_RE.finditer(line):
            unsupported[match.group("kind")] = match.group("reason")
    return {"samples": samples, "passes": passes, "counters": counters, "unsupported": unsupported}


def stats(values: list[float]) -> dict[str, Any] | None:
    if not values:
        return None
    ordered = sorted(values)
    return {"count": len(values), "min": ordered[0],
            "median": statistics.median(values), "mean": statistics.fmean(values),
            "max": ordered[-1]}


def window_metrics_ns(values: list[float]) -> dict[str, Any] | None:
    return None if not values else {
        "count": len(values), **{key: value / 1e6 for key, value in stats(values).items()
                                 if key != "count"}}


def load_summary(output: Path, expected_backlight: str,
                 expected_thermal: str) -> dict[str, Any]:
    summary = json.loads((output / "instant-summary.json").read_text())
    round_summary = json.loads((output / "summary.json").read_text())
    initial = round_summary.get("initial") or {}
    hz = summary.get("gpuFrequencyHz") or {}
    gates_ok = (summary.get("validCompletedProfile") is True and
                str(round_summary.get("expectedBacklight")) == str(expected_backlight) and
                str(round_summary.get("expectedPanelThermalStatus")) == str(expected_thermal))
    return {"gatesOk": gates_ok,
            "status": summary.get("controllerStatus"),
            "reason": summary.get("controllerReason"),
            "validCompletedProfile": summary.get("validCompletedProfile"),
            "metricsAreDiagnosticOnly": summary.get("metricsAreDiagnosticOnly"),
            "stableSamples": summary.get("stableSamples"),
            "gpuFrequencyHzMedian": hz.get("median"),
            "gpuBusyPercentMedian": (summary.get("gpuDriverReportedBusyPercent") or {}).get("median"),
            "processCPUPercentMedian": (summary.get("processCPUPercentOneCore100") or {}).get("median"),
            "startBatteryC": initial.get("batteryC"), "startVtsC": initial.get("vtsC")}


def analyze_round(directory: Path, window: tuple[float, float], expected_backlight: str,
                  expected_thermal: str) -> dict[str, Any]:
    logcat = parse_logcat(directory / "flutter-logcat.txt")
    result: dict[str, Any] = {"directory": str(directory),
                              **load_summary(directory, expected_backlight, expected_thermal),
                              "timerUnsupported": logcat["unsupported"] or None,
                              "counters": logcat["counters"] or None}
    low, high = window
    kinds: dict[str, list[float]] = {}
    for row in logcat["samples"]:
        if low <= row["pts"] <= high:
            kinds.setdefault(row["kind"], []).append(row["elapsed_ns"])
    result["drawSamples"] = {kind: window_metrics_ns(values) for kind, values in kinds.items()}
    passes: dict[tuple[str, int], list[dict[str, Any]]] = {}
    for row in logcat["passes"]:
        if row["stage"] == "frame" and low <= row["callback_pts"] <= high:
            passes.setdefault(("frame", row["index"]), []).append(row)
    pass_metrics: dict[str, dict[str, Any]] = {}
    for (stage, index), rows in sorted(passes.items()):
        avgs = [row["avg_ns"] for row in rows]
        primary = max(rows, key=lambda row: row["samples"])
        pass_metrics[f"index{index}"] = {
            "checkpoints": len(rows), "avgNsPerCheckpoint": window_metrics_ns(avgs),
            "primaryDesc": primary["desc"], "primarySamples": primary["samples"],
            "primaryAvgNs": primary["avg_ns"], "primaryLastNs": primary["last_ns"],
            "primaryPeakNs": primary["peak_ns"]}
    result["rendererPasses"] = pass_metrics or None
    hz = result.get("gpuFrequencyHzMedian")
    if hz:
        mhz = hz / 1e6
        normalized: dict[str, Any] = {}
        for kind, metrics in result["drawSamples"].items():
            if metrics:
                normalized[kind] = {"medianMcycles": metrics["median"] * mhz / 1e3}
        for name, metrics in pass_metrics.items():
            if metrics.get("avgNsPerCheckpoint"):
                normalized[name] = {"medianMcycles": metrics["avgNsPerCheckpoint"]["median"] * mhz / 1e3}
        result["frequencyNormalized"] = normalized or None
    return result


def share(input_label: str, renderer_label: str, rounds: dict[str, dict[str, Any]],
          renderer_pass: str) -> dict[str, Any]:
    for label in (input_label, renderer_label):
        if not rounds.get(label, {}).get("gatesOk"):
            return {"error": f"round {label} failed validity/backlight/thermal gates; "
                             "refusing a share over it", "inputLabel": input_label,
                    "rendererLabel": renderer_label}
    inp = rounds[input_label].get("frequencyNormalized") or {}
    ref = rounds[renderer_label].get("frequencyNormalized") or {}
    input_cycles = next((metrics["medianMcycles"] for name, metrics in inp.items()
                         if name.startswith("input") or name.startswith("final-yuv")), None)
    fused = (ref.get(renderer_pass) or {}).get("medianMcycles")
    if input_cycles is None or fused is None:
        return {"error": "missing normalized timing for share computation",
                "inputLabel": input_label, "rendererLabel": renderer_label}
    total = input_cycles + fused
    return {"inputLabel": input_label, "rendererLabel": renderer_label,
            "inputMcycles": input_cycles, "fusedRendererMcycles": fused,
            "inputShare": input_cycles / total, "fusedShare": fused / total,
            "caveat": "input and renderer timings come from separate sessions; the sum is an "
                      "occupancy estimate, not a measured per-frame total"}


def pair(baseline_label: str, candidate_label: str, rounds: dict[str, dict[str, Any]],
         renderer_pass: str | None) -> dict[str, Any]:
    def metric(label: str) -> tuple[str, float] | None:
        if not rounds.get(label, {}).get("gatesOk"):
            return None, None
        normalized = rounds.get(label, {}).get("frequencyNormalized") or {}
        if renderer_pass:
            if renderer_pass not in normalized:
                return None, None  # no silent fallback to another pass key
            return renderer_pass, normalized[renderer_pass]["medianMcycles"]
        for name in sorted(normalized):
            return name, normalized[name]["medianMcycles"]
        return None, None

    base_name, base_value = metric(baseline_label)
    cand_name, cand_value = metric(candidate_label)
    if not base_value or not cand_value:
        return {"error": "missing normalized timing for pair", "baseline": baseline_label,
                "candidate": candidate_label}
    if base_name != cand_name:
        return {"error": f"pair refuses different metrics: {base_name} vs {cand_name}",
                "baseline": baseline_label, "candidate": candidate_label}
    return {"baseline": baseline_label, "baselineMetric": base_name, "baselineMcycles": base_value,
            "candidate": candidate_label, "candidateMetric": cand_name, "candidateMcycles": cand_value,
            "reduction": 1 - cand_value / base_value}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--round", action="append", required=True, metavar="LABEL=DIR",
                        help="round label and instant-perf output directory; repeatable")
    parser.add_argument("--window", nargs=2, type=float, default=(20.0, 55.0), metavar=("START", "END"),
                        help="source PTS analysis window in seconds (default 20 55)")
    parser.add_argument("--expected-backlight", default="64")
    parser.add_argument("--expected-panel-thermal-status", default="0")
    parser.add_argument("--renderer-pass", default=None,
                        help="renderer pass key for pair/share (e.g. index0); default first index")
    parser.add_argument("--share", nargs=2, metavar=("INPUT_LABEL", "RENDERER_LABEL"))
    parser.add_argument("--pair", nargs=2, metavar=("BASELINE_LABEL", "CANDIDATE_LABEL"))
    parser.add_argument("--output", type=Path, help="write JSON here in addition to stdout")
    args = parser.parse_args()
    rounds: dict[str, dict[str, Any]] = {}
    for item in args.round:
        label, _, directory = item.partition("=")
        if not label or not directory:
            parser.error("--round requires LABEL=DIR")
        rounds[label] = analyze_round(Path(directory), tuple(args.window),
                                      args.expected_backlight, args.expected_panel_thermal_status)
    result: dict[str, Any] = {
        "windowPts": list(args.window),
        "limitations": [
            "input/yuv and renderer timings come from separate sessions and never form a per-frame total",
            "renderer pass numbers are rolling 256-sample histories at ~10s checkpoints, not per-frame attribution",
            "frequency normalization uses the round's stable-window median gpuclk; DVFS is not controlled",
            "timing instrumentation itself has overhead; compare only against rounds with the same mode"],
        "rounds": rounds}
    if args.share:
        result["share"] = share(args.share[0], args.share[1], rounds,
                                args.renderer_pass or "index0")
    if args.pair:
        result["pair"] = pair(args.pair[0], args.pair[1], rounds, args.renderer_pass)
    text = json.dumps(result, indent=2, sort_keys=True)
    if args.output:
        args.output.write_text(text + "\n")
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
