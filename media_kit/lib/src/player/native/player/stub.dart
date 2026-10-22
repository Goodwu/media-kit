/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'package:meta/meta.dart';
import 'package:synchronized/synchronized.dart';
import 'package:media_kit/src/models/media/media.dart';
import 'package:media_kit/src/models/playable.dart';

import 'package:media_kit/src/player/platform_player.dart';
import 'package:media_kit/src/player/native/utils/source_transition_gate.dart';

void nativeEnsureInitialized({String? libmpv}) {}

class NativePlayer extends PlatformPlayer {
  NativePlayer(
      {PlayerConfiguration configuration = const PlayerConfiguration()})
      : super(configuration: configuration);

  /// Compatibility view for media_kit_video's platform-specific controllers.
  PlatformPlayer? get platform => this;

  /// Whether the [NativePlayer] is initialized for unit-testing.
  @visibleForTesting
  static bool test = false;

  // Compile-face parity with the io [NativePlayer]: under `--wasm`, this stub
  // is what media_kit code compiles against, so the mpv property/command
  // surface used by the HDR backend must exist (it always throws here).

  /// Compile-face parity for the per-player, non-reentrant playback lock.
  final Lock lock = Lock();
  late final NativeSourceTransitionGate _sourceTransitions =
      NativeSourceTransitionGate(lock);

  Future<T> runSourceTransition<T>(Future<T> Function() body) =>
      _sourceTransitions.run(body);

  @override
  Future<void> open(
    Playable playable, {
    bool play = true,
    bool synchronized = true,
  }) async {
    throw UnsupportedError('[NativePlayer.open] requires dart:ffi');
  }

  /// Compile-face parity with the native container-only source discovery API.
  Future<void> openContainerProbe(
    Playable playable, {
    bool synchronized = true,
    bool automaticSubtitles = true,
  }) async {
    if (playable is! Media) {
      throw ArgumentError.value(playable, 'playable',
          'Container source discovery accepts exactly one Media entry');
    }
    throw UnsupportedError(
        '[NativePlayer.openContainerProbe] requires dart:ffi');
  }

  @override
  Future<void> stop({
    bool open = false,
    bool notify = true,
    bool synchronized = true,
    bool waitForVideoControllerInitialization = true,
  }) async {
    throw UnsupportedError('[NativePlayer.stop] requires dart:ffi');
  }

  /// Raw mpv property access parity with the io [NativePlayer].
  Future<void> setPropertyStrict(
    String property,
    String value, {
    bool waitForInitialization = true,
  }) async {
    throw UnsupportedError(
      '[NativePlayer.setPropertyStrict] is not supported in the wasm compile stub: the native player requires dart:ffi',
    );
  }

  /// Raw mpv property access parity with the io [NativePlayer].
  Future<String> getPropertyAsync(
    String property, {
    bool waitForInitialization = true,
  }) async {
    throw UnsupportedError(
      '[NativePlayer.getProperty] is not supported in the wasm compile stub: the native player requires dart:ffi',
    );
  }

  @override
  Future<List<String>> getPropertiesAsync(
    List<String> properties, {
    bool waitForInitialization = true,
  }) async {
    throw UnsupportedError(
      '[NativePlayer.getPropertiesAsync] requires dart:ffi',
    );
  }

  /// Raw mpv command invocation parity with the io [NativePlayer].
  Future<void> command(
    List<String> command, {
    bool waitForInitialization = true,
  }) async {
    throw UnsupportedError(
      '[NativePlayer.command] is not supported in the wasm compile stub: the native player requires dart:ffi',
    );
  }
}
