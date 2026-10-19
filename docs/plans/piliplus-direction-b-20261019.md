# PiliPlus direction B implementation

Date: 2026-10-19, Asia/Singapore.

## Approved decision and continuity

User selected direction B: allow narrowly scoped changes to the application player integration instead of universally intercepting old Player/VideoController operations. Business, network, account code and native hosts remain unchanged. Continue `compat/piliplus-zero-change-20261018`; do not recreate the SDK branch, redo P0/P1/P2a/P2b, or alter routing defaults to conceal missing work. This decision supersedes the pending A/B choice in the earlier handoff.

Starting SDK HEAD: 43f698958b7acdb4d0c1012d5afa17b8d829dc34. Routing ref re-read: 0597c8318ccf50f0824249ceeab310632efb84ab. Previous actual tested code: b6f19b0ad078a97e04c558e3ecb5f44d3f6491a6. SDK regression 39192616258 (1014 passed, 3 skipped), original-app five-platform Debug build 39192616309 and macOS views 39192616235 passed at that code. These are historical evidence, not certification of upcoming changes.

## Implementation boundary

Use existing HdrVideoSession orchestration and its controller listenable. Do not introduce a generic transparent Player interception layer or a universal stable output proxy. Re-read the latest original PiliPlus before generating a file/line inventory. Expected application scope: player controller initialization/open/release, video output binding, and the gallery player integration if it uses the same route path. A maintained integration patch and added integration-only Dart files may live under `tool/piliplus_compat/direction_b/` in this SDK branch; the build must apply them to an isolated original-app checkout, preserve the exact resulting source diff, and reject any file outside the reviewed allowlist. Never label this build zero-patch or write to upstream business/native files.

## Work sequence

1. Capture actual current SDK and app source identities; record this approval before code work.
2. Implement bounded player integration using the existing session/listenable. Retain subtitle/layout/PiP contracts. Separate request submission from validated output readiness where the old page only mounts after open returns; do not make tests pass with a blind delay or enable playback before readiness.
3. Integrate old hardware-decoding intent without changing current sdrEmbed defaults, preferCopy priority or capability tri-state. Unimplemented/blocked paths remain explicit errors.
4. Add focused tests for accepted-versus-verified operation ordering, cancellation/disposal and view replacement; run the complete SDK suite, existing zero-patch lane and a separate direction-B original-app build lane on Android/iOS/macOS/Windows/Linux. Record actual code SHA, input app SHA, source guards, stages and artifacts separately.
5. Continue no-hint source facts, latest-source native artifact/ABI closure, feature/PiP/screenshot and device/HDR gates. Compilation or non-Android passthrough does not certify HDR.

## Non-negotiated gates

No HDR safety or factual-verification relaxation. No new hidden experiment switch. No old prebuilt artifact substituted for latest-source native acceptance. Do not remove failing assertions or certify new runtime/test code from earlier green runs. If another disproportionately complex boundary is found, document concrete alternatives and discuss it with the user before expanding scope.

## Execution environment

Codex media-kit workspace connection was attempted again and returned connection error. This container has no Flutter/Dart and GitHub DNS resolution failed. Use the working GitHub connector and actual GitHub Actions execution; download source/evidence artifacts for local inspection. These environment limitations are not a reason to invent test results.

Status: approved; implementation starting. Detailed file inventory, commits and test results follow in this document and the root handoff.
