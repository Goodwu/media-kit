import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit/src/compat/legacy_media_options.dart';

void main() {
  test('no legacy options leaves an ordinary loadfile command', () {
    final options = LegacyMediaOptions.fromExtras(null);
    expect(options.isEmpty, isTrue);
    expect(options.appendArguments('file.mp4', apiVersion: 0x20003),
        ['loadfile', 'file.mp4', 'append']);
  });
  test('unknown application data cannot set decoder/output or scripts', () {
    final options = LegacyMediaOptions.fromExtras({
      'hwdec': 'no', 'vo': 'null', 'scripts': 'foreign.lua',
      'http-header-fields': 'Cookie: private', 'record': Object(),
      'track-auto-selection': 'no', 'vid': 'auto', 'aid': 'auto',
      'sid': 'auto', 'secondary-sid': 'no',
    });
    expect(options.isEmpty, isTrue);
  });
  test('typed container probe options preserve request fields and headers', () {
    final options = LegacyMediaOptions.fromExtras({
      // These untrusted extras must not replace the trusted probe policy.
      'track-auto-selection': 'yes', 'vid': '2', 'aid': '3', 'sid': '4',
      'secondary-sid': 'yes',
    },
      containerProbe: true,
      start: const Duration(milliseconds: 1234),
      end: const Duration(seconds: 9),
      httpHeaders: const {'X-Probe': 'preserved'},
    );
    expect(options.values, {
      'start': '1.234',
      'end': '9.000',
      'track-auto-selection': 'no',
      'vid': 'auto',
      'aid': 'auto',
      'sid': 'auto',
      'secondary-sid': 'no',
    });
    expect(options.encoded, contains('http-header-fields=%18%x-probe: preserved'));
    expect(options.appendArguments('probe.mp4', apiVersion: 0x20003), [
      'loadfile', 'probe.mp4', 'append', '-1', options.encoded,
    ]);
  });
  test('container probe can preserve an explicitly disabled subtitle selector', () {
    final disabled = LegacyMediaOptions.fromExtras(null,
        containerProbe: true, probeAutomaticSubtitles: false);
    expect(disabled.values['sid'], 'no');
    expect(disabled.values['track-auto-selection'], 'no');
    expect(disabled.values['vid'], 'auto');
    expect(disabled.values['aid'], 'auto');
    expect(disabled.values['secondary-sid'], 'no');

    final defaultProbe = LegacyMediaOptions.fromExtras(null, containerProbe: true);
    expect(defaultProbe.values['sid'], 'auto');
    final ordinary = LegacyMediaOptions.fromExtras(null,
        probeAutomaticSubtitles: false);
    expect(ordinary.isEmpty, isTrue);
  });
  test('original buffering option set survives', () {
    final options = LegacyMediaOptions.fromExtras({
      'cache': 'yes', 'cache-secs': '120.000',
      'demuxer-hysteresis-secs': '80.000',
      'demuxer-max-bytes': '104857600',
      'demuxer-max-back-bytes': '104857600',
    });
    expect(options.values.length, 5);
    expect(options.values['demuxer-hysteresis-secs'], '80.000');
    expect(options.encoded, contains('cache=%3%yes'));
  });
  test('options are frozen without changing extras', () {
    final extras = <String, dynamic>{'cache': 'yes'};
    final options = LegacyMediaOptions.fromExtras(extras);
    extras['cache'] = 'no';
    expect(options.values['cache'], 'yes');
    expect(() => options.values['cache'] = 'no', throwsUnsupportedError);
  });
  test('old whole-graph quotes are removed once, commas retained', () {
    const graph = '[aid1] dynaudnorm=g=5,anull [ao]';
    final options = LegacyMediaOptions.fromExtras({'lavfi-complex': '"$graph"'});
    expect(options.values['lavfi-complex'], graph);
    expect(options.encoded, 'lavfi-complex=%${utf8.encode(graph).length}%$graph');
  });
  test('UTF-8 length, delimiters and equals cannot inject another option', () {
    const value = '[aid1] volume=1,ametadata=key=标签:value=50% [ao]';
    final options = LegacyMediaOptions.fromExtras({'lavfi-complex': '"$value"'});
    expect(options.encoded, 'lavfi-complex=%${utf8.encode(value).length}%$value');
    final injection = LegacyMediaOptions.fromExtras({'cache': 'yes,vo=null'});
    expect(injection.encoded, 'cache=%11%yes,vo=null');
    expect(injection.values.keys, ['cache']);
  });
  test('empty graph is an explicit empty file-scoped value', () {
    expect(LegacyMediaOptions.fromExtras({'lavfi-complex': '""'}).encoded,
        'lavfi-complex=%0%');
  });
  test('legacy API versions put the options argument in its correct position', () {
    final options = LegacyMediaOptions.fromExtras({'cache': 'no'});
    expect(options.appendArguments('x', apiVersion: 0x20002),
        ['loadfile', 'x', 'append', 'cache=%2%no']);
    expect(options.appendArguments('x', apiVersion: 0x20003),
        ['loadfile', 'x', 'append', '-1', 'cache=%2%no']);
  });
  test('EDL is preserved as one opaque argument, including Unicode and separators', () {
    const video = '/tmp/视频;,=%.mp4';
    const audio = '/tmp/声音;,=%.m4a';
    final edl = 'edl://!no_chapters;%${utf8.encode(video).length}%$video;'
        '!new_stream;!no_chapters;%${utf8.encode(audio).length}%$audio';
    expect(Media(edl, extras: const {}).uri, edl);
    final command = LegacyMediaOptions.fromExtras({'cache': 'yes'})
        .appendArguments(edl, apiVersion: 0x20003);
    expect(command[1], edl);
    expect(command.length, 5);
  });
  test('same URI entries keep independently requested options', () {
    final first = Media('https://example.invalid/shared.mp4', extras: {'cache': 'yes'});
    final second = Media(first.uri, extras: {'cache': 'no'});
    expect(LegacyMediaOptions.fromExtras(first.extras).encoded, 'cache=%3%yes');
    expect(LegacyMediaOptions.fromExtras(second.extras).encoded, 'cache=%2%no');
  });
  for (final value in [null, 3, true, <String>[], 'yes\u0000no', '"yes', '"a"b"']) {
    test('invalid declared value is rejected: ${value.runtimeType} ${value.toString().length}', () {
      expect(() => LegacyMediaOptions.fromExtras({'cache': value}), throwsArgumentError);
    });
  }
  test('NUL in URI is rejected rather than truncated by FFI', () {
    expect(() => LegacyMediaOptions.fromExtras(null)
        .appendArguments('file\u0000.mp4', apiVersion: 0x20003), throwsArgumentError);
  });
}
