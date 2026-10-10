# MK-ROUTING-20261011 — native gap and build audit checkpoint

This is supporting evidence for the canonical execution plan and handoff, not a second independently maintained plan. Date: 2026-10-11 (task timezone Asia/Seoul).

## 1. Actual host execution: a decoder-selection counterexample

The current workspace was read through the connector. FFmpeg baseline is `d4bb79394b` on `lg-p84-d1-vui-fix-20261010`; its existing configure modification was preserved. The inspected production regions are `libavcodec/mediacodec_wrapper.c:470-676` (list selector) and `libavcodec/mediacodecdec_common.c:1070-1087` (native-DV lookup profile branch).

The current P8 caller selects profile=-1, and the list selector then accepts the first hardware decoder with matching MIME without checking profile256. A synthetic capability list [P5-only DV decoder, P8-only DV decoder] therefore demonstrates the mismatch between any-match Dart admission and actual selection.

This turn compiled the captured **current source regions** with the JNI fixture in `tool/routing_native_audit/native_selection_harness.c`. The regions are not a full source checkout and are not a complete FFmpeg build. No historical APK/JAR/so was used, no Android device was operated, and no native production source was changed.

Actual command family: `cc -std=c11 -Wall -Wextra -Werror -O0 -g -fsanitize=address,undefined -fno-omit-frame-pointer`. Compiler: Debian GCC 14.2.0-19. Compile exit=0; regression exit=1. No sanitizer diagnostic was emitted in this bounded fixture run.

```text
control-p5-profile profile=32 expected=vendor.p5-only actual=vendor.p5-only result=PASS
control-p8-profile profile=256 expected=vendor.p8-only actual=vendor.p8-only result=PASS
counterexample-current-p8-mime-only profile=-1 expected=vendor.p8-only actual=vendor.p5-only result=FAIL
control-skip-encoder profile=-1 expected=vendor.p8-only actual=vendor.p8-only result=PASS
control-skip-software profile=-1 expected=vendor.p8-only actual=vendor.p8-only result=PASS
control-skip-other-mime profile=-1 expected=vendor.p8-only actual=vendor.p8-only result=PASS
controls_failed=0 counterexample_reproduced=1
```

The extraction utility's six unit tests separately ran and passed. That does not turn the native regression failure into a successful suite.

Generated selection region SHA-256: `02040eaa500d5e66dd7c9f15ee2b4b603e8ad0d5794f00e2ee8ea2b0fb272ca8`.
Generated lookup region SHA-256: `894f3674b9ae6c3e875e4c9c9a3aecc14a56fc657090ea7f2e1a318589b7906c`.
Harness SHA-256: `ed3e80561244f4a763c843abd76658e1ba927ea2cf8879b5268b5939fe9b7a1e`.
These identify the executed input only, not future build pins.

### Required follow-up, not yet implemented

Prefer a narrow native profile-selection repair over inventing a new cross-layer named-decoder protocol. Also evaluate the list selector's existing behavior when the profile list is empty; blindly changing the caller to a positive profile does not prove all strict-admission cases. Preserve ordinary codec behavior and verify P5 and multi-decoder cases. This audit establishes a concrete B3 selection gap; it does not close B3, actual-decoder review, or full native compilation.

## 2. Existing native functionality to reuse

Current `mediacodecdec.c:402-424` already maps P5/P8 to 32/256. The current mpv `get_mediacodec_info` exposes MIME, selected codec and native-DV-active through the existing v1 protocol. Current FFmpeg already offers dovi=auto/on/off. These capabilities should be consumed before adding new protocols. Runtime RPU-to-frame delivery and original-source fact retention still need validation; symbol/option existence is not end-to-end proof.

## 3. Current-source test build audit remains open

`tool/build-android-test.sh` was read. Its documented pipeline invokes current mpv ninja, but then calls the external `build-mks-r1.py` linker/package recipe and describes replacement of libmpv in an r22 base JAR with pinned helper libraries. This is **not yet established** to satisfy the user's requirement that the candidate contain the latest applicable source builds. The actual external recipe and all embedded helper inputs must be audited/rebuilt; do not simply label the output latest because ninja ran.

The script also changes to the repository root before Flutter build, then expects the APK under media_kit_hdr_lab. Check the actual app working directory during the build; this is a static inspection concern, not a reproduced Flutter error.

The observed FFmpeg configure dirty diff changes generated FFMPEG_CONFIGURATION to an empty string. It was not reset, committed or otherwise changed here. Its presence must be accounted for in real builds; do not overwrite it as cleanup.

## 4. Execution limitation and GitHub state

Current container: C compiler and Python available; Flutter/Dart/gh unavailable on PATH; git network fetch fails DNS resolution for github.com. The workspace connector exposes read/review operations only, not remote command execution. GitHub content and ref writes work.

Canonical implementation branch: `routing/MK-ROUTING-20261011`, draft PR #4. B1a is `d18de2751085913591f50653d125b5db6fe5eff2`; the classifier EL follow-up is `f0bba6ff5a618767b92286011b768f77eee1ef9e`.

Both pushes and the PR were created. Exact-head Actions queries for d18 and f0bba returned zero workflow runs; d18 check-runs also returned zero. A source-only push/PR workflow exists, but no execution or success is claimed. The cause of absent Actions runs is not established; connector rejection of workflow-management URLs is not evidence that GitHub denied access or Actions is disabled. Do not substitute a rerun of an old commit for current-head acceptance.

PiliPlusX remote was discovered as `Goodwu/PiliPlusX` (default branch dev-new). Its workspace branch `fix/darwin-video-output-rebuild-barrier` resolves remotely to `73afb9b66ce44bf142fa17165c46c54be8c89731`. No APP branch or code has been created yet. Reconcile all remote refs before starting APP; do not assume dev-new contains the user's newer workspace branch.
