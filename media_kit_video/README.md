# [package:media_kit_video](https://github.com/media-kit/media-kit)

[![](https://img.shields.io/discord/1079685977523617792?color=33cd57&label=Discord&logo=discord&logoColor=discord)](https://discord.gg/h7qf2R9n57) [![Github Actions](https://github.com/media-kit/media-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/media-kit/media-kit/actions/workflows/ci.yml)

Native implementation for video playback in [package:media_kit](https://pub.dev/packages/media_kit).

## Android Texture output preparation

For Android `SurfaceProducer` Texture playback, mount a `Video` with a bounded
layout before opening media, then call
`await controller.prepareAndroidTextureOutput()`. The method uses the mounted
view's physical pixel size to create and bind an output Surface before decode
starts. It returns `false` when there is no usable layout or Surface; playback
can continue through the normal output setup path.

If the player page opens directly in landscape fullscreen, set the orientation
and fullscreen window mode before mounting `Video`. Otherwise the preparation
uses the earlier, smaller viewport. Keep `Video` mounted through the open call;
the output later follows the source video size. The preparation API applies to
Android `SurfaceProducer` Texture output, not PlatformView output.

## Android HDR routing and session (Phase 1)

For Android HDR (Dolby Vision / HDR10 / HLG / HDR Vivid) playback, the
session API provides pre-playback prediction, route execution and reporting
per `docs/requirements/android-hdr-auto-output.md`:

1. Query a capability snapshot with
   `await HdrCapabilities.query(player: player)`, build a
   `HdrSourceDescriptor` from the media you are about to open, and call
   `snapshot.predict(descriptor)` (same planner as execution) to
   learn the selected strategy, presentation and candidate list before
   deciding whether to request the HDR source.
2. Mount `HdrVideo` inside a `HdrVideoScope` and call
   `await session.open(media, hint: descriptor)`. The session orchestrates
   vo/hwdec topology, dataspace application and at most one decoder review
   rebuild per generation, degrading along the candidate list without
   stopping playback.
3. Show `session.report.value` (actual strategy and presentation) and
   handle `session.events` (`RouteApplied`/`Degraded`/`Reclassified`/
   `CapabilityChanged`/`Error`) per your app's own policy.

Default preference and the source × strategy maturity table are defined in
the requirement's sections 3.4 and 6; experimental strategies require an
explicit `allowExperimental` policy. Set `HdrOutputPreference.off` to
always tone-map. The device-vendor fallback for the validated LYA-AL00
device lives in the separate `media_kit_android_dataspace_vendor` package.

## License

Copyright © 2021 & onwards, Hitesh Kumar Saini <<saini123hitesh@gmail.com>>

This project & the work under this repository is governed by MIT license that can be found in the [LICENSE](./LICENSE) file.
