# Windows package CI crash diagnosis (2026-10-03)

## Baseline

Main code baseline: `25f3520e653bc6e56e71b8f30d4d71578909c191` (documentation-only changes since run 60's `490ae215`).

Run [60](https://github.com/Goodwu/media-kit/actions/runs/37034064978) completed with three failing jobs:

- Windows package tests: access violation `0xC0000005`, old DLL `+0x13c4f1`.
- Web package tests: 60 passed, 1 failed, 27 skipped; `player-set-shuffle-consecutive`, Stream closed.
- Linux package tests: 80 passed, 1 failed, 15 skipped; the same shuffle test / Stream closed.
- macOS package tests: success. Build and private-ABI/JAR identity gates succeeded.

## Fixture and suite isolation

[Full serial A/B](https://github.com/Goodwu/media-kit/actions/runs/37046664238), unchanged core with `dart test -j 1 --reporter expanded`:

- 2023-08-11: initializer suite passes, then `player-platform` crashes during teardown at DLL `+0x13c4f1`.
- media-kit/libmpv-win32-video-build latest release is **2023-09-24**, not modern mpv. It also crashes in `player-platform`, at `+0x142fc1`.
- [Modern fixture run](https://github.com/Goodwu/media-kit/actions/runs/37047363078): shinchiro 20261002 / mpv `3186d369f9` also crashes in the same test, DLL `+0x1125300`.
- [Single-test reproduction with cdb](https://github.com/Goodwu/media-kit/actions/runs/37047207889) confirms the crash without preceding suites. The first cdb invocation needed child initial-breakpoint handling corrected; its output is not a complete native stack.

Old DLL disassembly identifies the fault as `call [rax+0x38]` inside the function logging `Hotplug uninit`. Matching mpv source identifies WASAPI `wasapi_change_uninit` / `IMMDeviceEnumerator_UnregisterEndpointNotificationCallback`. Modern cdb also stops at `call [rax+0x38]` with an unreadable vtable address. Export-relative cdb names such as `mpv_render_context_render+...` are nearest exports, **not** evidence that render context code is the fault.

## Candidate correction and validation

libmpv joins the core thread before `mp_destroy` finishes WASAPI hotplug cleanup in the caller. The candidate keeps Windows COM MTA support alive across `mpv_terminate_destroy`, using a balanced CoIncrementMTAUsage / CoDecrementMTAUsage cookie. Other platforms are unchanged. No rollback of the awaited termination barrier, skipped tests, disabled Windows jobs, retries of test failures, or continue-on-error gates.

Microsoft documents that [CoIncrementMTAUsage](https://learn.microsoft.com/en-us/windows/win32/api/combaseapi/nf-combaseapi-coincrementmtausage) keeps MTA resources alive even after the explicit MTA thread count reaches zero; every successful call is paired with one decrement.

A [bare Python/libmpv control](https://github.com/Goodwu/media-kit/actions/runs/37047917848) passed both baseline and MTA cases, so that control does **not** establish a standalone upstream reproduction or prove causation.

[Patched old/new full suites](https://github.com/Goodwu/media-kit/actions/runs/37048293551) both succeeded: **81 passed, 15 skipped** each. The modern job first reproduced the unpatched access violation under cdb, then restored the fix and passed the complete suite. No failure retry was used to obtain these passes.

[Full-platform CI run 64](https://github.com/Goodwu/media-kit/actions/runs/37049478534) completed successfully: 23 successful jobs, one unchanged upstream-only release metadata skip, zero failures. Windows/Linux/macOS each passed 81 tests with 15 existing skips; Web passed 61 with 27 existing skips. [OHOS run 37](https://github.com/Goodwu/media-kit/actions/runs/37049478577) also succeeded. Dart 3.13.2 analysis of both changed source files reported no issues.

Run 64 tested PR head `76bff4a6` merged with current main `f6665609` (test merge `ba03e261`). Main's concurrent shuffle test change is separate from this Windows patch and accounts for the Web/Linux change; it is preserved. Failure set comparison: run 60 = {Windows access violation, Web shuffle, Linux shuffle}; run 64 = {}. Subsequent closure changes are documentation only.

The fork's awaited delayed termination was introduced in `5cf24d77`; it exposes the native teardown fault at a guaranteed disposal boundary. The chosen correction is local to Windows core disposal rather than reverting that lifecycle contract or changing upstream merge resolutions. The MTA-lifetime explanation is supported by source/disassembly and controlled old/new-fixture results, but is not claimed as a standalone upstream reproducer.

Fixture proposed for regular Windows package CI: https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/20261002/mpv-dev-x86_64-20261002-git-3186d369f9.7z

SHA-256: `d873450cc1a7f881a8a10c33936d9555ad18a3809d827b9dbea55ba55caebcf9` (release asset digest).
