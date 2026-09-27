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

## License

Copyright © 2021 & onwards, Hitesh Kumar Saini <<saini123hitesh@gmail.com>>

This project & the work under this repository is governed by MIT license that can be found in the [LICENSE](./LICENSE) file.
