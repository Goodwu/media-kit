# OHOS adaptation continuation — 2026-10-19

Continue `compat/piliplus-zero-change-20261018`; direction B is already approved. Starting SDK HEAD: `3da20c3e17cc4751494965a0b93348a7b37df253`. Do not recreate the branch or repeat P0/P1/P2b/B work.

## Requested result and evidence boundaries

The user requests OHOS compilation and adaptation. Keep three gates distinct: (1) build current OHOS native sources; (2) compile the actual SDK and explicit direction-B playback/view integration into an unsigned ARM64 HAP; (3) compile/run the current PiliPlus direction-B application. A test application HAP is NOT gate 3. Unsigned compilation is NOT installation, playback, PiP or HDR display validation.

## Confirmed starting gaps

* Existing `.github/workflows/ohos.yml` builds `media_kit_test`, not PiliPlus. It consumes pinned September libmpv binaries; the five-platform B runs do not cover OHOS.
* OHOS native plugin CMake pins the downloaded archive digest. A newly built archive cannot merely be copied over it: CMake would delete it and fetch the old release. Add an explicit build-input archive + SHA256 pair, fail closed on incomplete/mismatched inputs, and verify the actual HAP payload against this run's library. Do not add a runtime experiment switch.
* Current original PiliPlus has no `ohos/` host and declares Dart >=3.13 / Flutter 3.47.7 in the last observed snapshot. The selected maintained Flutter OHOS patch branch is based on 3.44.9. Obtain the actual tool versions and resolver error, not a guessed version mismatch; do not relabel the SDK or lower application constraints to make pub succeed.
* Goodwu/PiliPlusX `ohos` exists, but is a distinct older 1.1.5 application with OHOS-specific plugins. Do not silently substitute it for current original PiliPlus 2.1.6 plus the direction-B patch.
* The Codex workspace read connection fails; local container has no Flutter/OHOS SDK and cannot resolve GitHub. Execution uses GitHub Actions and read-back artifacts. No physical OHOS device is available through these tools.

## Bounded implementation

1. Add/test strict current-native-archive input in OHOS plugin CMake without weakening the historical release integrity path.
2. Resolve the configured Flutter OHOS patch branch and native build repository from live refs for each run. Native recipe downloads its maintained OHOS branches; verify their actual HEADs against the source-lock, retain the source identities and patches, compile from a clean checkout, and never use a previous binary cache as the tested native result. If source-lock drift is found, review before updating it.
3. Add an OHOS direction-B exercise entrypoint using `RoutedVideoPlayback` and `RoutedSimpleVideo`. Compile with real OHOS Flutter/ArkTS/C++ toolchains; record target entrypoint, versions, library ABI/exports, HAP payload hashes and all exit statuses. No HDR verification claim for non-Android passthrough.
4. Probe the current original application's OHOS toolchain and host/plugin prerequisites separately. A failed application gate stays failed even if the SDK HAP builds.
5. When this requires a newer OHOS engine/framework or broad non-player plugin/business portability, stop and discuss the concrete baseline/scope decision, as the user requested. Do not remove features or switch to old PiliPlusX without approval.

## Acceptance still open

All execution results are pending at plan creation. Update the master handoff with exact commits, runs, completed gates and unresolved application/device gates. Existing five-platform green runs certify only their recorded inputs.
