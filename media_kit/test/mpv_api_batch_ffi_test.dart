import 'dart:ffi';
import 'dart:io';

import 'package:media_kit/ffi/ffi.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as generated;
import 'package:media_kit/src/player/native/core/mpv_api_isolate.dart';
import 'package:test/test.dart';

const _normal = 0;
const _error = 1;
const _wrongCount = 2;
const _wrongRootType = 3;
const _wrongItemType = 4;

String? _fixtureSkipReason() {
  if (!Platform.isMacOS) {
    return 'Native ABI fixture currently requires macOS (-dynamiclib).';
  }
  final roots = [
    Directory.current,
    Directory('${Directory.current.path}/media_kit'),
  ];
  final packageRoot = roots.firstWhere(
    (root) => File('${root.path}/test/native/mpv_property_batch_fixture.c')
        .existsSync(),
    orElse: () => Directory.current,
  );
  final fixture =
      File('${packageRoot.path}/test/native/mpv_property_batch_fixture.c');
  if (!fixture.existsSync()) {
    return 'Native ABI fixture source test/native/mpv_property_batch_fixture.c is unavailable.';
  }
  final header =
      File('${packageRoot.parent.parent.path}/mpv/include/mpv/client.h');
  if (!header.existsSync()) {
    return 'Native ABI fixture requires adjacent mpv/include/mpv/client.h.';
  }
  try {
    final clang = Process.runSync('clang', ['--version']);
    if (clang.exitCode != 0) {
      return 'Native ABI fixture requires executable clang.';
    }
  } on ProcessException {
    return 'Native ABI fixture requires executable clang.';
  }
  return null;
}

void main() {
  final skipReason = _fixtureSkipReason();
  if (skipReason != null) {
    test('native property batch FFI fixture prerequisites', () {},
        skip: skipReason);
    return;
  }

  Directory? tempDirectory;
  late DynamicLibrary library;
  late generated.MPV bindings;
  late Pointer<generated.mpv_handle> handle;
  late void Function(int) reset;
  late int Function() scalarCalls;
  late int Function() batchCalls;
  late int Function() nodeContentsCalls;
  late int Function() allocatedObjects;
  late int Function() freedObjects;
  late MpvMediakitGetPropertyStringsDart batchReader;

  const names = <Object?>[
    'second',
    'missing',
    'empty',
    'unicode',
    'second',
  ];
  const expected = <String?>[
    'second',
    null,
    '',
    'Dolby Vision 🎞',
    'second',
  ];

  setUpAll(() async {
    final roots = [
      Directory.current,
      Directory('${Directory.current.path}/media_kit'),
    ];
    final packageRoot = roots.firstWhere(
      (root) => File('${root.path}/test/native/mpv_property_batch_fixture.c')
          .existsSync(),
      orElse: () => Directory.current,
    );
    final fixture =
        File('${packageRoot.path}/test/native/mpv_property_batch_fixture.c');
    final mpvInclude =
        Directory('${packageRoot.parent.parent.path}/mpv/include');
    if (!fixture.existsSync() ||
        !File('${mpvInclude.path}/mpv/client.h').existsSync()) {
      throw StateError(
          'Native fixture or ../mpv/include/mpv/client.h is unavailable');
    }
    tempDirectory = await Directory.systemTemp.createTemp('mk-mpv-batch-');
    final output = '${tempDirectory!.path}/libmpv_property_batch'
        '${Platform.isMacOS ? '.dylib' : '.so'}';
    final compileFlags =
        Platform.isMacOS ? ['-dynamiclib'] : ['-shared', '-fPIC'];
    final compile = await Process.run('clang', [
      ...compileFlags,
      '-I',
      mpvInclude.path,
      fixture.path,
      '-o',
      output,
    ]);
    if (compile.exitCode != 0) {
      throw StateError('clang fixture build failed: ${compile.stderr}');
    }

    library = DynamicLibrary.open(output);
    bindings = generated.MPV(library);
    handle = Pointer<generated.mpv_handle>.fromAddress(1);
    reset = library.lookupFunction<Void Function(Int32), void Function(int)>(
        'fixture_reset');
    scalarCalls = library.lookupFunction<Int32 Function(), int Function()>(
        'fixture_scalar_calls');
    batchCalls = library.lookupFunction<Int32 Function(), int Function()>(
        'fixture_batch_calls');
    nodeContentsCalls =
        library.lookupFunction<Int32 Function(), int Function()>(
            'fixture_node_contents_calls');
    allocatedObjects = library.lookupFunction<Int32 Function(), int Function()>(
        'fixture_allocated_objects');
    freedObjects = library.lookupFunction<Int32 Function(), int Function()>(
        'fixture_freed_objects');
    batchReader = library.lookupFunction<MpvMediakitGetPropertyStringsNative,
        MpvMediakitGetPropertyStringsDart>('mpv_mediakit_get_property_strings');
  });

  tearDownAll(() async {
    await tempDirectory?.delete(recursive: true);
  });

  setUp(() => reset(_normal));

  test('scalar fallback preserves order, duplicates, null, empty and Unicode',
      () {
    final (errorCode, value) = performMpvApiOp(
        bindings, MpvApiOp.getPropertyStringList, handle, [names]);

    expect(errorCode, -1);
    expect(value, expected);
    expect(scalarCalls(), names.length);
    expect(batchCalls(), 0);
    expect(nodeContentsCalls(), 0);
    expect(allocatedObjects(), freedObjects());
  });

  test('native batch decodes the same values with one native call', () {
    final (errorCode, value) = performMpvApiOp(
      bindings,
      MpvApiOp.getPropertyStringList,
      handle,
      [names],
      readPropertyStrings: batchReader,
    );

    expect(errorCode, 0);
    expect(value, expected);
    expect(batchCalls(), 1);
    expect(scalarCalls(), 0);
    expect(nodeContentsCalls(), 1);
    expect(allocatedObjects(), freedObjects());
  });

  test('native error result is translated and its partial node is freed', () {
    reset(_error);
    final (errorCode, value) = performMpvApiOp(
      bindings,
      MpvApiOp.getPropertyStringList,
      handle,
      [names],
      readPropertyStrings: batchReader,
    );

    expect(errorCode, -5);
    expect(value, List<String?>.filled(names.length, null));
    expect(batchCalls(), 1);
    expect(scalarCalls(), 0);
    expect(nodeContentsCalls(), 1);
    expect(allocatedObjects(), freedObjects());
  });

  for (final mode in [_wrongCount, _wrongRootType, _wrongItemType]) {
    test('malformed native batch mode $mode throws and frees node contents',
        () {
      reset(mode);
      expect(
        () => performMpvApiOp(
          bindings,
          MpvApiOp.getPropertyStringList,
          handle,
          [names],
          readPropertyStrings: batchReader,
        ),
        throwsA(isA<StateError>()),
      );
      expect(batchCalls(), 1);
      expect(scalarCalls(), 0);
      expect(nodeContentsCalls(), 1);
      expect(allocatedObjects(), freedObjects());
    });
  }

  test('more than 4096 names uses scalar fallback despite callback', () {
    final oversized = List<Object?>.filled(4097, 'duplicate');
    final (errorCode, value) = performMpvApiOp(
      bindings,
      MpvApiOp.getPropertyStringList,
      handle,
      [oversized],
      readPropertyStrings: batchReader,
    );

    expect(errorCode, -1);
    expect(value, List<String?>.filled(oversized.length, 'duplicate'));
    expect(batchCalls(), 0);
    expect(scalarCalls(), oversized.length);
    expect(nodeContentsCalls(), 0);
    expect(allocatedObjects(), freedObjects());
  });
}
