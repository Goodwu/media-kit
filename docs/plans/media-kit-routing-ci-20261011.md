# MK-ROUTING-20261011 — CI execution record

Evidence for the existing implementation plan and canonical handoff. Continue `routing/MK-ROUTING-20261011`, draft PR #4; do not recreate completed work on a new branch.

## 1. Actions restart and first observed execution

User reported Actions had been disabled and re-enabled. No run existed to rerun. Documentation checkpoint `01703016d333a97540fdd0f4ac5f9cd901bb54da` triggered current-source push/PR events after verifying prior head `0cb15efc`.

Observed runs for 01703016:
- Source PR run 38072309054: lab job 114272074052 completed success (analyze and tests). Video job 114272074370 found 18 analyzer diagnostics and the stale EL golden described below. A partial/interrupted test log is not whole-suite success.
- General run 38072308952: multiple platform jobs began; not an overall success. Web job 114272073801 failed compilation.
- OHOS run 38072309148: started; final acceptance not established at this checkpoint.

General CI still uses historical/distro native libraries in several jobs. Those results are legacy integration or compilation evidence, not this task's latest-source native candidate acceptance.

## 2. Web compile repair — already committed

Commit `445a2add7e1df072e09885070ce1c0eb40b335b5` fixes the actual dart2js error: the cross-platform test app imported OHOS sw_render.dart, which imported dart:ffi unconditionally. Wasm was skipped after the JS failure, not passed.

- Native implementation moved unchanged to sw_render_io.dart, original blob `ab031d15910763fb646c45209fb867a9cbc19ee6`.
- sw_render.dart conditionally exports the IO implementation or an unavailable stub.
- Added two stub behavior tests and a facade smoke entry. Current source CI now compiles/runs the facade as JS and compiles it as Wasm; full application JS/Wasm jobs remain enabled.
- No OHOS decoding/rendering algorithm, pixel contract or native owner behavior changed.

## 3. Analyzer and EL diagnostic repair — already committed; do not rerun patch

First video analysis reported 18 findings: one unused private Cupertino helper, 13 use_super_parameters findings, two unbraced retry guards, and two impossible null comparisons in a fake channel using nonnullable lists. Test hdr_output_diagnostics_test.dart expected EL=false after classification with no EL fact; actual EL=unknown is correct after f0bba6ff.

Setup commit `146269c414085ac0bc352886739267f83fe5c9d1` introduced a tightly guarded one-shot source-editing job. Actual run 38072868284/job 114273725734:
- Four repair-tool tests PASS and six extraction-tool tests PASS.
- Exact-anchor repairs and the Dart use_super_parameters fixer completed successfully. Only seven allowlisted Dart files were staged.
- Source commit and non-force expected-head push SUCCESS: `1c134790cfbf4f7094c90472b8fd2357184a92e8` (72 insertions, 39 deletions, seven files). Remote diff was independently read back.
- Artifact upload FAILED because `.ci-repair` was a hidden path excluded by the artifact action. Overall editing run is therefore failure, NOT green validation. The source was already persisted before this failure; do not repeat/reimplement it. Job logs retain the full test/fixer/push transcript.

The generated source includes correct unknown-EL golden, a positive explicit EL=false diagnostic test, nullable fake-channel responses and two null-release/null-ACK negative tests, helper removal and mechanical syntax fixes. No analyzer suppression or test exclusion was added.

The one-shot write-permission workflow is removed in this checkpoint. Scripts remain audit evidence and have utility tests, but are not executed to modify CI-tested source. Independent source CI checks out the persisted repair commit plus this checkpoint. No production source is changed inside that validation run.

## 4. Actual local utility tests

Current remote extraction sources were checked against Git blob hashes `78c7c329c874cb2bbb2c871fc80070476e966a62` and `cf4631433bf375eacbcc1898e2e1df209e448ca4`; six utility tests passed. The new repair utility initially had an overbroad test anchor, corrected before upload; then all four utility tests passed. The same 6+4 tests also passed on the GitHub runner. These do not repair or close the known native decoder-selection regression.

## 5. Independent latest-head validation

Pending observation after this checkpoint. Both full video/lab suites retain strict analysis, and Python utility tests plus JS/Wasm facade checks are included. Push/PR duplicate source suites use one branch concurrency group. No current native build, test APK or device playback is claimed.

Local Flutter/Dart remain unavailable; GitHub runners now provide real Flutter execution. Review the latest runs and then update this record and canonical ledger with exact SHA/results, keeping implementation and validation distinct.
