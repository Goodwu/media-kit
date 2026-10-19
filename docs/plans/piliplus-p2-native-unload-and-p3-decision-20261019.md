# P2b native-unload evidence and P3 complexity decision

Date: 2026-10-19 (Asia/Singapore). Continue ONLY `compat/piliplus-zero-change-20261018`.

## Current request and verified source

The user authorized continued implementation, but requested stopping to discuss unusually difficult implementation; requirements may be moderately adjusted to control complexity. This is NOT permission to silently relax functional assertions, HDR safety, source freshness or the original-app source boundary.

This turn read branch `dd2bd031a76d3937b120faf809f6d300e4488f1e`, routing `0597c8318ccf50f0824249ceeab310632efb84ab`, the actual P2b core, helper, tests and CI workflows. The normal test commit `b6f19b0ad078a97e04c558e3ecb5f44d3f6491a6` contains that routing base (behind_by=0). No branch recreation, force push, original PiliPlus patch or player production change was made in this slice.

## Correct the interpretation of the last failed SDK run

Downloaded and read the COMPLETE `video-tests.log` from run 39187039529 / artifact 12158627197, tested commit `e540c22fa106cc2ece54a1a665862422523c1f6c`. Artifact ZIP SHA256: `6b7683afd40e5b3845de40596e5ff23bd10ad963d89f80df68e941d058535352`.

The final result was 1012 passed, 3 skipped, 1 failed. The failing same-URI test had already passed the A/B/A real-wire checks, including immutable application defaults, the literal comma/injection-looking value, trailing backslash and per-entry isolation. Failure was specifically its last assertion after `await player.stop()`: expected `x-baseline: keep`, observed entry A's still-active header block. It was NOT still a header delivery timeout. The earlier duplicate-key encoding defect and its correction remain recorded in `piliplus-p2-request-scope-20261019.md`.

Source cross-check:

* SDK `media_kit/lib/src/player/native/player/real.dart`, blob `4f4348f40df74a8fc5622783ce6993974998b4b9`: `stop` acknowledges native commands, then resets public state. It does not await completed native file teardown.
* mpv v0.37.0 `player/loadfile.c`, blob `1d25dc340af35acda5b7cbb45c92b2168f2c60f0`, lines 1850-1990: `on_unload`, native teardown and `m_config_restore_backups` precede END_FILE and the return to idle.
* mpv manual: `idle-active` means no file is loaded; `core-idle`/pause is NOT the same boundary. https://mpv.io/manual/master/#property-list

## Test correction and additional regression

Commit `b6f19b0a` (native request test blob `082856a8150662af115997c18270940e249ea806`):

1. Observe native `idle-active` using bounded asynchronous queries before checking restored header/start/end values. The helper never polls the expected option value, writes a reset, ignores errors, or treats a delay as proof of completion.
2. Retain every existing wire and exact restoration assertion and every existing skip/timeout setting.
3. Add three immediate `stop` -> `open` cycles with different native baselines. There is deliberately NO idle wait before successor `open`. Each baseline HTTP request must contain the current baseline and no preceding per-media fields. Only the final restoration read waits for idle. This tests that synchronization does not conceal a real successor-source leak.

This corrects test synchronization to the existing stop contract. It does not add a public physical-stop guarantee, change the HDR cleanup barrier, or weaken native-source/feature acceptance. If restoration after native idle or the immediate successor test fails, investigate the implementation rather than adding a Dart global reset or weakening the assertions.

Triggered on that actual commit: SDK 39192616258, five-platform original-app T1 39192616309, macOS views 39192616235. Results were pending when this note was first written; the root handoff records the subsequent observed results. Never certify this test revision from an older successful run.

## P3: discuss before the large transparent-adapter refactor

Re-read `VideoController` (blob `ff990f325b6ceaca2be2bb45914b09e754dfdeaf`), `HdrVideoSession` (`a51d0ac47a8366e362376985b05f816c89d974a4`) and `HdrVideo` (`ff929f09f67f07bd8ace6e644e45b3aa3c0a7985`). The existing session replaces controllers at a topology switch, waits for output binding and decoder review, and already provides a listenable-following widget. Ordinary `VideoController` has a one-shot `platform` completer and forwarders tied to the initial backend. Ordinary player open waits for controller initialization. The generic session also uses ordinary player operations internally.

These contracts make complete zero-source-change transparent routing more than a forwarding method: it requires a stable public output proxy, explicit/raw operation separation to avoid recursion, one owner, and accepted-vs-verified open sequencing to avoid mount/open dependency cycles. Playlist changes and direct commands further expand the compatibility surface. These are architectural costs, not a claim that the goal is impossible.

Two scope choices for user discussion (neither has been silently selected):

| Choice | Retained goal | Additional work / tradeoff |
| --- | --- | --- |
| A: retain absolutely zero original-app edits | Original Player/VideoController/SimpleVideo flow automatically gains routing | Build and validate the transparent proxy + operation interception + staged open. Larger generic compatibility/lifetime surface. |
| B: allow narrowly scoped player-integration edits | Business/network/account code and native hosts remain unchanged; SDK owns planning/verification | Adapt player initialization, routed open, view binding and release in the app integration layer to the existing session/listenable. Avoid a universal transparent legacy state machine. Exact file/line inventory and PiP/layout review are required before any app write. |

Recommendation for complexity control: discuss B before committing to the large A refactor. This is not 'replace one widget and everything is done': no-hint source facts, cancellation, old hwdec intent, custom subtitle/layout/PiP behavior, native artifact provenance and HDR device checks still require implementation/verification under either choice. Non-Android passthrough must not be advertised as Android-equivalent HDR.

P0/P1 and zero-patch multi-platform builds are retained under either choice; do not discard or reimplement them. Until the user chooses, P3 interception/output-ownership production changes and all original PiliPlus edits are paused. P2b evidence collection may finish without making this decision.
