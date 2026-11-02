import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_hdr_lab/common/android_p84_thermal_probe.dart';

List<Map<String, dynamic>> decodeRows(List<String> lines) {
  final rows = <Map<String, dynamic>>[];
  final parts = <String, List<String?>>{};
  for (final line in lines) {
    expect(utf8.encode(line).length, lessThan(800));
    if (line.startsWith('THERMAL_JSON_PART ')) {
      final part = jsonDecode(line.substring('THERMAL_JSON_PART '.length));
      final key = '${part['r']}:${part['n']}';
      final group = parts.putIfAbsent(
          key, () => List<String?>.filled(part['c'] as int, null));
      group[part['i'] as int] = part['d'] as String;
      if (group.every((part) => part != null)) {
        rows.add(jsonDecode(utf8.decode(base64Decode(group.join())))
            as Map<String, dynamic>);
        parts.remove(key);
      }
    } else if (line.startsWith('THERMAL_JSON ')) {
      rows.add(jsonDecode(line.substring('THERMAL_JSON '.length))
          as Map<String, dynamic>);
    }
  }
  return rows;
}

void main() {
  test('only accepted mode is written and a mismatch fails before open',
      () async {
    final writes = <String>[];
    final probe = AndroidP84ThermalProbe(
      serial: 1,
      isCurrent: () => true,
      readMode: () async => 'audio',
      writeProperty: (name, value) async => writes.add('$name=$value'),
      readProperty: (_) async => 'display-resample',
      readReport: () => {},
      emit: (_) {},
    );
    await expectLater(probe.prepare(), throwsStateError);
    expect(writes, ['video-sync=audio']);
    await probe.stop();
  });

  test('invalid or late mode never writes to the next source owner', () async {
    var current = true;
    final mode = Completer<String>();
    final writes = <String>[];
    final probe = AndroidP84ThermalProbe(
      serial: 1,
      isCurrent: () => current,
      readMode: () => mode.future,
      writeProperty: (name, value) async => writes.add('$name=$value'),
      readProperty: (_) async => 'audio',
      readReport: () => {},
      emit: (_) {},
    );
    final preparation = probe.prepare();
    current = false;
    mode.complete('audio');
    await expectLater(preparation, throwsStateError);
    expect(writes, isEmpty);
    await probe.stop();

    final invalid = AndroidP84ThermalProbe(
      serial: 2,
      isCurrent: () => true,
      readMode: () async => 'invalid',
      writeProperty: (name, value) async => writes.add('$name=$value'),
      readProperty: (_) async => 'audio',
      readReport: () => {},
      emit: (_) {},
    );
    await expectLater(invalid.prepare(), throwsStateError);
    expect(writes, isEmpty);
    await invalid.stop();
  });

  test('overlap is coalesced; stop drains a stale query without another read',
      () async {
    var current = true;
    final blocked = Completer<String>();
    final reads = <String>[];
    final lines = <String>[];
    final probe = AndroidP84ThermalProbe(
      serial: 3,
      isCurrent: () => current,
      readMode: () async => 'audio',
      writeProperty: (_, __) async {},
      readProperty: (name) {
        reads.add(name);
        return name == 'time-pos' ? blocked.future : Future.value('audio');
      },
      readReport: () => {},
      emit: lines.add,
    );
    await probe.prepare();
    final first = probe.sample();
    final second = probe.sample();
    var stopped = false;
    current = false;
    final stop = probe.stop().then((_) => stopped = true);
    await Future<void>.delayed(Duration.zero);
    expect(stopped, isFalse);
    blocked.complete('12');
    await Future.wait([first, second, stop]);
    expect(reads, ['video-sync', 'time-pos']);
    expect(lines, hasLength(1)); // only prepared; no stale live fact
    await probe.sample();
    expect(reads, ['video-sync', 'time-pos']);
  });

  test('start and end retain live hwdec separately from cached route report',
      () async {
    final lines = <String>[];
    var readCount = 0;
    final probe = AndroidP84ThermalProbe(
      serial: 4,
      isCurrent: () => true,
      readMode: () async => 'audio',
      writeProperty: (_, __) async {},
      readProperty: (name) async {
        readCount++;
        if (name == 'video-sync') return 'audio';
        if (name == 'hwdec-current') return 'no';
        if (name == 'video-codec') throw StateError('unavailable');
        return '';
      },
      readReport: () => {'verified': true, 'hwdecCurrent': 'surfacetexture'},
      emit: lines.add,
    );
    await probe.prepare();
    await probe.start();
    await probe.stop();
    final samples = decodeRows(lines);
    expect(samples.map((row) => row['phase']), ['prepared', 'start', 'end']);
    expect(samples.last['properties']['hwdec-current'], 'no');
    expect(samples.last['report']['hwdecCurrent'], 'surfacetexture');
    expect(
        samples.last['propertyErrors']['video-codec'], contains('unavailable'));
    final readsAtStop = readCount;
    await probe.stop();
    await probe.sample();
    expect(readCount, readsAtStop);
  });

  test('a session generation change invalidates subsequent native samples',
      () async {
    var generation = 10;
    var reads = 0;
    final probe = AndroidP84ThermalProbe(
      serial: 5,
      isCurrent: () => true,
      readMode: () async => 'audio',
      writeProperty: (_, __) async {},
      readProperty: (name) async {
        reads++;
        return name == 'video-sync' ? 'audio' : '';
      },
      readReport: () => {'generation': generation},
      emit: (_) {},
    );
    await probe.prepare();
    await probe.start();
    final initialReads = reads;
    generation++;
    await probe.sample();
    await probe.stop();
    expect(reads, initialReads);
  });

  test('large payload is losslessly chunked below the LG log limit', () async {
    final lines = <String>[];
    final probe = AndroidP84ThermalProbe(
      serial: 6,
      isCurrent: () => true,
      readMode: () async => 'audio',
      writeProperty: (_, __) async {},
      readProperty: (name) async => name == 'video-sync'
          ? 'audio'
          : name == 'video-codec'
              ? 'x' * 5000
              : '',
      readReport: () => {'generation': 1},
      emit: lines.add,
    );
    await probe.prepare();
    await probe.start();
    await probe.stop();
    final rows = decodeRows(lines);
    expect(rows.map((row) => row['phase']), ['prepared', 'start', 'end']);
    expect(rows.last['properties']['video-codec'], 'x' * 5000);
    final withoutOneChunk = List<String>.of(lines)
      ..removeAt(
          lines.indexWhere((line) => line.startsWith('THERMAL_JSON_PART')));
    expect(decodeRows(withoutOneChunk).map((row) => row['phase']),
        ['prepared', 'end']);
  });

  test('open failure is observable before any teardown sampling', () async {
    final lines = <String>[];
    final probe = AndroidP84ThermalProbe(
      serial: 7,
      isCurrent: () => true,
      readMode: () async => 'audio',
      writeProperty: (_, __) async {},
      readProperty: (_) async => 'audio',
      readReport: () => {'generation': 3, 'verified': false, 'actual': null},
      emit: lines.add,
    );
    probe.reportError(StateError('decoder init failed'));
    expect(lines.single, startsWith('THERMAL_ERROR '));
    expect(utf8.encode(lines.single).length, lessThan(800));
    expect(lines.single, contains('decoder init failed'));
    await probe.stop();
  });
}
