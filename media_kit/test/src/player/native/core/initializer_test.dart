/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:ffi';
import 'dart:async';
import 'package:path/path.dart';
import 'package:test/test.dart';

import 'package:media_kit/ffi/ffi.dart';

import 'package:media_kit/src/player/native/core/initializer.dart';
import 'package:media_kit/src/player/native/core/native_library.dart';

import 'package:media_kit/generated/libmpv/bindings.dart';

MPV? _mpv;
MPV get mpv => _mpv!;

void _preloadFrameworkDependencies() {
  final bundlePath = Platform.environment['MEDIA_KIT_TEST_FRAMEWORKS'];
  if (bundlePath == null) return;
  final pending = <String>[];
  for (final entity in Directory(bundlePath).listSync(followLinks: true)) {
    if (entity is Directory && entity.path.endsWith('.framework')) {
      final executable = File(
        join(entity.path, 'Versions', 'A',
            basenameWithoutExtension(entity.path)),
      );
      if (executable.existsSync()) pending.add(executable.path);
    } else if (entity is File && entity.path.endsWith('.dylib')) {
      pending.add(entity.path);
    }
  }
  while (pending.isNotEmpty) {
    var loaded = false;
    for (final candidate in pending.toList()) {
      try {
        DynamicLibrary.open(candidate);
        pending.remove(candidate);
        loaded = true;
      } catch (_) {}
    }
    if (!loaded) break;
  }
}

void main() {
  setUp(() {
    _preloadFrameworkDependencies();
    NativeLibrary.ensureInitialized();
    _mpv = MPV(DynamicLibrary.open(NativeLibrary.path));
  });
  test(
    'initializer-init',
    () async {
      final handle = await Initializer(mpv).create((_) async {});
      await Initializer(mpv).dispose(handle);
    },
  );
  test(
    'initializer-create',
    () async {
      final handle = await Initializer(mpv).create((_) async {});
      await Initializer(mpv).dispose(handle);
    },
  );
  test(
    'initializer-dispose',
    () async {
      final handle = await Initializer(mpv).create((_) async {});
      await expectLater(Initializer(mpv).dispose(handle), completes);
    },
  );
  test(
    'initializer-callback',
    () async {
      final shutdown = Completer();

      final expectPauseTrue = expectAsync1((value) {
        print(value);
        expect(value, isTrue);
        shutdown.complete();
      });
      final expectShutdown = expectAsync0(() {
        print('shutdown');
        expect(true, isTrue);
      });

      final handle = await Initializer(mpv).create(
        (event) async {
          if (event.ref.event_id == mpv_event_id.MPV_EVENT_PROPERTY_CHANGE) {
            final prop = event.ref.data.cast<mpv_event_property>();
            if (prop.ref.name.cast<Utf8>().toDartString() == 'pause' &&
                prop.ref.format == mpv_format.MPV_FORMAT_FLAG) {
              final value = prop.ref.data.cast<Bool>().value;
              expectPauseTrue(value);
            }
          }
          if (event.ref.event_id == mpv_event_id.MPV_EVENT_SHUTDOWN) {
            expectShutdown();
          }
        },
      );
      await Future.delayed(Duration(seconds: 5));
      {
        final name = 'pause'.toNativeUtf8();
        mpv.mpv_observe_property(
          handle,
          0,
          name.cast(),
          mpv_format.MPV_FORMAT_FLAG,
        );
        calloc.free(name);
      }
      {
        final command = 'cycle pause'.toNativeUtf8();
        mpv.mpv_command_string(
          handle,
          command.cast(),
        );
        calloc.free(command);
      }
      await shutdown.future;
      {
        final command = 'quit 0'.toNativeUtf8();
        mpv.mpv_command_string(
          handle,
          command.cast(),
        );
        calloc.free(command);
      }

      await Future.delayed(const Duration(seconds: 5));

      await Initializer(mpv).dispose(handle);
    },
  );
  test(
    'initializer-options-with-callback',
    () async {
      final handle = await Initializer(mpv).create(
        (_) async {},
        options: {
          'config': 'yes',
          'config-dir': dirname(Platform.script.toFilePath()),
        },
      );
      {
        final name = 'config'.toNativeUtf8();
        final value = mpv.mpv_get_property_string(
          handle,
          name.cast(),
        );
        calloc.free(name);
        expect(
          value.cast<Utf8>().toDartString(),
          'yes',
        );
      }
      {
        final name = 'config-dir'.toNativeUtf8();
        final value = mpv.mpv_get_property_string(
          handle,
          name.cast(),
        );
        calloc.free(name);
        expect(
          value.cast<Utf8>().toDartString(),
          dirname(Platform.script.toFilePath()),
        );
      }

      await Future.delayed(const Duration(seconds: 5));

      await Initializer(mpv).dispose(handle);
    },
  );
}
