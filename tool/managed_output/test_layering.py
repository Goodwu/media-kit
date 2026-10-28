"""Source boundary checks; behavioral/native cases are separate requirements."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
HDR = ROOT / 'media_kit_video/lib/src/hdr'


class LayeringBoundaryTests(unittest.TestCase):
    def test_session_uses_only_generic_output_resource_port(self):
        source = (HDR / 'hdr_video_session.dart').read_text()
        imports = re.findall(r"import\s+['\"]([^'\"]+)['\"]", source)
        self.assertNotIn('hdr_yuv_window_arm.dart', imports)
        for forbidden in ('lgExperimentOwnerToken', 'EnableYuvDiag',
                          'BeginOutputInitWrite', '0x11C60000', "'lg-pq'",
                          'resolveHdrYuvWindowFfiBindings'):
            self.assertNotIn(forbidden, source)
        self.assertIn('HdrOutputResources<HdrOpenPlan>', source)
        self.assertIn('await _outputResources?.endAttempt(plan)', source)
        self.assertIn('await _outputResources?.dispose()', source)

    def test_output_resource_port_has_no_platform_or_vendor_dependency(self):
        source = (HDR / 'hdr_output_resources.dart').read_text()
        self.assertNotRegex(source, r'(?m)^\s*(import|export)\s')
        self.assertIn('Future<void> endAttempt(P plan)', source)
        self.assertIn('Future<void> dispose()', source)

    def test_backend_owns_legacy_adapter_during_migration(self):
        source = (HDR / 'hdr_player_backend.dart').read_text()
        self.assertIn('HdrOutputResources<HdrOpenPlan>? get outputResources', source)
        self.assertRegex(source, r'this\.yuvWindowArm\s*=\s*yuvWindowArm\s*\?\?\s*HdrYuvWindowArm\(')
        self.assertIn('static VideoControllerConfiguration withManagedOutputOwner(', source)
        legacy = (HDR / 'hdr_yuv_window_arm.dart').read_text()
        self.assertIn('implements HdrOutputResources<HdrOpenPlan>', legacy)

    def test_snapshot_workflow_does_not_claim_functional_validation(self):
        source = (ROOT / '.github/workflows/routing-source-review.yml').read_text()
        self.assertIn('contents: read', source)
        self.assertIn('functionalVerified=false', source)
        self.assertIn('nativeVerified=false', source)
        self.assertIn('deviceVerified=false', source)
        self.assertNotIn('continue-on-error', source)


if __name__ == '__main__':
    unittest.main()
