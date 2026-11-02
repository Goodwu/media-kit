import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_hdr_lab/common/android_p84_atlas_reuse_probe.dart';
import 'android_p84_quality_probe_test.dart' as quality_fixture;

class Fixture {
  final quality = quality_fixture.Fixture();
  final logs = StreamController<String>(sync: true);
  final rows = <Map<String, Object?>>[];
  final config = P84AtlasReuseConfig('a' * 32, 35.035, 600.032766667);
  String ack = '';
  late final runner = AndroidP84AtlasReuseProbe(config: config, quality: quality.probe,
    nativeLogs: logs.stream, readAck: () async => ack,
    currentOwnerValid: () => quality.owner == quality.initial,
    record: (row) async => rows.add(row),
    delay: (_) => Future<void>.delayed(Duration.zero));

  Map<String, String> receipt(String event) => {'event': event, 'stage':'1','ordinal':'1',
    'nonce': config.nonce, 'cache_id':'7','cache_generation':'1','renderer_id':'8',
    'renderer_generation':'1','signature':'b' * 64,'seed_capture_id':'9',
    'seed_pts':'35.035000000','t2_pts':'600.032766667'};
  void emit(String event, [Map<String, String> changes = const {}]) {
    final values = {...receipt(event), ...changes};
    logs.add('MKS-UV-ATLAS-READ ${values.entries.map((e) => '${e.key}=${e.value}').join(' ')}');
  }
  Future<void> until(bool Function() check) async {
    for (var i = 0; i < 500; i++) {
      if (check()) return;
      await Future<void>.delayed(Duration.zero);
    }
    throw StateError('Fixture failed to converge: ${runner.status}');
  }
  Future<void> readyForAck() async {
    await until(() => quality.rows.any((row) => row['status'] == 'ready-for-observation'));
    emit('promoted-ready');
    await until(() => runner.status == 'awaiting-host-ack');
  }
  Future<void> close() async {
    await runner.cancelAndDrain();
    await logs.close();
  }
}

void main() {
  test('default off and explicit complete clean startup controls', () {
    expect(P84AtlasReuseConfig.parse({P84AtlasReuseConfig.property:''}), isNull);
    expect(P84AtlasReuseConfig.parse({P84AtlasReuseConfig.property:'0'}), isNull);
    final values = {for (final key in P84AtlasReuseConfig.properties) key:'0',
      P84AtlasReuseConfig.property:'1',P84AtlasReuseConfig.nextPTS:'600.032766667',
      P84AtlasReuseConfig.nonceProperty:'a' * 32,P84AtlasReuseConfig.ackProperty:'',
      'debug.mks.yuv_compare':'1','debug.mks.yuv_atlas':'1','debug.mks.yuv_fusion':'1',
      'debug.mks.quality_pts':'35.035','debug.mks.yuv_compare_pts':'35.035'};
    expect(P84AtlasReuseConfig.parse(values)!.secondPTS, 600.032766667);
    for (final change in [
      {P84AtlasReuseConfig.property:'2'}, {P84AtlasReuseConfig.nonceProperty:'A' * 32},
      {P84AtlasReuseConfig.ackProperty:'old:7'}, {P84AtlasReuseConfig.nextPTS:'35.035'},
      {P84AtlasReuseConfig.nextPTS:'nan'}, {'debug.mks.yuv_oracle':'1'},
      {'debug.mks.yuv_compare_pts':'35.036'}, {'debug.mks.yuv_fusion':'0'},
    ]) {
      expect(() => P84AtlasReuseConfig.parse({...values,...change}), throwsStateError);
    }
  });

  test('same probe cannot seek2 before host ACK and matching native acceptance', () async {
    final f = Fixture();addTearDown(f.close);
    final run = f.runner.run();
    await f.readyForAck();
    final oldMonitor = f.quality.heartbeatTicks.last;
    expect(f.quality.rows.where((r) => r['status'] == 'seek-started').length, 1);
    f.ack = '${f.config.nonce}:7';
    await f.until(() => f.runner.status == 'awaiting-native-ack');
    expect(f.quality.rows.where((r) => r['status'] == 'seek-started').length, 1);
    f.emit('ack-accepted');
    await run;
    expect(f.runner.status, 'second-observation-ready');
    final seeks = f.quality.rows.where((r) => r['status'] == 'seek-started').toList();
    expect(seeks.map((r) => r['ordinal']), [1,2]);
    expect(seeks.map((r) => r['requestedPTS']), [35.035,600.032766667]);
    expect(seeks[0]['owner'], seeks[1]['owner']);
    final count = f.quality.rows.length;
    oldMonitor.complete();await Future<void>.delayed(Duration.zero);
    expect(f.quality.rows.length, count);
    await expectLater(f.runner.run(), throwsStateError);
  });

  test('native receipt mismatches and terminal diagnostics never trigger seek2', () async {
    for (final changes in [
      {'nonce':'c' * 32}, {'cache_id':'0'}, {'renderer_generation':'0'},
      {'signature':'B' * 64}, {'seed_pts':'35.036'}, {'t2_pts':'720.052666667'},
      {'ordinal':'2'}, {'stage':'2'}, {'cache_generation':'18446744073709551616'},
    ]) {
      final f = Fixture();
      final rejection = expectLater(f.runner.run(), throwsStateError);
      await f.until(() => f.quality.rows.any((r) => r['status'] == 'ready-for-observation'));
      f.emit('promoted-ready', changes);await rejection;
      expect(f.quality.rows.where((r) => r['status'] == 'seek-started').length, 1);
      await f.close();
    }
    for (final event in ['capture-diagnostic-invalid','capture-failed','config-invalid','cleanup-deferred','unknown']) {
      final f = Fixture();final rejection = expectLater(f.runner.run(), throwsStateError);
      await f.readyForAck();f.emit(event);await rejection;
      expect(f.quality.rows.where((r) => r['status'] == 'seek-started').length, 1);
      await f.close();
    }
  });

  test('stale ACK, changed identity, duplicate promotion and premature ACK are rejected', () async {
    for (final scenario in ['stale','changed','duplicate','premature']) {
      final f = Fixture();final rejection = expectLater(f.runner.run(), throwsStateError);
      await f.readyForAck();
      if (scenario == 'stale') f.ack = '${'c' * 32}:7';
      if (scenario == 'changed') {
        f.ack = '${f.config.nonce}:7';f.emit('ack-accepted', {'cache_id':'8'});
      }
      if (scenario == 'duplicate') f.emit('promoted-ready');
      if (scenario == 'premature') f.emit('ack-accepted');
      await rejection;
      expect(f.quality.rows.where((r) => r['status'] == 'seek-started').length, 1);
      await f.close();
    }
  });

  test('owner change, cancellation, stage and total deadlines cannot advance', () async {
    for (final scenario in ['owner','cancel','stage','total']) {
      final f = Fixture();
      var clock = DateTime(2026);
      final runner = scenario == 'stage' || scenario == 'total'
          ? AndroidP84AtlasReuseProbe(config:f.config,quality:f.quality.probe,nativeLogs:f.logs.stream,
            readAck:() async => '',currentOwnerValid:() => true,record:(row) async => f.rows.add(row),
            stageTimeout:Duration(seconds: scenario == 'stage' ? 1 : 10),
            totalTimeout:Duration(seconds: scenario == 'total' ? 1 : 10),now:() => clock,
            delay:(_) async { clock = clock.add(const Duration(seconds:2)); }) : f.runner;
      final rejection = expectLater(runner.run(), throwsA(anything));
      if (scenario == 'owner' || scenario == 'cancel') {
        await f.readyForAck();
        if (scenario == 'owner') f.quality.owner = null;
        if (scenario == 'cancel') await runner.cancelAndDrain();
      }
      await rejection;
      expect(f.quality.rows.where((r) => r['status'] == 'seek-started').length, 1);
      await runner.cancelAndDrain();await f.logs.close();
    }
  });
}
