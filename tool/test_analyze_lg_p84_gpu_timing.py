#!/usr/bin/env python3
"""Tests for analyze_lg_p84_gpu_timing.py (offline fixtures + archived log)."""
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import analyze_lg_p84_gpu_timing as analyzer

HERE = Path(__file__).resolve().parent
ARCHIVED_RENDER = HERE / "fixtures/mks-gpu-pass-render-A.log.txt"


def sample_log(kind: str = "input-copy") -> list[str]:
    data = ",".join(f"{seq}:{20.5 + seq * 0.5:.9f}:{1000000 + seq}:{5_000_000 + seq * 100}"
                    for seq in range(1, 9))
    return [
        "10-30 01:27:57.674  6673  6673 I flutter : MPVLOG [vo/gpu-next] error: "
        f"MKS-GPU kind={kind} supported=1 bits=40 ring=16 scope=elapsed-draw",
        "10-30 01:27:58.000  6673  6673 I flutter : MPVLOG [vo/gpu-next] error: "
        f"MKS-GPU-SAMPLES kind={kind} instance=0x1 pid=6673 start_ns=1 count=8 data={data}",
        "10-30 01:27:59.000  6673  6673 I flutter : MPVLOG [vo/gpu-next] error: "
        f"MKS-GPU kind={kind} instance=0x1 pid=6673 start_ns=1 mono_ns=2 final=0 attempts=8 "
        f"issued=8 results=8 sum_ns=40000000 min_ns=5000000 max_ns=5000700 disjoint_drop=0 "
        f"ring_full=0 nested_skip=0 context_skip=0 pending_drop=0 begin_failed=0",
        "10-30 01:28:07.674  6673  6673 I flutter : MPVLOG [vo/gpu-next] error: "
        "MKS-GPU-PASS instance=0x2 mono_ns=15569184380 final=0 stage=frame index=0 "
        "signature=3009792244357468632 samples=256 last_ns=7705885 avg_ns=8100108 peak_ns=9520261 "
        "callback_frame_id=329 callback_pts=29.476133333 attribution=rolling-history "
        "desc=color decoding, color encoding",
    ]


INSTANT = {"controllerStatus": "completed-observation", "controllerReason": None,
           "validCompletedProfile": True, "metricsAreDiagnosticOnly": False,
           "stableSamples": 24, "gpuFrequencyHz": {"median": 300_000_000.0},
           "gpuDriverReportedBusyPercent": {"median": 60.0},
           "processCPUPercentOneCore100": {"median": 55.0}}
SUMMARY = {"initial": {"batteryC": 26.2, "vtsC": 32.0},
           "expectedBacklight": "64", "expectedPanelThermalStatus": "0"}


class AnalyzerTests(unittest.TestCase):
    def write_round(self, root: Path, log_lines, instant=INSTANT, summary=SUMMARY) -> Path:
        root.mkdir(parents=True)
        (root / "flutter-logcat.txt").write_text("\n".join(log_lines) + "\n")
        (root / "instant-summary.json").write_text(json.dumps(instant))
        (root / "summary.json").write_text(json.dumps(summary))
        return root

    def analyze(self, root: Path) -> dict:
        return analyzer.analyze_round(root, (20.0, 55.0), "64", "0")

    def test_parse_samples_pass_and_normalization(self):
        with tempfile.TemporaryDirectory() as d:
            result = self.analyze(self.write_round(Path(d) / "r1", sample_log()))
        self.assertEqual(result["status"], "completed-observation")
        self.assertEqual(result["startBatteryC"], 26.2)
        self.assertEqual(result["gpuFrequencyHzMedian"], 300_000_000.0)
        samples = result["drawSamples"]["input-copy"]
        self.assertEqual(samples["count"], 8)
        self.assertAlmostEqual(samples["median"], 5.00045, places=6)
        counters = result["counters"]["input-copy"]
        self.assertEqual(counters["results"], 8)
        self.assertEqual(counters["disjoint"], 0)
        pas = result["rendererPasses"]["index0"]
        self.assertEqual(pas["checkpoints"], 1)
        self.assertEqual(pas["primaryAvgNs"], 8_100_108)
        self.assertIn("color decoding", pas["primaryDesc"])
        normalized = result["frequencyNormalized"]
        self.assertAlmostEqual(normalized["input-copy"]["medianMcycles"],
                               samples["median"] * 300 / 1e3)
        self.assertAlmostEqual(normalized["index0"]["medianMcycles"], 8.100108 * 300 / 1e3)

    def test_window_filter_excludes_out_of_window(self):
        lines = sample_log() + [
            "10-30 01:28:00.000  6673  6673 I flutter : MPVLOG [vo/gpu-next] error: "
            "MKS-GPU-SAMPLES kind=input-copy instance=0x1 pid=6673 start_ns=1 count=2 "
            "data=1:70.0:5:1234,2:-1.0:6:2345"]
        with tempfile.TemporaryDirectory() as d:
            result = self.analyze(self.write_round(Path(d) / "r2", lines))
        self.assertEqual(result["drawSamples"]["input-copy"]["count"], 8)

    def test_share_and_pair(self):
        with tempfile.TemporaryDirectory() as d:
            rounds = {label: self.analyze(self.write_round(Path(d) / label, sample_log(kind)))
                      for label, kind in (("inp", "input-copy"), ("ref", "final-yuv"))}
        share = analyzer.share("inp", "ref", rounds, "index0")
        self.assertGreater(share["inputShare"], 0)
        self.assertLess(share["inputShare"], 1)
        self.assertAlmostEqual(share["inputShare"] + share["fusedShare"], 1.0)
        # both fixture rounds carry index0 checkpoints; the input-copy vs
        # final-yuv sample metrics must NOT be silently paired
        self.assertIn("error", analyzer.pair("inp", "ref", rounds, None))
        pair = analyzer.pair("inp", "ref", rounds, "index0")
        self.assertLess(pair["reduction"], 1)
        self.assertIn("error", analyzer.pair("inp", "missing", rounds, None))

    def test_share_refuses_invalid_round_and_missing_pass(self):
        invalid_instant = dict(INSTANT, validCompletedProfile=False)
        with tempfile.TemporaryDirectory() as d:
            good = self.write_round(Path(d) / "good", sample_log())
            bad = self.write_round(Path(d) / "bad", sample_log(), instant=invalid_instant)
            rounds = {label: self.analyze(root)
                      for label, root in (("good", good), ("bad", bad))}
        self.assertIn("error", analyzer.share("bad", "good", rounds, "index0"))
        self.assertIn("error", analyzer.share("good", "bad", rounds, "index0"))
        # exact renderer_pass is required: no silent fallback to another index
        self.assertIn("error", analyzer.share("good", "good", rounds, "index7"))

    def test_pair_refuses_cross_metric_and_missing_pass_never_raises(self):
        with tempfile.TemporaryDirectory() as d:
            inp = self.write_round(Path(d) / "inp", sample_log())  # input-copy only
            ref = self.write_round(Path(d) / "ref", sample_log())  # input-copy only
            rounds = {label: self.analyze(root)
                      for label, root in (("inp", inp), ("ref", ref))}
        # same metric on both sides pairs fine
        self.assertNotIn("error", analyzer.pair("inp", "ref", rounds, None))
        # a renderer-only round paired against an input round must be refused,
        # not silently compared across metrics
        renderer_only = json.loads(json.dumps(rounds["ref"]))
        renderer_only["frequencyNormalized"] = {"index7": {"medianMcycles": 2.0}}
        mixed = {**rounds, "ref2": renderer_only}
        self.assertIn("error", analyzer.pair("inp", "ref2", None) if False else
                      analyzer.pair("inp", "ref2", mixed, None))
        # a requested pass missing from a gatesOk round errors without raising
        self.assertIn("error", analyzer.pair("inp", "ref2", mixed, "index0"))

    def test_unsupported_timer_recorded(self):
        lines = ["10-30 01:27:57.674 6673 6673 I flutter : MPVLOG [vo/gpu-next] error: "
                 "MKS-GPU kind=input-copy supported=0 reason=entrypoints-or-extension"]
        with tempfile.TemporaryDirectory() as d:
            result = self.analyze(self.write_round(Path(d) / "r3", lines))
        self.assertEqual(result["timerUnsupported"],
                         {"input-copy": "entrypoints-or-extension"})
        self.assertEqual(result["drawSamples"], {})

    def test_archived_render_log_regression(self):
        parsed = analyzer.parse_logcat(ARCHIVED_RENDER)
        self.assertEqual(parsed["samples"], [])
        self.assertTrue(parsed["passes"])
        first = parsed["passes"][0]
        self.assertEqual((first["stage"], first["index"], first["samples"]), ("frame", 0, 256))
        self.assertTrue(7e6 < first["avg_ns"] < 9e6)
        # render-mode counters live on the libplacebo side; their absence is tolerated
        self.assertEqual(parsed["counters"], {})

    def test_main_end_to_end(self):
        with tempfile.TemporaryDirectory() as d:
            self.write_round(Path(d) / "rA", sample_log())
            output = Path(d) / "out.json"
            argv = sys.argv
            sys.argv = ["analyze_lg_p84_gpu_timing.py", "--round", f"A={Path(d) / 'rA'}",
                        "--output", str(output)]
            try:
                self.assertEqual(analyzer.main(), 0)
            finally:
                sys.argv = argv
            payload = json.loads(output.read_text())
            self.assertEqual(set(payload["rounds"]), {"A"})
            self.assertTrue(payload["rounds"]["A"]["validCompletedProfile"])


if __name__ == "__main__":
    unittest.main()
