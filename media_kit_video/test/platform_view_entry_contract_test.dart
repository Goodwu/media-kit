import 'dart:io';

void _require(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

String _read(String path) => File(path).readAsStringSync();

class _LifecycleModel {
  String? bound;
  String? inFlight;
  final pending = <String>{};
  final nativeReferences = <String>{};
  final tombstones = <String>{};
  final acknowledged = <String>{};
  bool normalDisposeSucceeded = false;
  bool terminalCallbackPending = true;

  void create(String owner) {
    nativeReferences.add(owner);
  }

  void bind(String owner, {required bool stopSucceeds, required bool binds}) {
    pending.add(owner);
    if ((bound != null || inFlight != null) && !stopSucceeds) {
      throw StateError('producer stop failed');
    }
    if (bound != null) {
      release(bound!, ackReachedJava: true, ackReplyReachedDart: true);
    }
    if (inFlight != null) {
      release(inFlight!, ackReachedJava: true, ackReplyReachedDart: true);
    }
    bound = null;
    inFlight = owner;
    if (!binds) throw StateError('bind failed');
    bound = owner;
    inFlight = null;
    pending.remove(owner);
  }

  void destroy(
    String owner, {
    required bool stopSucceeds,
    required bool ackReachedJava,
    required bool ackReplyReachedDart,
  }) {
    pending.add(owner);
    if ((bound == owner || inFlight == owner) && !stopSucceeds) return;
    if (bound == owner) bound = null;
    if (inFlight == owner) inFlight = null;
    release(
      owner,
      ackReachedJava: ackReachedJava,
      ackReplyReachedDart: ackReplyReachedDart,
    );
  }

  void release(
    String owner, {
    required bool ackReachedJava,
    required bool ackReplyReachedDart,
  }) {
    if (nativeReferences.remove(owner)) tombstones.add(owner);
    if (ackReachedJava && tombstones.contains(owner)) acknowledged.add(owner);
    if (ackReplyReachedDart && acknowledged.contains(owner)) {
      pending.remove(owner);
    }
  }

  void normalDispose() {
    normalDisposeSucceeded = true;
  }

  String disposalPath({required bool playerTerminated}) =>
      playerTerminated ? 'terminal' : 'normal';

  void terminate({
    required bool callReachedJava,
    required bool replyReachedDart,
  }) {
    if (!callReachedJava) return;
    nativeReferences.clear();
    tombstones.clear();
    acknowledged.clear();
    if (replyReachedDart) {
      pending.clear();
      bound = null;
      inFlight = null;
      terminalCallbackPending = false;
    }
  }
}

void _testLifecycleModel() {
  final model = _LifecycleModel()..create('A');
  model.bind('A', stopSucceeds: true, binds: true);
  model.create('B');
  try {
    model.bind('B', stopSucceeds: false, binds: true);
    throw StateError('a failed A stop must reject B promotion');
  } on StateError catch (error) {
    _require(error.message == 'producer stop failed', 'unexpected model error');
  }
  _require(
    model.bound == 'A' && model.pending.contains('B'),
    'B must remain pending while A remains the confirmed producer owner',
  );
  model.destroy(
    'A',
    stopSucceeds: false,
    ackReachedJava: false,
    ackReplyReachedDart: false,
  );
  _require(
    model.nativeReferences.contains('A') && model.pending.contains('A'),
    'a failed producer stop must retain A without a false release ACK',
  );

  try {
    model.bind('B', stopSucceeds: true, binds: false);
    throw StateError('a failed B bind must remain visible as in-flight');
  } on StateError catch (error) {
    _require(error.message == 'bind failed', 'unexpected model error');
  }
  _require(
    model.bound == null &&
        model.inFlight == 'B' &&
        model.pending.contains('B') &&
        !model.nativeReferences.contains('A'),
    'after A stops, a partial B bind must retain B until stop or termination',
  );
  model.destroy(
    'B',
    stopSucceeds: true,
    ackReachedJava: true,
    ackReplyReachedDart: false,
  );
  _require(
    model.tombstones.contains('B') &&
        model.acknowledged.contains('B') &&
        model.pending.contains('B'),
    'a lost ACK reply must retain both Java receipt and Dart retry state',
  );
  model.release(
    'B',
    ackReachedJava: true,
    ackReplyReachedDart: true,
  );
  _require(
    model.tombstones.contains('B') && model.pending.isEmpty,
    'an idempotent ACK retry must keep the tombstone until player termination',
  );

  model.create('D');
  model.pending.add('D');
  model.release(
    'D',
    ackReachedJava: false,
    ackReplyReachedDart: false,
  );
  _require(
    model.tombstones.contains('D') && model.pending.contains('D'),
    'a lost ReleaseSurface reply must retain the Dart owner for an idempotent retry',
  );
  model.release(
    'D',
    ackReachedJava: true,
    ackReplyReachedDart: true,
  );
  _require(
    !model.pending.contains('D'),
    'a ReleaseSurface timeout retry must finish the explicit owner ACK',
  );

  model.create('C');
  model.pending.add('C');
  model.normalDispose();
  _require(
    model.normalDisposeSucceeded &&
        model.disposalPath(playerTerminated: true) == 'terminal',
    'terminal cleanup must take priority over a successful normal dispose',
  );
  model.terminate(callReachedJava: false, replyReachedDart: false);
  _require(
    model.nativeReferences.contains('C') && model.tombstones.contains('B'),
    'engine detach or a terminal channel timeout before delivery must retain owners',
  );
  model.terminate(callReachedJava: true, replyReachedDart: false);
  _require(
    model.pending.contains('C') && model.terminalCallbackPending,
    'a lost terminal reply must retain Dart owner state and the retry callback',
  );
  model.terminate(callReachedJava: true, replyReachedDart: true);
  _require(
    model.nativeReferences.isEmpty &&
        model.pending.isEmpty &&
        !model.terminalCallbackPending,
    'an idempotent terminal retry must reclaim owners missed by normal callbacks',
  );
}

void main() {
  _testLifecycleModel();
  final shared = _read('lib/src/video/platform_view_video.dart');
  final ohos = _read('lib/src/video/platform_view_video_ohos.dart');

  _require(
    shared.contains('PlatformViewsService.initExpensiveAndroidView') &&
        shared.contains('PlatformViewsService.initHybridAndroidView') &&
        shared.contains('AndroidViewSurface'),
    'the shared entry must remain analyzable with standard Flutter platform-view APIs',
  );
  _require(
    !shared.contains('OhosViewController') &&
        !shared.contains('OhosViewSurface') &&
        !shared.contains('initSurfaceOhosView') &&
        !shared.contains('initExpensiveOhosView'),
    'OHOS-only controller and factories must not leak into the shared entry',
  );
  _require(
    ohos.contains('OhosViewController') &&
        ohos.contains('OhosViewSurface') &&
        ohos.contains('initSurfaceOhosView') &&
        ohos.contains('initExpensiveOhosView'),
    'the isolated OHOS entry must retain the OHOS platform-view implementation',
  );
  _require(
    shared.contains('final bool mpvWindow;') &&
        ohos.contains('final bool mpvWindow;'),
    'both platform entries must keep the shared constructor contract',
  );
  final androidController =
      _read('lib/src/video_controller/android_video_controller/real.dart');
  final nativePlayer =
      _read('../media_kit/lib/src/player/native/player/real.dart');
  _require(
    androidController
            .contains('Future<void> get waitUntilInitialOutputBound') &&
        androidController.contains('_bindPlatformViewSurface') &&
        androidController
            .contains('_initialPlatformViewOutputBound.complete()'),
    'Android PlatformView must bind its first Surface before releasing media open',
  );
  _require(
    androidController.contains('seekAfterSurfaceBind') &&
        androidController.contains('player.state.playlist.medias.isNotEmpty') &&
        androidController.contains('Future<void> _applyVideoSizeLocked()') &&
        androidController
            .split('Future<void> _applyVideoSizeLocked()')[1]
            .split('static const Duration _surfaceReleaseTimeout')[0]
            .contains("_setOutputProperty('android-surface-size'") &&
        !androidController
            .split('Future<void> _applyVideoSizeLocked()')[1]
            .split('static const Duration _surfaceReleaseTimeout')[0]
            .contains("await setProperty('android-surface-size'") &&
        !androidController
            .split('Future<void> _applyVideoSizeLocked()')[1]
            .split('static const Duration _surfaceReleaseTimeout')[0]
            .contains('_applyWidLocked('),
    'a size-only reapply or media-less initial bind must not reset the decoder',
  );
  _require(
    androidController.contains('Future<void>? _disposeFuture;') &&
        androidController.contains('_disposeFuture ??= _disposeOnce()') &&
        androidController.contains('platform.isReleaseCallbacksActive') &&
        androidController.contains('platform.setPropertyStrictForRelease') &&
        androidController.contains('platform.setPropertyStrict(') &&
        androidController.contains("'generation': owner.generation") &&
        androidController.contains("'viewId': owner.viewId") &&
        androidController.contains('_ledger.finishRelease'),
    'Android disposal must share one barrier and release the exact Surface owner',
  );
  final detach =
      androidController.indexOf('Future<void> _detachPlatformSurface(');
  final stopProducer = androidController.indexOf(
      "await _applyWidLocked(widValueOverride: '0');", detach);
  final releaseSurface = androidController.indexOf(
      'await _releaseSurfaceOwnerLocked(owner);', stopProducer);
  _require(
    detach >= 0 && stopProducer > detach && releaseSurface > stopProducer,
    'the current producer must stop before its Java Surface reference is released',
  );
  final bind =
      androidController.indexOf('Future<void> _bindPlatformViewSurface({');
  final boundOwner =
      androidController.indexOf('final bound = _boundSurfaceOwner(', bind);
  final stopPrevious = androidController.indexOf(
      "await _applyWidLocked(widValueOverride: '0');", bind);
  final retainIncoming =
      androidController.indexOf('_ledger.markInFlight(incoming);', bind);
  final promoteIncoming =
      androidController.indexOf('_platformViewId = incoming.viewId;', bind);
  _require(
    bind >= 0 &&
        boundOwner > bind &&
        stopPrevious > boundOwner &&
        retainIncoming > stopPrevious &&
        promoteIncoming > retainIncoming,
    'binding B must retain A until strict stop succeeds and retain B while binding is in flight',
  );
  final dispose = androidController.indexOf('Future<void> _disposeOnce()');
  final retryDispose =
      androidController.indexOf('_disposeFuture = null;', dispose);
  final unregisterController =
      androidController.indexOf('_controllers.remove(handle);', dispose);
  _require(
    dispose >= 0 &&
        retryDispose > dispose &&
        unregisterController > retryDispose &&
        androidController
            .contains("status != 'released' && status != 'alreadyReleased'"),
    'failed stop or release must retain retry state and reject ambiguous acknowledgements',
  );
  final terminate = nativePlayer.indexOf('mpv.mpv_terminate_destroy(ctx);');
  final terminalCallbacks =
      nativePlayer.indexOf('await retryPostTerminationCallbacks();', terminate);
  final terminalDispose = androidController
      .indexOf('Future<void> _disposeAfterPlayerTermination()');
  final terminalRelease = androidController.indexOf(
      "'PlatformVideoView.PlayerTerminated'", terminalDispose);
  _require(
    nativePlayer
            .contains('await Future.delayed(const Duration(seconds: 5));') &&
        terminate >= 0 &&
        terminalCallbacks > terminate &&
        terminalDispose >= 0 &&
        terminalRelease > terminalDispose &&
        androidController.contains('_maxOrphanReleaseAttempts = 3') &&
        androidController.contains('_scheduleOrphanSurfaceRetry(owner)') &&
        nativePlayer.contains('Future<void> setPropertyStrict(') &&
        nativePlayer.contains('Future<void> setPropertyStrictForRelease(') &&
        nativePlayer.contains('_throwIfMpvError(immediate,') &&
        nativePlayer.contains('_throwIfMpvError(reply,') &&
        nativePlayer.contains('Future<void>? _disposeFuture;') &&
        nativePlayer.contains('if (existing != null) return existing;') &&
        nativePlayer.contains('retryPostTerminationCallbacks()') &&
        nativePlayer.contains('_postTerminationLock.synchronized') &&
        androidController.contains('if (platform.isTerminated)') &&
        androidController
            .contains('await platform.retryPostTerminationCallbacks();') &&
        androidController.contains('.timeout(_surfaceReleaseTimeout)') &&
        androidController
            .contains('.timeout(_surfaceReleaseOwnerAckTimeout)') &&
        androidController.contains('.timeout(_playerTerminatedTimeout)') &&
        androidController.contains('void ensurePlayerActive()') &&
        androidController.contains('nativePlayer.isTerminated') &&
        androidController.contains(
            'Android video controller disposal is incomplete; retry disposal'),
    'failed release callbacks need a post-termination fallback and bounded orphan retries',
  );
  final create = androidController
      .indexOf('static Future<PlatformVideoController> create(');
  final sharedCreation = androidController.indexOf(
      'final pendingCreation = _controllerCreations[handle];', create);
  final initializeProperties =
      androidController.indexOf('await controller.setProperties({', create);
  final publishController =
      androidController.indexOf('_controllers[handle] = controller;', create);
  _require(
    sharedCreation > create &&
        initializeProperties > sharedCreation &&
        publishController > initializeProperties &&
        androidController.contains('_failedControllerDisposals[handle]') &&
        androidController.contains('controller._videoOutputCreated = true;'),
    'same-handle creation must share initialization and publish only after full setup',
  );

  final platformView = _read(
      'android/src/main/java/com/alexmercerind/media_kit_video/platformview/PlatformVideoView.java');
  final platformViewFactory = _read(
      'android/src/main/java/com/alexmercerind/media_kit_video/platformview/PlatformVideoViewFactory.java');
  final globalReferences = _read(
      'android/src/main/java/com/alexmercerind/media_kit_video/GlobalObjectRefManager.java');
  _require(
    platformView.contains('new HashMap<>(surfaceReferences).entrySet()') &&
        platformView.contains(
            'onSurfaceEvent.accept(new SurfaceEvent(reference.getValue(), reference.getKey(), true))') &&
        platformViewFactory.contains(
            'ConcurrentHashMap<SurfaceOwner, PlatformVideoView> surfaceOwners') &&
        platformView.contains('return "identityMismatch";') &&
        platformViewFactory.contains('return "ownerMissing";') &&
        platformViewFactory.contains('releaseSurfaceOwner(') &&
        platformView.contains('acknowledgeSurfaceRelease(') &&
        platformView.contains('acknowledgedSurfaceReferences.put(') &&
        !platformView
            .contains('releasedSurfaceReferences.remove(generation)') &&
        androidController
            .contains("'surfaceGeneration': owner.surfaceGeneration") &&
        androidController.contains("'wid': owner.wid.toString()") &&
        !platformViewFactory.contains('if (views.get(handle) != view) return;'),
    'view disposal and replaced-view destroys must retain an acknowledgement path',
  );
  _require(
    platformViewFactory
            .contains(
                'private final ConcurrentHashMap<SurfaceOwner, PlatformVideoView> surfaceOwners') &&
        platformViewFactory.contains('detachedFactories.add(this)') &&
        platformViewFactory.contains('not lifecycle completion') &&
        platformViewFactory.contains(
            'Retaining Surface owner without producer-termination proof') &&
        platformViewFactory
            .contains('view.releaseAllSurfacesAfterProducerTermination()') &&
        !platformViewFactory.contains(
            'private static final ConcurrentHashMap<SurfaceOwner, PlatformVideoView> surfaceOwners'),
    'engine detach must isolate and retain unproven owners until a terminal barrier exists',
  );
  _require(
    globalReferences.contains('HashSet<Long> activeGlobalObjectRefs') &&
        globalReferences
            .contains('static synchronized boolean deleteGlobalObjectRef') &&
        !globalReferences.contains('deletedGlobalObjectRefs'),
    'JNI reference deduplication must track live allocations instead of reusable addresses',
  );
}
