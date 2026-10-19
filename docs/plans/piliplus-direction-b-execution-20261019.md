# Direction B implementation receipt — first source batch

The user explicitly approved direction B on 2026-10-19. The pending decision in the earlier native-unload note is superseded; do not ask again or start a universal transparent adapter.

Continue SDK branch compat/piliplus-zero-change-20261018. SDK integration commit: 6025d405939743eb40718fe4663cec5b2cb4fe27. Actual new application source snapshot: 2eaeeb731462dad92246809d5b5ac716c671736b. Snapshot action 39198005234, artifact 12161749495, ZIP SHA256 d4a9607ae4a2c1d6468288112135c13f68d9a97e550bc12814d11b321a792c97. Both archives and all regular source blobs were checked locally against the captured Git manifests.

RoutedVideoPlayback explicitly owns session/transport integration; it does not intercept Player. Android opens/rebuilds use the existing HdrVideoSession paused, and the newest transport intent is applied after reviewed readiness. Audio-only mode retires the video owner. Non-Android preserves the ordinary controller and makes no HDR assertion. RoutedSimpleVideo mounts while review is pending and follows controller replacement.

The integration patch changes seven reviewed Dart files, with exact before/after blob guards:
- lib/plugin/pl_player/controller.dart: initialization/open/play/pause/seek/release; reactive binding, shared initialization, stale request guard, retained failed cleanup.
- lib/plugin/pl_player/view/view.dart: video/subtitle controller-following, application background transport.
- lib/pages/video/view.dart and lib/pages/live_room/view.dart: mount the output when binding exists, before open verification; no network or account changes.
- lib/common/widgets/image_viewer/gallery_viewer.dart: explicit gallery playback and listenable output/release.
- lib/pages/video/introduction/local/controller.dart and lib/pages/video/post_panel/view.dart: existing transport call sites use the owned integration; no changes to selection/business rules.

Patch: tool/piliplus_compat/direction_b/player-integration.patch; SHA256 8be7561cc7f0f79a7470efb56b8f8801fb99dcb624b7716a8149da9bfe098028. It is maintained in this SDK repository, not pushed into the upstream PiliPlus repository. Direction B applies it only to an isolated latest-app checkout and records both upstream and derivative identities. Changes outside the seven-path allowlist, dirty inputs, patch digest drift and changed preimages/postimages fail before certification. The existing original zero-patch T1 lane is untouched. New T1B uses build_direction_b.py and a separately named five-platform workflow; it must never be reported as zero-patch T1.

Local validation: 121 Python build-tool tests passed, including seven new direction-B guard tests. The actual seven-file patch was applied to a local verified-source clone and all postimage/diff guards passed. This is not Flutter analysis or compilation. SDK regression at 6025d405 and the new T1B lane must be observed before claiming success.

Still open: new regression/build acceptance, broader no-hint source fact admission, remaining cancellation/race and PiP/layout/feature behavior, latest-source native library/ABI delivery, Release/signing and device/HDR validation. Existing sdrEmbed defaults, preferCopy semantics, safety checks and unimplemented-path errors are unchanged. Do not claim complete P3/P4/P5 based on compilation.
