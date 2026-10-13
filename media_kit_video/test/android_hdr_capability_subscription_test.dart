import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';
import 'package:media_kit_video/src/hdr/hdr_output_event.dart';
import 'package:media_kit_video/src/hdr/hdr_video_session.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/real.dart';

import 'hdr_video_session_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.alexmercerind/media_kit_video');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const capabilities = HdrCapabilities(
    sdkInt: 29,
    displayHdrTypes: {2},
    hevcDecoders: [],
    dolbyVisionDecoders: [],
    p5PipelineAvailable: true,
    dataSpaceBridgeLoaded: true,
    dataSpaceExt: null,
  );

  final sessions = <HdrVideoSession>[];
  final manualListeners = <void Function(Map<Object?, Object?>)>[];
  final nativeReplies = <Completer<Object?>>[];
  final calls = <bool>[];
  late StreamController<bool> nativeCalls;
  var nativeEnabled = false;
  FutureOr<Object?> Function(bool enabled)? reply;

  setUp(() {
    sessions.clear();
    manualListeners.clear();
    nativeReplies.clear();
    calls.clear();
    nativeCalls = StreamController<bool>.broadcast(sync: true);
    nativeEnabled = false;
    reply = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'HdrCapabilities.Changed');
      final enabled = (call.arguments as Map)['enable'] as bool;
      calls.add(enabled);
      nativeCalls.add(enabled);
      final response = reply?.call(enabled);
      // Model the Java plugin's shared switch. A held response delays the
      // acknowledgement, not the synchronous native registration operation.
      nativeEnabled = enabled;
      return await response;
    });
  });

  tearDown(() async {
    reply = null;
    for (final response in nativeReplies) {
      if (!response.isCompleted) response.complete(null);
    }
    for (final listener in manualListeners) {
      AndroidVideoController.unregisterHdrCapabilitiesChangedListener(listener);
    }
    for (final session in sessions) {
      await session.dispose();
    }
    await AndroidVideoController.setHdrCapabilitiesChangedEnabled(false);
    expect(nativeEnabled, isFalse);
    await nativeCalls.close();
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<HdrVideoSession> createSession({void Function()? onQuery}) async {
    final enabled = nativeCalls.stream.first;
    final session = HdrVideoSession.forTesting(
      isAndroid: true,
      backend: fixture.FakeBackend(),
      capabilitiesProvider: () async {
        onQuery?.call();
        return capabilities;
      },
    );
    sessions.add(session);
    expect(await enabled, isTrue);
    return session;
  }

  Future<void> disposeSession(
    HdrVideoSession session, {
    required bool keepsSubscription,
  }) async {
    final enabled = nativeCalls.stream.first;
    await session.dispose();
    expect(await enabled, keepsSubscription);
  }

  Future<void> sendDisplayChange() async {
    // A disabled native listener sends no event. Tests check the switch
    // before awaiting a Session event, so a lost subscription fails directly.
    if (!nativeEnabled) return;
    final response = await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(
        const MethodCall('HdrCapabilities.Changed', <String, Object?>{}),
      ),
      null,
    );
    expect(response, isNotNull);
    expect(channel.codec.decodeEnvelope(response!), isNull);
  }

  test('disposing one Session preserves the surviving capability refresh',
      () async {
    var firstQueries = 0;
    var secondQueries = 0;
    final first = await createSession(onQuery: () => firstQueries++);
    final second = await createSession(onQuery: () => secondQueries++);

    await disposeSession(first, keepsSubscription: true);
    expect(nativeEnabled, isTrue);
    final changed = second.events.firstWhere(
      (event) => event is HdrCapabilityChangedEvent,
    );
    await sendDisplayChange();
    await changed;
    expect(firstQueries, 0);
    expect(secondQueries, 1);

    final count = calls.length;
    await first.dispose();
    expect(calls, hasLength(count));
    expect(nativeEnabled, isTrue);

    await disposeSession(second, keepsSubscription: false);
    expect(calls, [true, true, true, false]);
    expect(nativeEnabled, isFalse);
  });

  test('listener registration and repeated enables do not count extra owners',
      () async {
    final survivor = await createSession();
    void listener(Map<Object?, Object?> snapshot) {}
    manualListeners.add(listener);
    AndroidVideoController.registerHdrCapabilitiesChangedListener(listener);
    AndroidVideoController.registerHdrCapabilitiesChangedListener(listener);
    await AndroidVideoController.setHdrCapabilitiesChangedEnabled(true);
    await AndroidVideoController.setHdrCapabilitiesChangedEnabled(true);

    expect(
      AndroidVideoController.unregisterHdrCapabilitiesChangedListener(listener),
      isTrue,
    );
    expect(
      AndroidVideoController.unregisterHdrCapabilitiesChangedListener(listener),
      isFalse,
    );
    await AndroidVideoController.setHdrCapabilitiesChangedEnabled(false);
    expect(nativeEnabled, isTrue);
    await disposeSession(survivor, keepsSubscription: false);
    expect(calls, [true, true, true, true, false]);
  });

  test('a late disable cannot unsubscribe a replacement Session', () async {
    final previous = await createSession();
    await disposeSession(previous, keepsSubscription: false);
    final replacement = await createSession();
    final releaseLateCall = Completer<void>();
    final lateDisable = releaseLateCall.future.then(
      (_) => AndroidVideoController.setHdrCapabilitiesChangedEnabled(false),
    );

    releaseLateCall.complete();
    await lateDisable;
    expect(nativeEnabled, isTrue);
    await disposeSession(replacement, keepsSubscription: false);
    expect(calls, [true, false, true, true, false]);
  });

  test('a delayed native acknowledgement does not retain a disposed owner',
      () async {
    final held = Completer<Object?>();
    nativeReplies.add(held);
    var holdNext = true;
    reply = (_) {
      if (holdNext) {
        holdNext = false;
        return held.future;
      }
      return null;
    };
    final first = await createSession();
    final second = await createSession();
    await disposeSession(first, keepsSubscription: true);
    held.complete(null);
    await held.future;

    await disposeSession(second, keepsSubscription: false);
    expect(calls, [true, true, true, false]);
    expect(nativeEnabled, isFalse);
  });

  test('native failures preserve current ownership and permit a retry',
      () async {
    final session = await createSession();
    reply = (_) => throw PlatformException(code: 'subscription-failed');
    await expectLater(
      AndroidVideoController.setHdrCapabilitiesChangedEnabled(false),
      throwsA(isA<PlatformException>().having(
        (error) => error.code,
        'code',
        'subscription-failed',
      )),
    );
    reply = null;
    await AndroidVideoController.setHdrCapabilitiesChangedEnabled(false);
    expect(nativeEnabled, isTrue);

    reply = (_) => throw PlatformException(code: 'subscription-failed');
    await disposeSession(session, keepsSubscription: false);
    expect(nativeEnabled, isTrue);

    await expectLater(
      AndroidVideoController.setHdrCapabilitiesChangedEnabled(false),
      throwsA(isA<PlatformException>()),
    );
    reply = null;
    await AndroidVideoController.setHdrCapabilitiesChangedEnabled(false);
    expect(calls, [true, true, true, false, false, false]);
    expect(nativeEnabled, isFalse);
  });
}
