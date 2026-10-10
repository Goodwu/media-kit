# MK-ROUTING-20261011 — CI execution record

Supporting evidence for the existing plan and handoff, not a second plan. Continue `routing/MK-ROUTING-20261011` and draft PR #4.

## Restart and actual execution

The user reported Actions had been disabled and re-enabled. The branch had no run to rerun, so checkpoint `01703016d333a97540fdd0f4ac5f9cd901bb54da` triggered a new current-source push/PR event, after verifying previous head `0cb15efc` and existing implementation commits. No implementation was repeated.

Observed runs for 01703016:
- Routing source checks (PR): 38072309054. lab analyze succeeded and tests started; other job status must be refreshed.
- General Github Actions: 38072308952. Multiple platform jobs started; this is not yet an overall success.
- OHOS: 38072309148, started; conclusion not yet verified.

The general workflow still uses prebuilt/distro native libraries in several jobs. Those jobs provide compile or legacy integration evidence only, not latest-source native/APK candidate acceptance. No old binary was substituted as this task's native test candidate.

## First CI failure and repair

General workflow job 114272073801 (Build Flutter Web) failed at dart2js on 01703016: `media_kit_test/tests/01.single_player_single_video.dart` imports the OHOS `sw_render.dart`, which unconditionally imported dart:ffi and dart:io. Runtime Platform checks cannot remove an unsupported compile-time import. Wasm was skipped after the JS failure, not passed.

Repair in the commit titled `fix(web): isolate OHOS software bridge FFI imports [MK-ROUTING-20261011 CI]`:
- Move the native implementation unchanged to sw_render_io.dart using the original blob `ab031d15910763fb646c45209fb867a9cbc19ee6`.
- Keep sw_render.dart as a conditional export (dart.library.io); web gets an unavailable stub with identical public method signatures.
- Preserve OHOS/native behavior; no renderer, pixel, decoder or lifecycle algorithm was modified.
- Add two stub behavior tests and a facade smoke entry for JS/Wasm compilation. Existing full JS/Wasm application CI remains enabled; do not bypass the error by removing checks.

Reference for the conditional-export mechanism: https://dart.dev/tools/pub/create-packages#conditionally-importing-and-exporting-library-files

## Local tests actually run

The current remote run.py and test_extract.py were copied into the temporary container and checked against Git blob hashes `78c7c329c874cb2bbb2c871fc80070476e966a62` and `cf4631433bf375eacbcc1898e2e1df209e448ca4` before execution. `python3 -m unittest -v test_extract`: six tests passed, exit 0. This verifies the existing extraction utility only; it does not fix or close the native selection counterexample.

Local Flutter/Dart/gh remain unavailable; git ls-remote fails DNS (exit 128). Remote CI now supplies real Flutter execution. Current-source native builds and device acceptance remain open.

## Checkpoint status

The web repair and new tests are implemented, not yet validated, at this checkpoint. Observe its new head runs; do not report the previous head's partial successes as acceptance of the repair. Update this evidence and the canonical handoff before ending the round.
