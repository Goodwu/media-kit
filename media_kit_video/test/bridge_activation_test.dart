import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/bridge_activation.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/platform_output_availability.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/platform_surface_release.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/surface_owner_ledger.dart';

/// Records every strict property write and lets the test hold or fail each
/// ACK individually (the fake strict setter).
class _FakeStrictSetter {
  _FakeStrictSetter({this.holds = const {}});

  /// Keys whose ACK is held until the test completes the completer.
  final Map<String, Completer<void>> holds;
  final writes = <String>[];
  final pending = <String, Completer<void>>{};
  final errors = <String, Object>{};

  Future<void> call(String key, String value) {
    final entry = '$key=$value';
    writes.add(entry);
    final error = errors[entry] ?? errors[key];
    if (error != null) throw error;
    final hold = holds[entry] ?? holds[key];
    if (hold != null) {
      final waiter = Completer<void>();
      pending[entry] = waiter;
      hold.future.whenComplete(() => waiter.complete());
      return waiter.future;
    }
    return Future<void>.value();
  }

  void fail(String keyOrEntry, Object error) => errors[keyOrEntry] = error;
}

/// Records every authorization request and lets the test script replies,
/// failures and never-returning calls (the fake authorization channel).
/// Futures are created lazily at call time so scripted errors are never
/// unhandled before the protocol attaches its listeners.
class _FakeAuthorizeChannel {
  _FakeAuthorizeChannel();
  final requests = <BridgeAuthorizationRequest>[];
  final _scripts = <Object Function()>[];
  int get calls => requests.length;

  void replyNext(Object? value) {
    _scripts.add(() => Future<Object?>.value(value));
  }

  void failNext(Object error) {
    _scripts.add(() => Future<Object?>.error(error));
  }

  void holdNext() {
    final held = Completer<Object?>();
    _scripts.add(() => held.future);
  }

  Future<Object?> call(BridgeAuthorizationRequest request) {
    requests.add(request);
    if (_scripts.isEmpty) return Future<Object?>.value(null);
    return _scripts.removeAt(0)() as Future<Object?>;
  }
}

const _owner = AndroidSurfaceAccountId(
  handle: 11,
  generation: 3,
  viewId: 7,
  surfaceGeneration: 2,
  wid: 4242,
);

BridgeAuthorizationRequest get _request => BridgeAuthorizationRequest(
      handle: _owner.handle,
      generation: _owner.generation,
      viewId: _owner.viewId,
      surfaceGeneration: _owner.surfaceGeneration,
      wid: _owner.wid,
      ownerToken: 'mk-owner-test',
    );

Map<String, Object?> _okReply({
  bool applicable = true,
  Object? ownerGeneration = 3,
  Object? surfaceGeneration = 2,
  bool ok = true,
}) =>
    <String, Object?>{
      'applicable': applicable,
      'ok': ok,
      'code': 'ok',
      'ownerGeneration': ownerGeneration,
      'surfaceGeneration': surfaceGeneration,
      'message': null,
    };

Map<String, Object?> _failureReply(String code,
        {bool applicable = true, bool ok = false}) =>
    <String, Object?>{
      'applicable': applicable,
      'ok': ok,
      'code': code,
      'ownerGeneration': code == 'staleIdentity' ? 3 : null,
      'surfaceGeneration': code == 'staleIdentity' ? 2 : null,
      'message': null,
    };

BridgeActivationProtocol _protocol(
  _FakeStrictSetter setter,
  _FakeAuthorizeChannel channel, {
  Duration timeout = const Duration(seconds: 5),
}) =>
    BridgeActivationProtocol(
      strictSetter: setter.call,
      invokeAuthorization: channel.call,
      authorizationTimeout: timeout,
    );

/// The barrier a bind transaction would build: guarded + traced authorize.
Future<void> Function() _barrier(
  BridgeActivationProtocol protocol, {
  bool Function()? stillCurrent,
}) {
  final guard = stillCurrent ?? () => true;
  return () => protocol.authorize(
        request: _request,
        stillCurrent: guard,
      );
}

Future<BridgeActivationTransaction> _apply(
  BridgeActivationProtocol protocol, {
  String widValue = '4242',
  String voValue = 'gpu-next',
  Future<void> Function()? barrier,
  bool Function()? stillCurrent,
  bool writeVid = true,
}) {
  return protocol.apply(
    widValue: widValue,
    voValue: voValue,
    vidValue: widValue == '0' ? 'no' : 'auto',
    androidSurfaceSizeValue: '1920x1080',
    writeVid: writeVid,
    authorizeActivation: barrier,
    activationStillCurrent: stillCurrent,
  );
}

void main() {
  test('authorization request encodes handle/wid as decimal strings',
      () async {
    expect(
      _request.asChannelArguments(),
      <String, Object>{
        'handle': '11',
        'generation': 3,
        'viewId': 7,
        'surfaceGeneration': 2,
        'wid': '4242',
        'ownerToken': 'mk-owner-test',
      },
    );
    expect(
      BridgeAuthorizationRequest(
        handle: 11,
        generation: 3,
        viewId: 7,
        surfaceGeneration: 2,
        wid: 4242,
        ownerToken: null,
      ).asChannelArguments().containsKey('ownerToken'),
      isFalse,
    );
  });

  group('BridgeActivationResult.fromMap', () {
    test('parses a successful reply', () {
      final result = BridgeActivationResult.fromMap(_okReply());
      expect(result.isOk, isTrue);
      expect(result.isStale, isFalse);
      expect(result.ownerGeneration, 3);
      expect(result.surfaceGeneration, 2);
    });

    test('present nulls parse while doubles never do', () {
      final result = BridgeActivationResult.fromMap(
        _okReply(ownerGeneration: null, surfaceGeneration: null),
      );
      expect(result.code, BridgeActivationCode.ok);
      expect(result.ownerGeneration, isNull);
      expect(
        BridgeActivationResult.fromMap(
          _okReply(ownerGeneration: 3.0),
        ).code,
        BridgeActivationCode.invalidArguments,
      );
    });

    test('rejects malformed replies as invalidArguments', () {
      final malformed = <Object?>[
        null,
        <String, Object?>{},
        <Object?>[1, 2],
        <String, Object?>{'applicable': true, 'ok': true},
        <String, Object?>{'applicable': true, 'code': 'ok'},
        <String, Object?>{'ok': true, 'code': 'ok'},
        // Six-key strictness: a present-but-null field is fine, a missing
        // key never is — not even `message` or the generations.
        <String, Object?>{
          'applicable': true,
          'ok': true,
          'code': 'ok',
          'ownerGeneration': 3,
          'surfaceGeneration': 2,
        },
        <String, Object?>{
          'applicable': true,
          'code': 'ok',
          'ownerGeneration': 3,
          'surfaceGeneration': 2,
          'message': null,
        },
        <String, Object?>{'applicable': 1, 'ok': true, 'code': 'ok',
          'ownerGeneration': null, 'surfaceGeneration': null, 'message': null},
        <String, Object?>{'applicable': true, 'ok': 'yes', 'code': 'ok',
          'ownerGeneration': null, 'surfaceGeneration': null, 'message': null},
        <String, Object?>{'applicable': true, 'ok': true, 'code': 0,
          'ownerGeneration': null, 'surfaceGeneration': null, 'message': null},
        <String, Object?>{'applicable': true, 'ok': true, 'code': 'madeUp',
          'ownerGeneration': null, 'surfaceGeneration': null, 'message': null},
        // An inconsistent applicable/code combination.
        <String, Object?>{'applicable': false, 'ok': true, 'code': 'ok',
          'ownerGeneration': null, 'surfaceGeneration': null, 'message': null},
        <String, Object?>{
          'applicable': true,
          'ok': true,
          'code': 'ok',
          'ownerGeneration': 3.5,
          'surfaceGeneration': 2,
          'message': null,
        },
        // Doubles are rejected even when integral (the standard codec only
        // widens Java double, never int).
        <String, Object?>{
          'applicable': true,
          'ok': true,
          'code': 'ok',
          'ownerGeneration': 3.0,
          'surfaceGeneration': 2,
          'message': null,
        },
        <String, Object?>{
          'applicable': true,
          'ok': true,
          'code': 'ok',
          'ownerGeneration': 3,
          'surfaceGeneration': '2',
          'message': null,
        },
      ];
      for (final raw in malformed) {
        final result = BridgeActivationResult.fromMap(raw);
        expect(result.isOk, isFalse, reason: '$raw parsed as success');
        expect(result.code, BridgeActivationCode.invalidArguments,
            reason: '$raw');
      }
    });

    test('parses the real Java notApplicable combination', () {
      final result = BridgeActivationResult.fromMap(
        <String, Object?>{
          'applicable': false,
          'ok': true,
          'code': 'notApplicable',
          'ownerGeneration': null,
          'surfaceGeneration': null,
          'message': null,
        },
      );
      expect(result.isOk, isFalse);
      expect(result.isStale, isFalse);
      expect(result.code, BridgeActivationCode.notApplicable);
    });
  });

  group('stop → authorize → apply ordering', () {
    test('stop begin → stop ACK → authorize → success → size/wid/vo/vid '
        'as one shared event sequence', () async {
      final setter = _FakeStrictSetter();
      final channel = _FakeAuthorizeChannel()..replyNext(_okReply());
      final events = <String>[];
      final protocol = BridgeActivationProtocol(
        strictSetter: setter.call,
        invokeAuthorization: channel.call,
        trace: events.add,
      );
      final transaction = await protocol.apply(
        widValue: '4242',
        voValue: 'gpu-next',
        vidValue: 'auto',
        androidSurfaceSizeValue: '1920x1080',
        writeVid: true,
        authorizeActivation: () => protocol.authorize(
              request: _request,
              stillCurrent: () => true,
              onResult: (result) => events.add('authorize reply '
                  '${result.code.name}'),
            ),
      );
      events.add('phase=${transaction.phase.name}');
      expect(events, <String>[
        'apply begin wid=4242 vo=gpu-next vid=auto',
        'property begin vo=null',
        'property complete vo=null',
        'authorize reply ok',
        'property begin android-surface-size=1920x1080',
        'property complete android-surface-size=1920x1080',
        'property begin wid=4242',
        'property complete wid=4242',
        'property begin vo=gpu-next',
        'property complete vo=gpu-next',
        'property begin vid=auto',
        'property complete vid=auto',
        'apply complete wid=4242',
        'phase=applied',
      ]);
      expect(channel.calls, 1);
    });

    test('a barrier-less apply makes zero channel calls and identical writes',
        () async {
      // mediacodec_embed/texture/RGB-window routes construct no barrier: the
      // gate unit below pins when that happens; this pins the resulting
      // zero-channel, zero-behavior-change apply.
      final setter = _FakeStrictSetter();
      final channel = _FakeAuthorizeChannel();
      final protocol = _protocol(setter, channel);
      await _apply(protocol);
      expect(channel.calls, 0);
      expect(setter.writes, <String>[
        'vo=null',
        'android-surface-size=1920x1080',
        'wid=4242',
        'vo=gpu-next',
        'vid=auto',
      ]);
    });

    test('the HOME empty-bound branch authorizes with no prior stop call',
        () async {
      // boundWid=null + stopPreviousFirst=false: the transaction's own first
      // vo=null is the only stop, and the authorization still runs.
      final setter = _FakeStrictSetter();
      final channel = _FakeAuthorizeChannel()..replyNext(_okReply());
      final protocol = _protocol(setter, channel);
      await _apply(protocol, barrier: _barrier(protocol));
      expect(channel.calls, 1);
      expect(setter.writes.first, 'vo=null');
    });

    test('a held stop ACK delays the authorization', () async {
      final stopHold = Completer<void>();
      final setter = _FakeStrictSetter(holds: {'vo=null': stopHold});
      final channel = _FakeAuthorizeChannel()..replyNext(_okReply());
      final protocol = _protocol(setter, channel);
      final pending = _apply(protocol, barrier: _barrier(protocol));
      await Future<void>.delayed(Duration.zero);
      expect(channel.calls, 0);
      stopHold.complete();
      await pending;
      expect(channel.calls, 1);
    });

    test('a wid=0 stop transaction never authorizes', () async {
      final setter = _FakeStrictSetter();
      final channel = _FakeAuthorizeChannel();
      final protocol = _protocol(setter, channel);
      // The caller passes a barrier anyway; the helper must hard-refuse it.
      await _apply(protocol,
          widValue: '0', voValue: 'null', barrier: _barrier(protocol));
      expect(channel.calls, 0);
      expect(setter.writes, <String>[
        'vo=null',
        'android-surface-size=1920x1080',
        'wid=0',
        'vo=null',
        'vid=no',
      ]);
    });

    test('the optional vid=no preface precedes the stop', () async {
      final setter = _FakeStrictSetter();
      final channel = _FakeAuthorizeChannel();
      final protocol = _protocol(setter, channel);
      await protocol.apply(
        widValue: '0',
        voValue: 'null',
        vidValue: 'no',
        androidSurfaceSizeValue: '1920x1080',
        writeVid: true,
        stopVideoFirst: true,
      );
      expect(setter.writes.first, 'vid=no');
      expect(setter.writes[1], 'vo=null');
    });
  });

  group('stop failures never authorize', () {
    test('a negative vo=null ACK propagates with zero authorize and zero wid',
        () async {
      final setter = _FakeStrictSetter()..fail('vo=null', StateError('ACK'));
      final channel = _FakeAuthorizeChannel()..replyNext(_okReply());
      final protocol = _protocol(setter, channel);
      await expectLater(
        _apply(protocol, barrier: _barrier(protocol)),
        throwsStateError,
      );
      expect(channel.calls, 0);
      expect(setter.writes.single, 'vo=null');
    });

    test('a timed-out stop ACK leaves the authorization unsent', () async {
      final setter = _FakeStrictSetter(
        holds: {'vo=null': Completer<void>()},
      );
      final channel = _FakeAuthorizeChannel()..replyNext(_okReply());
      final protocol = _protocol(setter, channel);
      final pending = _apply(protocol, barrier: _barrier(protocol));
      await Future<void>.delayed(Duration.zero);
      final movedOn = Completer<void>();
      pending.then<void>((_) => movedOn.complete(),
          onError: (Object _, StackTrace __) => movedOn.complete());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(movedOn.isCompleted, isFalse);
      expect(channel.calls, 0);
    });
  });

  group('authorization classification', () {
    for (final code in [
      'staleIdentity',
      'invalidArguments',
      'tokenMismatch',
      'invalidOwner',
      'initFailed',
    ]) {
      test('reply $code maps to the typed code and stops before wid',
          () async {
        final setter = _FakeStrictSetter();
        final channel = _FakeAuthorizeChannel()..replyNext(_failureReply(code));
        final protocol = _protocol(setter, channel);
        await expectLater(
          _apply(protocol, barrier: _barrier(protocol)),
          throwsA(isA<BridgeActivationException>()
              .having((error) => error.code.name, 'code', code)),
        );
        // Zero new wid writes: only the stop happened.
        expect(setter.writes.single, 'vo=null');
      });
    }

    test('the real Java notApplicable combination is a token-path failure '
        '(contract mismatch, decision A)', () async {
      final setter = _FakeStrictSetter();
      final channel = _FakeAuthorizeChannel()
        ..replyNext(<String, Object?>{
          'applicable': false,
          'ok': true,
          'code': 'notApplicable',
          'ownerGeneration': null,
          'surfaceGeneration': null,
          'message': null,
        });
      final protocol = _protocol(setter, channel);
      await expectLater(
        _apply(protocol, barrier: _barrier(protocol)),
        throwsA(isA<BridgeActivationException>().having(
            (error) => error.code, 'code', BridgeActivationCode.notApplicable)),
      );
      expect(setter.writes.single, 'vo=null');
    });

    test('a successful reply with mismatched generations is a stale discard',
        () async {
      final setter = _FakeStrictSetter();
      final channel = _FakeAuthorizeChannel()
        ..replyNext(_okReply(ownerGeneration: 4));
      final protocol = _protocol(setter, channel);
      await expectLater(
        _apply(protocol, barrier: _barrier(protocol)),
        throwsA(isA<BridgeActivationException>()
            .having((error) => error.code, 'code',
                BridgeActivationCode.staleIdentity)
            .having((error) => error.stale, 'stale', isTrue)),
      );
      expect(setter.writes.single, 'vo=null');
    });

    test('only staleIdentity classifies as stale', () {
      for (final code in BridgeActivationCode.values) {
        if (code == BridgeActivationCode.ok) continue;
        expect(isBridgeActivationStaleCode(code),
            code == BridgeActivationCode.staleIdentity,
            reason: code.name);
      }
    });

    test('a malformed reply is an invalidArguments failure', () async {
      final setter = _FakeStrictSetter();
      final channel = _FakeAuthorizeChannel()..replyNext('not-a-map');
      final protocol = _protocol(setter, channel);
      await expectLater(
        _apply(protocol, barrier: _barrier(protocol)),
        throwsA(isA<BridgeActivationException>().having(
            (error) => error.code, 'code', BridgeActivationCode.invalidArguments)),
      );
      expect(setter.writes.single, 'vo=null');
    });

    test('a channel exception is a channelError failure', () async {
      final setter = _FakeStrictSetter();
      final channel = _FakeAuthorizeChannel()
        ..failNext(PlatformException(code: 'E', message: 'channel'));
      final protocol = _protocol(setter, channel);
      await expectLater(
        _apply(protocol, barrier: _barrier(protocol)),
        throwsA(isA<BridgeActivationException>().having(
            (error) => error.code, 'code', BridgeActivationCode.channelError)),
      );
      expect(setter.writes.single, 'vo=null');
    });
  });

  group('timeout and late replies (C3)', () {
    test('a silent channel times out and never writes the new wid', () async {
      final setter = _FakeStrictSetter();
      final channel = _FakeAuthorizeChannel()..holdNext();
      final protocol = _protocol(setter, channel,
          timeout: const Duration(milliseconds: 10));
      await expectLater(
        _apply(protocol, barrier: _barrier(protocol)),
        throwsA(isA<BridgeActivationException>().having(
            (error) => error.code, 'code', BridgeActivationCode.timeout)),
      );
      expect(setter.writes.single, 'vo=null');
    });

    test('a late success reply does not activate the timed-out transaction',
        () async {
      final setter = _FakeStrictSetter();
      final lateReply = Completer<Object?>();
      final channel = _FakeAuthorizeChannel();
      final protocol = BridgeActivationProtocol(
        strictSetter: setter.call,
        invokeAuthorization: (request) {
          channel.requests.add(request);
          return lateReply.future;
        },
        authorizationTimeout: const Duration(milliseconds: 10),
      );
      await expectLater(
        _apply(protocol, barrier: _barrier(protocol)),
        throwsA(isA<BridgeActivationException>()),
      );
      final writesAfterTimeout = setter.writes.length;
      // The reply arrives after the timeout: no property write may follow.
      lateReply.complete(_okReply());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(setter.writes.length, writesAfterTimeout);
      expect(setter.writes.single, 'vo=null');
    });

    test('a late failure reply surfaces no unhandled async error', () async {
      final lateReply = Completer<Object?>();
      final protocol = BridgeActivationProtocol(
        strictSetter: _FakeStrictSetter().call,
        invokeAuthorization: (_) => lateReply.future,
        authorizationTimeout: const Duration(milliseconds: 10),
      );
      await expectLater(
        protocol.authorize(request: _request, stillCurrent: () => true),
        throwsA(isA<BridgeActivationException>()),
      );
      lateReply.completeError(StateError('late channel failure'));
      // Give the abandoned future a chance to (wrongly) escalate.
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });

    test('the pending gate refuses a second call and reopens after settling',
        () async {
      final first = Completer<Object?>();
      final second = Completer<Object?>();
      final channel = _FakeAuthorizeChannel();
      final protocol = BridgeActivationProtocol(
        strictSetter: (String key, String value) async {},
        invokeAuthorization: (request) {
          channel.requests.add(request);
          return channel.calls == 1 ? first.future : second.future;
        },
      );
      final authorize1 =
          protocol.authorize(request: _request, stillCurrent: () => true);
      // While the first call is outstanding, a second one is refused.
      await expectLater(
        protocol.authorize(request: _request, stillCurrent: () => true),
        throwsA(isA<BridgeActivationException>().having(
            (error) => error.code, 'code', BridgeActivationCode.channelError)),
      );
      first.complete(_okReply());
      await authorize1;
      final authorize2 =
          protocol.authorize(request: _request, stillCurrent: () => true);
      second.complete(_okReply());
      await authorize2;
      expect(channel.calls, 2);
    });

    test('a timeout reopens the gate', () async {
      final channel = _FakeAuthorizeChannel()..holdNext();
      final protocol = _protocol(
        _FakeStrictSetter(),
        channel,
        timeout: const Duration(milliseconds: 10),
      );
      await expectLater(
        protocol.authorize(request: _request, stillCurrent: () => true),
        throwsA(isA<BridgeActivationException>()),
      );
      // The gate must not stay permanently closed (C3).
      channel.replyNext(_okReply());
      await protocol.authorize(request: _request, stillCurrent: () => true);
      expect(channel.calls, 2);
    });
  });

  group('identity guards', () {
    test('a stale identity before authorize sends nothing', () async {
      final setter = _FakeStrictSetter();
      final channel = _FakeAuthorizeChannel()..replyNext(_okReply());
      final protocol = _protocol(setter, channel);
      await expectLater(
        _apply(protocol,
            barrier: _barrier(protocol, stillCurrent: () => false)),
        throwsA(isA<BridgeActivationException>()
            .having((error) => error.stale, 'stale', isTrue)
            .having((error) => error.widWriteStarted,
                'widWriteStarted', isFalse)),
      );
      expect(channel.calls, 0);
      expect(setter.writes.single, 'vo=null');
    });

    test('a stale identity detected after the reply discards before any write',
        () async {
      final setter = _FakeStrictSetter();
      final channel = _FakeAuthorizeChannel()..replyNext(_okReply());
      final protocol = _protocol(setter, channel);
      // The identity dies exactly when the platform reply lands (for example
      // a SurfaceDestroyed pre-lock update arrived first).
      await expectLater(
        _apply(
          protocol,
          barrier: _barrier(
            protocol,
            stillCurrent: () => channel.calls == 0,
          ),
        ),
        throwsA(isA<BridgeActivationException>()
            .having((error) => error.code, 'code',
                BridgeActivationCode.staleIdentity)
            .having((error) => error.widWriteStarted,
                'widWriteStarted', isFalse)),
      );
      expect(setter.writes.single, 'vo=null');
    });

    test('a stale identity after the size write is before-wid stale',
        () async {
      final setter = _FakeStrictSetter();
      final channel = _FakeAuthorizeChannel()..replyNext(_okReply());
      final protocol = _protocol(setter, channel);
      // The identity dies once the size write is ACKed, before wid starts.
      await expectLater(
        _apply(
          protocol,
          barrier: _barrier(protocol),
          stillCurrent: () =>
              !setter.writes.contains('android-surface-size=1920x1080'),
        ),
        throwsA(isA<BridgeActivationException>()
            .having((error) => error.widWriteStarted,
                'widWriteStarted', isFalse)
            .having((error) => error.phase, 'phase',
                BridgeActivationPhase.authorized)),
      );
      expect(setter.writes, <String>[
        'vo=null',
        'android-surface-size=1920x1080',
      ]);
    });

    test('a stale identity after the wid write keeps the write debt visible',
        () async {
      final setter = _FakeStrictSetter();
      final channel = _FakeAuthorizeChannel()..replyNext(_okReply());
      final protocol = _protocol(setter, channel);
      final widWritten = Completer<void>();
      var current = true;
      final applied = _apply(
        protocol,
        barrier: _barrier(protocol),
        stillCurrent: () {
          if (setter.writes.contains('wid=4242')) {
            // Fail only once the wid write has been ACKed.
            if (!widWritten.isCompleted) widWritten.complete();
            return false;
          }
          return current;
        },
      );
      await expectLater(
        applied,
        throwsA(isA<BridgeActivationException>()
            .having((error) => error.widWriteStarted,
                'widWriteStarted', isTrue)
            .having((error) => error.phase, 'phase',
                BridgeActivationPhase.mayHaveWrittenWid)),
      );
      expect(setter.writes, <String>[
        'vo=null',
        'android-surface-size=1920x1080',
        'wid=4242',
      ]);
      current = false;
    });

    test('a fresh identity completes every write and applies vid', () async {
      final setter = _FakeStrictSetter();
      final channel = _FakeAuthorizeChannel()..replyNext(_okReply());
      final protocol = _protocol(setter, channel);
      final transaction =
          await _apply(protocol, barrier: _barrier(protocol), writeVid: true);
      expect(transaction.phase, BridgeActivationPhase.applied);
      expect(setter.writes.last, 'vid=auto');
    });
  });

  group('dispatch epoch (B3)', () {
    test('counts only real channel dispatches', () async {
      final setter = _FakeStrictSetter();
      final channel = _FakeAuthorizeChannel();
      final protocol = _protocol(setter, channel);
      expect(protocol.dispatchEpoch, 0);
      // A stale pre-check discard never dispatches and never bumps.
      await expectLater(
        protocol.authorize(
            request: _request, stillCurrent: () => false),
        throwsA(isA<BridgeActivationException>()),
      );
      expect(protocol.dispatchEpoch, 0);
      expect(channel.calls, 0);

      channel.replyNext(_okReply());
      await protocol.authorize(request: _request, stillCurrent: () => true);
      expect(protocol.dispatchEpoch, 1);
      channel.replyNext(_okReply());
      await protocol.authorize(request: _request, stillCurrent: () => true);
      expect(protocol.dispatchEpoch, 2);
    });

    test('a gate refusal does not bump; a timeout does', () async {
      final channel = _FakeAuthorizeChannel()..holdNext();
      final protocol = _protocol(
        _FakeStrictSetter(),
        channel,
        timeout: const Duration(milliseconds: 10),
      );
      final first = protocol.authorize(request: _request, stillCurrent: () => true);
      await Future<void>.delayed(Duration.zero);
      expect(protocol.dispatchEpoch, 1);
      // The refused second call never dispatches.
      await expectLater(
        protocol.authorize(request: _request, stillCurrent: () => true),
        throwsA(isA<BridgeActivationException>().having(
            (error) => error.code, 'code', BridgeActivationCode.channelError)),
      );
      expect(protocol.dispatchEpoch, 1);
      await expectLater(first, throwsA(isA<BridgeActivationException>()));
      expect(protocol.dispatchEpoch, 1); // timeout keeps the single dispatch
      channel.replyNext(_okReply());
      await protocol.authorize(request: _request, stillCurrent: () => true);
      expect(protocol.dispatchEpoch, 2);
    });
  });

  group('held-ACK cancellation series (C4)', () {
    test('cancel while wid is submitted but not ACKed keeps the write debt',
        () async {
      final widAck = Completer<void>();
      final setter = _FakeStrictSetter(holds: {'wid=4242': widAck});
      final channel = _FakeAuthorizeChannel()..replyNext(_okReply());
      final protocol = _protocol(setter, channel);
      // The identity dies as soon as the wid write is SUBMITTED (the hold
      // means its ACK has not arrived yet).
      final applied = _apply(
        protocol,
        barrier: _barrier(protocol),
        stillCurrent: () => !setter.writes.contains('wid=4242'),
      );
      widAck.complete(); // the ACK lands after the cancellation decision
      await expectLater(
        applied,
        throwsA(isA<BridgeActivationException>()
            .having((error) => error.widWriteStarted,
                'widWriteStarted', isTrue)
            .having((error) => error.phase, 'phase',
                BridgeActivationPhase.mayHaveWrittenWid)),
      );
      expect(setter.writes, <String>[
        'vo=null',
        'android-surface-size=1920x1080',
        'wid=4242',
      ]);
    });

    test('cancel after vo is activated stops before vid', () async {
      final setter = _FakeStrictSetter();
      final channel = _FakeAuthorizeChannel()..replyNext(_okReply());
      final protocol = _protocol(setter, channel);
      await expectLater(
        _apply(
          protocol,
          barrier: _barrier(protocol),
          stillCurrent: () =>
              !setter.writes.contains('vo=gpu-next'),
        ),
        throwsA(isA<BridgeActivationException>()
            .having((error) => error.widWriteStarted,
                'widWriteStarted', isTrue)
            .having((error) => error.phase, 'phase',
                BridgeActivationPhase.mayHaveWrittenWid)),
      );
      expect(setter.writes, <String>[
        'vo=null',
        'android-surface-size=1920x1080',
        'wid=4242',
        'vo=gpu-next',
      ]);
    });

    test('a late ACK of the abandoned transaction never revives it',
        () async {
      final setter = _FakeStrictSetter();
      final channel = _FakeAuthorizeChannel()..replyNext(_failureReply('initFailed'));
      final protocol = _protocol(setter, channel);
      await expectLater(
        _apply(protocol, barrier: _barrier(protocol)),
        throwsA(isA<BridgeActivationException>()),
      );
      // The strict stop after the abandonment completes cleanly regardless
      // of the abandoned activation's earlier writes.
      final transaction = await protocol.apply(
        widValue: '0',
        voValue: 'null',
        vidValue: 'no',
        androidSurfaceSizeValue: '1920x1080',
        writeVid: true,
      );
      expect(transaction.phase, BridgeActivationPhase.applied);
      expect(setter.writes.last, 'vid=no');
      // No new authorization was sent for the stop.
      expect(channel.calls, 1);
    });
  });

  group('wid listener activation (real state machines, B2-1/B2-2)', () {
    WidListenerActivation activator({
      required PlatformOutputAvailability availability,
      required SurfaceOwnerLedger<AndroidSurfaceAccountId> ledger,
      required BridgeActivationProtocol protocol,
      required _FakeStrictSetter setter,
      Future<void> Function(AndroidSurfaceAccountId owner, int serial)?
          guardedApply,
      Future<bool> Function()? strictStop,
      void Function(AndroidSurfaceAccountId owner)? onCleared,
      void Function(
              AndroidSurfaceAccountId owner,
              int serial,
              BridgeActivationException error,
              StackTrace stack,
              {required bool boundIdentityClearable})?
          onFailure,
      void Function()? onNotExpected,
      bool Function(AndroidSurfaceAccountId owner, int serial)?
          isIdentityCurrent,
    }) {
      return WidListenerActivation(
        availability: availability,
        ledger: ledger,
        isIdentityCurrent: isIdentityCurrent ?? (_, __) => true,
        isIntentCurrent: (_, __) => true,
        mayPublishOutput: (_, __) => true,
        plainReapply: () async {
          fail('plain re-apply must not run on a bridge route');
        },
        guardedApply: guardedApply ??
            (owner, serial) async {
              await protocol.apply(
                widValue: '${owner.wid}',
                voValue: 'gpu-next',
                vidValue: 'auto',
                androidSurfaceSizeValue: '1920x1080',
                writeVid: true,
                authorizeActivation: () => protocol.authorize(
                  request: _request,
                  stillCurrent: () => true,
                ),
                activationStillCurrent: () => true,
              );
            },
        strictStop: strictStop ?? () async {
              fail('strict stop must not run');
            },
        clearSuspendedOwner: onCleared ?? (_) {
          fail('no suspended owner state to clear');
        },
        recordFailure: onFailure ??
            (owner, serial, error, stack, {required bool boundIdentityClearable}) {
              fail('no failure expected');
            },
        onNotExpectedOutput: onNotExpected ?? () {
          fail('output expected');
        },
        trace: (_) {},
      );
    }

    test('a successful guarded activation restores availability and '
        'completes the FRESH waiter (B2-1)', () async {
      final setter = _FakeStrictSetter();
      final channel = _FakeAuthorizeChannel()..replyNext(_okReply());
      final protocol = _protocol(setter, channel);
      final availability = PlatformOutputAvailability();
      final ledger = SurfaceOwnerLedger<AndroidSurfaceAccountId>()
        ..announceQueuedBind(_owner);
      // Normally bound start: the previous waiter completed and the output
      // is available.
      availability.publishCurrentAvailable();
      await availability.currentFuture;

      var sawSuspendedWaiter = false;
      final run = activator(
        availability: availability,
        ledger: ledger,
        protocol: protocol,
        setter: setter,
        guardedApply: (owner, serial) async {
          // Mid-transaction: the old waiter was invalidated and a fresh
          // pending one installed; the output is suspended.
          sawSuspendedWaiter = availability.currentOutputUnavailable &&
              !availability.currentWaiterCompleted;
          await protocol.apply(
            widValue: '${owner.wid}',
            voValue: 'gpu-next',
            vidValue: 'auto',
            androidSurfaceSizeValue: '1920x1080',
            writeVid: true,
            authorizeActivation: () => protocol.authorize(
              request: _request,
              stillCurrent: () => true,
            ),
            activationStillCurrent: () => true,
          );
        },
      );
      await run.run(
        plan: WidListenerActivationPlan.guardedActivation,
        owner: _owner,
        outputIntentSerial: 4,
      );
      expect(sawSuspendedWaiter, isTrue);
      // The fresh waiter completed and availability was restored — this is
      // the new waiter, not the pre-transaction completed one.
      expect(availability.currentOutputUnavailable, isFalse);
      expect(availability.currentWaiterCompleted, isTrue);
      await availability.currentFuture;
      expect(ledger.inFlightOwner, isNull);
      expect(
        isCurrentPlatformOutputImmediatelyAvailable(
          outputAvailable: !availability.currentOutputUnavailable,
          widBound: true,
          viewIdBound: true,
          hasInFlightOwner: ledger.inFlightOwner != null,
        ),
        isTrue,
      );
    });

    test('a bridge-route skip writes nothing and preserves a foreign '
        'in-flight debt (B2-2)', () async {
      final setter = _FakeStrictSetter();
      final channel = _FakeAuthorizeChannel();
      final protocol = _protocol(setter, channel);
      final availability = PlatformOutputAvailability()
        ..publishCurrentAvailable();
      const foreign = AndroidSurfaceAccountId(
        handle: 11,
        generation: 3,
        viewId: 8,
        surfaceGeneration: 1,
        wid: 4242,
      );
      final ledger = SurfaceOwnerLedger<AndroidSurfaceAccountId>()
        ..announceQueuedBind(_owner)
        ..announceQueuedBind(foreign)
        ..markInFlight(foreign);
      final run = activator(
        availability: availability,
        ledger: ledger,
        protocol: protocol,
        setter: setter,
      );
      await run.run(
        plan: WidListenerActivationPlan.skip,
        owner: _owner,
        outputIntentSerial: 4,
      );
      // Zero property writes, zero channel calls, zero state changes: the
      // foreign debt and the availability are untouched.
      expect(setter.writes, isEmpty);
      expect(channel.calls, 0);
      expect(ledger.inFlightOwner, foreign);
      expect(availability.currentOutputUnavailable, isFalse);
      expect(availability.currentWaiterCompleted, isTrue);
    });

    test('a stale activation whose strict stop FAILED keeps the owner debt '
        'for detach (B2-2/B4)', () async {
      final setter = _FakeStrictSetter();
      final channel = _FakeAuthorizeChannel()..replyNext(_okReply());
      final protocol = _protocol(setter, channel);
      final availability = PlatformOutputAvailability()
        ..publishCurrentAvailable();
      final ledger = SurfaceOwnerLedger<AndroidSurfaceAccountId>()
        ..announceQueuedBind(_owner);
      var cleared = false;
      final run = activator(
        availability: availability,
        ledger: ledger,
        protocol: protocol,
        setter: setter,
        // The identity dies after the wid write was ACKed.
        isIdentityCurrent: (_, __) => false,
        strictStop: () async => false,
        onCleared: (_) => cleared = true,
        onFailure: (owner, serial, error, stack,
            {required bool boundIdentityClearable}) {
          fail('stale discards publish no failure');
        },
      );
      await run.run(
        plan: WidListenerActivationPlan.guardedActivation,
        owner: _owner,
        outputIntentSerial: 4,
      );
      expect(cleared, isFalse);
      // The in-flight debt survives so the owner's detach must stop mpv
      // strictly before releasing the JNI reference.
      expect(ledger.inFlightOwner, _owner);
      expect(releaseRequiresStrictStop(
          isBoundOutput: true, isInFlightOutput: true), isTrue);
      expect(availability.currentOutputUnavailable, isTrue);
    });

    test('a stale activation whose strict stop SUCCEEDED clears the '
        'suspended owner state', () async {
      final setter = _FakeStrictSetter();
      final channel = _FakeAuthorizeChannel()..replyNext(_okReply());
      final protocol = _protocol(setter, channel);
      final availability = PlatformOutputAvailability()
        ..publishCurrentAvailable();
      final ledger = SurfaceOwnerLedger<AndroidSurfaceAccountId>()
        ..announceQueuedBind(_owner);
      var cleared = false;
      final run = activator(
        availability: availability,
        ledger: ledger,
        protocol: protocol,
        setter: setter,
        isIdentityCurrent: (_, __) => false,
        strictStop: () async => true,
        onCleared: (_) => cleared = true,
      );
      await run.run(
        plan: WidListenerActivationPlan.guardedActivation,
        owner: _owner,
        outputIntentSerial: 4,
      );
      expect(cleared, isTrue);
      expect(ledger.inFlightOwner, isNull);
    });
  });

  group('controller decision units (production code)', () {
    test('BridgeActivationIssue carries the full scope payload with '
        'kind=failed', () {
      final error = const BridgeActivationException(
        BridgeActivationCode.initFailed,
        message: 'init exploded',
      );
      final issue = BridgeActivationIssue(
        controller: Object(),
        owner: _owner,
        activationEpoch: 5,
        outputIntentSerial: 9,
        code: error.code,
        error: error,
        message: error.message,
      );
      expect(issue.kind, BridgeActivationIssueKind.failed);
      expect(issue.owner, _owner);
      expect(issue.activationEpoch, 5);
      expect(issue.outputIntentSerial, 9);
      expect(issue.code, BridgeActivationCode.initFailed);
      expect(issue.error, same(error));
    });

    test('bridgeActivationGateEnabled: only the surfacetexture carrier '
        'activates the barrier', () {
      // The HDR session injects a token for EVERY Android session, so the
      // token alone must not be enough.
      expect(
        bridgeActivationGateEnabled(
          usePlatformView: true,
          ownerToken: 'mk-owner-x',
          hwdec: 'surfacetexture',
        ),
        isTrue,
      );
      // A token-carrying mediacodec_embed (native DV) PlatformView route.
      expect(
        bridgeActivationGateEnabled(
          usePlatformView: true,
          ownerToken: 'mk-owner-x',
          hwdec: 'mediacodec',
        ),
        isFalse,
      );
      expect(
        bridgeActivationGateEnabled(
          usePlatformView: true,
          ownerToken: 'mk-owner-x',
          hwdec: 'mediacodec-copy',
        ),
        isFalse,
      );
      // Texture routes are not PlatformView at all.
      expect(
        bridgeActivationGateEnabled(
          usePlatformView: false,
          ownerToken: 'mk-owner-x',
          hwdec: 'surfacetexture',
        ),
        isFalse,
      );
      // Without a token nothing activates (Lab/default players).
      expect(
        bridgeActivationGateEnabled(
          usePlatformView: true,
          ownerToken: null,
          hwdec: 'surfacetexture',
        ),
        isFalse,
      );
      // The controller default hwdec never authorizes.
      expect(
        bridgeActivationGateEnabled(
          usePlatformView: true,
          ownerToken: 'mk-owner-x',
          hwdec: 'auto-safe',
        ),
        isFalse,
      );
    });

    test('mayPublishPlatformSurface: a newer ViewCreated without a Surface '
        'closes the gate for the older view', () {
      expect(
        mayPublishPlatformSurface(
          ownerViewCreationSerial: 4,
          latestViewCreationSerial: 4,
          authorizedFallbackSerial: false,
        ),
        isTrue,
      );
      expect(
        mayPublishPlatformSurface(
          ownerViewCreationSerial: 4,
          latestViewCreationSerial: 5,
          authorizedFallbackSerial: false,
        ),
        isFalse,
      );
      expect(
        mayPublishPlatformSurface(
          ownerViewCreationSerial: null,
          latestViewCreationSerial: 5,
          authorizedFallbackSerial: false,
        ),
        isFalse,
      );
      expect(
        mayPublishPlatformSurface(
          ownerViewCreationSerial: 4,
          latestViewCreationSerial: 5,
          authorizedFallbackSerial: true,
        ),
        isTrue,
      );
    });

    test('decideCompatibleBoundFallback: C1 failure fixtures never promote',
        () {
      final bound = 'bound';
      final stoppedOwner = 'stopped';
      String? decide({
        required bool hasInFlightOwner,
        required Set<String> boundOwners,
        Set<String> compatible = const {'bound', 'stopped'},
        Set<String> queued = const {},
      }) =>
          decideCompatibleBoundFallback<String>(
            hasInFlightOwner: hasInFlightOwner,
            liveOwnersInArrivalOrder: [stoppedOwner, bound],
            isBoundSurfaceOwner: boundOwners.contains,
            isCompatibleWithLatestView: compatible.contains,
            hasOtherQueuedCandidate: (owner) =>
                queued.any((queued) => queued != owner),
          );
      // Healthy state: the still-confirmed bound owner is promoted.
      expect(decide(hasInFlightOwner: false, boundOwners: {'bound'}), bound);
      // Stop-then-authorize failure fixture: the retained in-flight debt
      // blocks promotion outright.
      expect(decide(hasInFlightOwner: true, boundOwners: {'bound'}), isNull);
      // Identity-cleared fixture (same-Surface failure or stale discard):
      // the stopped owner is not a confirmed bound owner anymore.
      expect(decide(hasInFlightOwner: false, boundOwners: {}), isNull);
      // A competing queued candidate defers the promotion.
      expect(
        decide(hasInFlightOwner: false, boundOwners: {'bound'},
            queued: {'newer'}),
        isNull,
      );
      // An incompatible view never promotes.
      expect(
        decide(hasInFlightOwner: false, boundOwners: {'bound'},
            compatible: {'stopped'}),
        isNull,
      );
    });

    test('mayRepublishAlreadyBoundOutput: the repeated already-bound event '
        'cannot bypass a failed activation', () {
      expect(
        mayRepublishAlreadyBoundOutput(
          confirmedBound: true,
          hasInFlightOwner: false,
          intentCurrent: true,
          mayPublishLatestView: true,
        ),
        isTrue,
      );
      // The stop-then-authorize failure retains the in-flight debt exactly
      // so this stays closed.
      expect(
        mayRepublishAlreadyBoundOutput(
          confirmedBound: true,
          hasInFlightOwner: true,
          intentCurrent: true,
          mayPublishLatestView: true,
        ),
        isFalse,
      );
      // The cleared (stopped) identity is not a confirmed bound output.
      expect(
        mayRepublishAlreadyBoundOutput(
          confirmedBound: false,
          hasInFlightOwner: false,
          intentCurrent: true,
          mayPublishLatestView: true,
        ),
        isFalse,
      );
      expect(
        mayRepublishAlreadyBoundOutput(
          confirmedBound: true,
          hasInFlightOwner: false,
          intentCurrent: false,
          mayPublishLatestView: true,
        ),
        isFalse,
      );
      // ViewCreated arrived for a newer view without a new Surface.
      expect(
        mayRepublishAlreadyBoundOutput(
          confirmedBound: true,
          hasInFlightOwner: false,
          intentCurrent: true,
          mayPublishLatestView: false,
        ),
        isFalse,
      );
    });

    test('isCurrentPlatformOutputImmediatelyAvailable: a hanging '
        'authorization blocks the waiter (issue 2)', () {
      expect(
        isCurrentPlatformOutputImmediatelyAvailable(
          outputAvailable: true,
          widBound: true,
          viewIdBound: true,
          hasInFlightOwner: false,
        ),
        isTrue,
      );
      // The listener activation invalidated the output and took the debt.
      expect(
        isCurrentPlatformOutputImmediatelyAvailable(
          outputAvailable: false,
          widBound: true,
          viewIdBound: true,
          hasInFlightOwner: true,
        ),
        isFalse,
      );
      expect(
        isCurrentPlatformOutputImmediatelyAvailable(
          outputAvailable: true,
          widBound: true,
          viewIdBound: true,
          hasInFlightOwner: true,
        ),
        isFalse,
      );
    });

    test('releaseRequiresStrictStop: a failed stop keeps the debt that '
        'forces detach to stop first', () {
      // Listener abandonment whose strict stop failed: identity kept +
      // in-flight kept -> detach must stop before releasing the JNI ref.
      expect(
        releaseRequiresStrictStop(isBoundOutput: true, isInFlightOutput: true),
        isTrue,
      );
      expect(
        releaseRequiresStrictStop(isBoundOutput: false, isInFlightOutput: true),
        isTrue,
      );
      // Clean state after a successful stop: release directly.
      expect(
        releaseRequiresStrictStop(isBoundOutput: false, isInFlightOutput: false),
        isFalse,
      );
    });

    test('planWidListenerActivation: only a guarded owner activates the '
        'barrier; bridge routes never fall back to an unauthorized write',
        () {
      expect(
        planWidListenerActivation(
          bridgeActivationEnabled: true,
          hasCompleteBoundIdentity: true,
          boundWid: 4242,
          boundOwnerIsCurrentIntent: true,
          hasForeignInFlightOwner: false,
        ),
        WidListenerActivationPlan.guardedActivation,
      );
      // Token-carrying mediacodec_embed route: gate disabled -> plain.
      expect(
        planWidListenerActivation(
          bridgeActivationEnabled: false,
          hasCompleteBoundIdentity: true,
          boundWid: 4242,
          boundOwnerIsCurrentIntent: true,
          hasForeignInFlightOwner: false,
        ),
        WidListenerActivationPlan.plainReapply,
      );
      // No complete identity / zero wid: plain (a stop, never a non-zero
      // wid write).
      expect(
        planWidListenerActivation(
          bridgeActivationEnabled: true,
          hasCompleteBoundIdentity: false,
          boundWid: 0,
          boundOwnerIsCurrentIntent: false,
          hasForeignInFlightOwner: false,
        ),
        WidListenerActivationPlan.plainReapply,
      );
      // The bound owner is not the current intent (a destroy/newer intent is
      // in flight): a bridge route is SKIPPED — never an unauthorized
      // non-zero wid write.
      expect(
        planWidListenerActivation(
          bridgeActivationEnabled: true,
          hasCompleteBoundIdentity: true,
          boundWid: 4242,
          boundOwnerIsCurrentIntent: false,
          hasForeignInFlightOwner: false,
        ),
        WidListenerActivationPlan.skip,
      );
      // Another owner's unfinished transaction holds the in-flight slot:
      // skipped without overwriting or bypassing its debt.
      expect(
        planWidListenerActivation(
          bridgeActivationEnabled: true,
          hasCompleteBoundIdentity: true,
          boundWid: 4242,
          boundOwnerIsCurrentIntent: true,
          hasForeignInFlightOwner: true,
        ),
        WidListenerActivationPlan.skip,
      );
    });

    test('abandonedActivationCleanupAfterStrictStop', () {
      expect(
        abandonedActivationCleanupAfterStrictStop(strictStopSucceeded: true)
            .mayDropOwnerState,
        isTrue,
      );
      // A failed stop keeps the owner state: the detach debt survives.
      expect(
        abandonedActivationCleanupAfterStrictStop(strictStopSucceeded: false)
            .mayDropOwnerState,
        isFalse,
      );
    });

    test('isBridgeActivationIssueCurrent: full scope (B3)', () {
      final controller = Object();
      BridgeActivationIssue issue({int epoch = 1, int intent = 4}) =>
          BridgeActivationIssue(
            controller: controller,
            owner: _owner,
            activationEpoch: epoch,
            outputIntentSerial: intent,
            code: BridgeActivationCode.initFailed,
          );
      bool current({
        Object? issueController,
        bool active = true,
        int epoch = 1,
        AndroidSurfaceAccountId? expected = _owner,
        int intent = 4,
        bool latestView = true,
        BridgeActivationIssue? issueOverride,
      }) =>
          isBridgeActivationIssueCurrent(
            issue: issueOverride ?? issue(),
            controller: issueController ?? controller,
            controllerActive: active,
            activationEpoch: epoch,
            expectedOwner: expected,
            outputIntentSerial: intent,
            ownerAllowedByLatestView: latestView,
          );
      expect(current(), isTrue);
      // Controller replaced / disposed / terminated.
      expect(current(issueController: Object()), isFalse);
      expect(current(active: false), isFalse);
      // A newer real dispatch supersedes the issue.
      expect(current(epoch: 2), isFalse);
      // The owner is no longer the expected output identity (replaced or
      // destroyed).
      expect(
        isBridgeActivationIssueCurrent(
          issue: issue(),
          controller: controller,
          controllerActive: true,
          activationEpoch: 1,
          expectedOwner: null,
          outputIntentSerial: 4,
          ownerAllowedByLatestView: true,
        ),
        isFalse,
      );
      expect(
        current(
          expected: const AndroidSurfaceAccountId(
            handle: 11,
            generation: 3,
            viewId: 7,
            surfaceGeneration: 9,
            wid: 9999,
          ),
        ),
        isFalse,
      );
      // The intent serial moved on.
      expect(current(intent: 5), isFalse);
      // A newer ViewCreated arrived without any new dispatch: the epoch and
      // intent are unchanged, but the latest-view gate closed.
      expect(current(latestView: false), isFalse);
      // An issue naming another controller instance is never current.
      expect(current(issueOverride: issue(epoch: 1)), isTrue);
    });

    test('BridgeActivationScopeAnchor equality is field-wise on the same '
        'controller', () {
      final controller = Object();
      final a = BridgeActivationScopeAnchor(
        controller: controller,
        owner: _owner,
        activationEpoch: 3,
        outputIntentSerial: 7,
        latestViewCreationSerial: 1,
      );
      expect(
        BridgeActivationScopeAnchor(
          controller: controller,
          owner: _owner,
          activationEpoch: 3,
          outputIntentSerial: 7,
          latestViewCreationSerial: 1,
        ),
        a,
      );
      expect(
        BridgeActivationScopeAnchor(
          controller: Object(),
          owner: _owner,
          activationEpoch: 3,
          outputIntentSerial: 7,
        ),
        isNot(a),
      );
      expect(
        BridgeActivationScopeAnchor(
          controller: controller,
          owner: _owner,
          activationEpoch: 4,
          outputIntentSerial: 7,
        ),
        isNot(a),
      );
      expect(
        BridgeActivationScopeAnchor(
          controller: controller,
          owner: null,
          activationEpoch: 3,
          outputIntentSerial: 7,
        ),
        isNot(a),
      );
      expect(
        BridgeActivationScopeAnchor(
          controller: controller,
          owner: _owner,
          activationEpoch: 3,
          outputIntentSerial: 8,
        ),
        isNot(a),
      );
      // A newer ViewCreated with no new Surface: owner/intent/epoch all
      // unchanged — only the latest-view serial distinguishes the scopes.
      expect(
        BridgeActivationScopeAnchor(
          controller: controller,
          owner: _owner,
          activationEpoch: 3,
          outputIntentSerial: 7,
          latestViewCreationSerial: 2,
        ),
        isNot(a),
      );
      expect(
        BridgeActivationScopeAnchor(
          controller: controller,
          owner: _owner,
          activationEpoch: 3,
          outputIntentSerial: 7,
          latestViewCreationSerial: 1,
        ),
        a,
      );
      const nullAnchor = BridgeActivationScopeAnchor(
        controller: null,
        owner: null,
        activationEpoch: 0,
        outputIntentSerial: 0,
      );
      expect(
        const BridgeActivationScopeAnchor(
          controller: null,
          owner: null,
          activationEpoch: 0,
          outputIntentSerial: 0,
        ),
        nullAnchor,
      );
    });
  });
}
