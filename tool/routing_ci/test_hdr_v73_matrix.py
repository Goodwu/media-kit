"""Guard the independent v7.3 release matrix against false-positive acceptance."""
import json
from pathlib import Path
import unittest

MATRIX = Path(__file__).resolve().parents[2] / "docs" / "validation" / "hdr-route-matrix-v7.3.json"
SOURCES = ["dvP5","dvP81","dvP82","dvP84","dvP7","hdr10","hlg","hdr10Plus","hdrVividPq","hdrVividHlg","sdr","dvP10","dvUnknown"]
STAGES = ("c1", "c2", "c3", "c4")

class HdrRouteMatrixContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = json.loads(MATRIX.read_text(encoding="utf-8"))

    def test_complete_independent_source_stage_catalog(self):
        rows = self.data["cases"]
        actual = [row["id"] for row in rows]
        expected = [f"{source}/{stage}" for source in SOURCES for stage in STAGES]
        self.assertEqual(actual, expected)
        self.assertEqual(len(actual), len(set(actual)))

    def test_structural_skips_cannot_pass_as_accepted(self):
        for row in self.data["cases"]:
            with self.subTest(row=row["id"]):
                self.assertEqual(row["applicable"], row["route"] is not None)
                if not row["applicable"]:
                    self.assertEqual(row["acceptance"], "notApplicable")
                    self.assertEqual(row["implementation"], "notApplicable")
                else:
                    self.assertIn(row["implementation"], ("pendingImplementation", "requiresValidation"))
                    self.assertIn(row["acceptance"], ("pending", "accepted"))

    def test_no_acceptance_without_reproducible_path_evidence(self):
        for row in self.data["cases"]:
            if row["acceptance"] == "accepted":
                self.assertTrue(row["evidence"], row["id"])
                for item in row["evidence"]:
                    self.assertTrue(item.get("sourceSha"), row["id"])
                    self.assertTrue(item.get("deviceOrReference"), row["id"])
                    self.assertTrue(item.get("candidateId"), row["id"])
                    self.assertTrue(item.get("resultArtifact"), row["id"])
                    self.assertEqual(item["validatedStage"], row["stage"])

    def test_user_deferral_preserves_full_matrix_without_requiring_dynamic_for_static(self):
        scope = self.data["currentPhase"]
        self.assertEqual(scope["mode"], "staticCompatibilityOnly")
        self.assertEqual(scope["deferredPackages"], ["B1", "B2", "B3", "B4"])
        self.assertFalse(scope["requiresDeferredDynamicFeaturesForStaticAcceptance"])
        expected_dynamic = {
            f"{name}/{stage}"
            for name in ("hdr10Plus", "hdrVividPq", "hdrVividHlg")
            for stage in ("c1", "c2")
        }
        self.assertEqual(set(scope["deferredCandidateIds"]), expected_dynamic)
        rows = {row["id"]: row for row in self.data["cases"]}
        self.assertEqual(
            {row["id"] for row in rows.values()
             if row.get("scheduling") == "deferredByUser"},
            expected_dynamic)
        for key in expected_dynamic:
            row = rows[key]
            self.assertTrue(row["applicable"], key)
            self.assertEqual(row["acceptance"], "pending", key)
            self.assertNotEqual(row["implementation"], "notApplicable", key)
        expected_static = {
            "hdr10Plus/c3", "hdrVividPq/c3", "hdrVividHlg/c3", "hdrVividHlg/c4",
        }
        self.assertEqual(set(scope["baselineCandidateIds"]), expected_static)
        for key in expected_static:
            self.assertEqual(rows[key].get("scheduling"), "currentStaticCompatibility")
            self.assertEqual(rows[key]["acceptance"], "pending")
        self.assertFalse(self.data["releaseReady"])

    def test_release_gate_is_fail_closed(self):
        applicable = [row for row in self.data["cases"] if row["applicable"]]
        additional = self.data["requiredAdditionalCases"]
        required = ["sdrDirect","hdrDisplayMissingMustBlock","hdrNoSdrFallback","sdrOnlyToneMap","dvUnknownBlock","requireOutputConflict","metadataNotImplementedReturnsError","metadataErrorPreservedAfterBaseline","p82HdrNoSdrBaseExit","p82SdrDisplayDirect","c2FailureThenC3","c2FailureThenC4","staleGenerationRejected","ownerDebtBlocksRetry","presentationObservedNotImplied"]
        self.assertEqual([item["id"] for item in additional], required)
        for item in additional:
            self.assertIn(item["acceptance"], ("pending", "accepted"))
            if item["acceptance"] == "accepted":
                self.assertTrue(item["evidence"], item["id"])
                for evidence in item["evidence"]:
                    self.assertTrue(evidence.get("sourceSha"), item["id"])
                    self.assertTrue(evidence.get("deviceOrReference"), item["id"])
                    self.assertTrue(evidence.get("resultArtifact"), item["id"])
                    self.assertEqual(evidence.get("validatedCase"), item["id"])
        accepted = all(row["acceptance"] == "accepted" for row in applicable)
        extras_accepted = all(item["acceptance"] == "accepted" for item in additional)
        self.assertEqual(self.data["releaseReady"], accepted and extras_accepted,
                         "Release is forbidden until every stage and extra case is attested")
        self.assertNotIn("experimental", json.dumps(self.data).lower())

if __name__ == "__main__":
    unittest.main()
