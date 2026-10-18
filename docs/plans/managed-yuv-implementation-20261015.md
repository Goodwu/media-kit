# Managed YUV implementation continuation / 2026-10-15

Task MK-ROUTING-20261011; contract LAYERING-20261015-r1 in managed-yuv-layering-contract-20261015.md. User requested implementation after the two documentation commits. Continue media-kit PR4 and PiliPlusX PR1 on routing/MK-ROUTING-20261011. Observed starting heads: library b84fb96e712d12ac2455392701c3eab845dd2957 and App 9b55f194b52e4a6b2d89bacc46b5f094c07fff11. These are provenance, not future dependency pins.

## Scope and execution

1. Read the current complete sources and existing tests; preserve existing output identities, release ACKs, route selection and attempt cleanup. Workspace connector currently cannot connect; use GitHub and an isolated source snapshot, never modify the user's uncommitted workspace.
2. Implement the bounded generic output/presentation lifecycle in the Android output layer. Session only orchestrates generic backend preparation/cleanup; vendor applicability and paired arm stay in the implementation. Separate immutable requirements, actual Surface ownership, attempt initialization admission and playback resource lifetime. Prove the initial dataspace/bridge/arm/producer dependencies rather than assuming SurfaceAvailable is the correct boundary.
3. Cover ordinary no-token construction, repeat open, reuse/reinitialize, new Surface after an open has returned, stale callbacks, failed/late ACKs and retained cleanup debt. Do not introduce a second Surface ownership authority, a lab token fallback, an enable switch, implicit HDR-to-SDR, or unconditional per-open recreation.
4. Consume the latest completed library change in the App's eight overrides, retain exact source/target/options/revision and error diagnostics, and extend ordinary-entry regressions without vendor policy or arm logic in App.
5. Run existing source and native contract CI plus all changed boundary tests against current captured source vectors. Full native packaging/APK/member/ABI/parity and device HDR/performance remain separately evidenced; no synthetic/host success may close L-A16 or APP-L08.

## Evidence and current status

This checkpoint adds only this implementation record and a source-review workflow. The workflow exports tracked source bytes and Git blob/tree identities for isolated review where direct network checkout is unavailable. It has read-only permissions, captures App branch HEAD once, contains no credentials or build outputs, and does not certify tests, native output or devices. Subsequent code commits and original PR comments will record changed files, exact commands/results, CI and remaining contract case IDs. No contract implementation is preclaimed by this checkpoint.

Keep the existing dynamic HDR10+/Vivid deferral, original branches/PRs and acceptance ledger. Do not repeat already implemented query/selection/configuration/Session/report work. Any interrupted continuation starts by reading current heads and this record plus latest original PR comments, not by reimplementing from the starting SHAs.

## Implementation checkpoint: generic backend resource boundary

The first code change moves Session's direct arm construction into the Android backend. Session sees only HdrOutputResources and generic preparation/conflict failures; the existing legacy adapter implements that port. Explicit historical single-open configuration policy is isolated from ordinary orchestration. Existing arm/coordinator fake-native assertions remain; only the test injection parameter changes. Four source-boundary checks have local red/green evidence (two original boundary violations, four passing after); these are architecture checks, not ordinary YUV cold-open validation. Full Flutter suites must run on the actual published code.

Still pending after this checkpoint: generic Android managed provider/Surface protocol, ordinary no-token positive initialization, rebuild/reuse/native bridge and App/native/device integration. The existing missing-owner refusal has NOT been removed. Session refactor must not be described as full L-A06/APP-L03 completion.

## Implementation checkpoint: P0 contract-test fixture seams (2026-10-15, local agent)

The d5f30c7e source run failed three cases in
media_kit_video/test/hdr_yuv_presentation_contract_test.dart (reproduced
locally and identical to CI run 38731073045: two
HdrOutputPreparationFailure(yuvWindowArmUnavailable) and one
HdrOutputLeaseConflict with an uninitialized ServicesBinding). Root cause:
784df146 moved the default arm-manager construction into AndroidHdrBackend,
so the old `_exercise` fixture (no injection, migration-default capability
snapshot without a declared YUV-window channel, no owner token) crossed from
"owned writes only" into the real resource/platform boundary.

Fix (test-only, `test/hdr_yuv_presentation_contract_test.dart`): the
issuance-group `_harness` now injects the SAME real `HdrYuvWindowArm`
through the existing `yuvWindowArm:` constructor seam with the in-file
`FakeArmAtoms` channel/FFI doubles already used by the passing
arm-integration group, and `_exercise` uses `_issuedPlan`, which declares
the YUV-window PQ presentation channel the accepted quad implies (the
`yuvPlan` shape). Admission, ownership and lease checks stay live; the
production default resource manager is untouched; no case was deleted,
skipped or weakened; no binding initialization workaround.

Local verification after the fix (Flutter 3.47.2, macOS arm64):
media_kit_video analyze clean and `flutter test --no-pub --concurrency=1`
890/890 passed (CI baseline 884 passed/3 skipped/3 failed; local all
pass); media_kit_hdr_lab analyze clean and 292/292 passed;
tool/managed_output 4 OK; routing tools 6+17+27 OK. Raw before/after
evidence: /tmp/mk-p0-fix-evidence-20261015/. Still pending: generic
managed provider/Surface protocol (W1), ordinary no-token YUV cold-open,
W3 App re-pin to this commit, W4 native packaging, W5 device matrix.
