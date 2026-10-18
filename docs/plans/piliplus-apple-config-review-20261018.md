# Apple generated configuration review for T1

On f0de192 the macOS build also performed MacOSDeploymentTargetMigration (10.14/11.0 -> 12.0) and XcodeProjectObjectVersionMigration (LastUpgradeCheck/LastUpgradeVersion -> 1510). Those are observed Flutter migrations, not arbitrary app patches. Add exact original-to-generated blob verification bound to the current Flutter generator blobs 9333ed69, 75300a5e and 21550a04. Any other project/scheme changes remain rejected. Keep the already reviewed iOS migration separate. Save complete app-generated-diff.log before integrity guards for the next diagnostic round.

This follows 288b9f24803025c462f081a5be4c3c0cb9065ea4 on the same branch. Local post-edit tool suite: 77 tests passed. Source editing request piliplus-p1-apple-r3b must be integrated before the next accepted T1 run. No runtime, native-freshness, SwiftPM or device/HDR success is implied.
