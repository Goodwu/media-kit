// ignore_for_file: implementation_imports
import 'package:media_kit/media_kit.dart' show Media;
import 'package:media_kit_video/media_kit_video.dart';

/// One immutable owner per Session, one consumed attempt including failures.
class AndroidLgSingleOpenOwner {
  AndroidLgSingleOpenOwner(this.token);
  final String token;
  bool _used = false;
  int? _handle;
  void claim() {
    if (_used) {
      throw StateError(
          'LG experiment owner already used; create a new Session');
    }
    _used = true;
  }

  void bindHandle(int handle) {
    if (_handle != null && _handle != handle) {
      throw StateError('Experiment handle changed');
    }
    _handle = handle;
  }

  Future<void> revoke(Future<void> Function(String, int) callback) async {
    final handle = _handle;
    if (handle != null) await callback(token, handle);
  }

  Future<void> open(
      {required HdrVideoSession session,
      required Media media,
      HdrSourceDescriptor? hint,
      Duration? start,
      required Future<void> Function() prepare,
      required Future<void> Function(String, int) revokeOwner}) async {
    claim(); // Synchronous, before any await, permanent on prepare/open failure.
    try {
      await prepare();
      await session.open(media, hint: hint, start: start);
      if (session.report.value.error != null ||
          session.report.value.actual == null) {
        throw StateError('LG experiment Session failed');
      }
    } catch (_) {
      await revoke(revokeOwner);
      rethrow;
    }
  }
}

/// Lab-only contract. Reject before Session can prepare/open any other route,
/// including the planner's SDR safety net and dependency-failure retries.
class AndroidHdrConvertExperiment {
  const AndroidHdrConvertExperiment(this.surfaceTransfer, this.outputLevels);

  final String surfaceTransfer;
  final String outputLevels;

  static void validateVisual278Admission(
      {required bool enabled,
      required bool routeLocked,
      required bool android,
      required bool hdrTransaction}) {
    if (enabled && (!routeLocked || !android || !hdrTransaction)) {
      throw StateError(
          'Visual278 experiment requires Android strict HDR route lock');
    }
  }

  void validateAdmission({required bool dataSpacePerformProbe}) {
    validate();
    if (dataSpacePerformProbe) {
      throw StateError('Convert route lock excludes DATASPACE_PERFORM_PROBE');
    }
  }

  void validate() {
    if (!((surfaceTransfer == 'pq' && outputLevels == 'full') ||
        (surfaceTransfer == 'pq-itu' && outputLevels == 'limited'))) {
      throw StateError('Convert experiment requires pq/full or pq-itu/limited');
    }
  }

  Future<void> prepareOutputLevels({
    required Future<void> Function(String) set,
    required Future<String> Function() read,
  }) async {
    validate();
    await set(outputLevels);
    final actual = await read();
    if (actual != outputLevels) {
      throw StateError('Output levels not accepted: $actual');
    }
  }

  HdrRoutePrediction plan({
    required HdrSourceDescriptor source,
    required HdrCapabilities capabilities,
    required HdrRoutingPolicy policy,
    required HdrOutputPreference preference,
    required Map<String, HdrDegradeReason> excluded,
  }) {
    validate();
    final cls = HdrSourceClass.of(source);
    if (cls != HdrSourceClass.hlg &&
        cls != HdrSourceClass.dvP84 &&
        cls != HdrSourceClass.hdr10) {
      throw const HdrPlaybackBlocked(HdrDegradeReason.unsupportedStrategy);
    }
    final prediction = HdrRoutePlanner.plan(
      source: source,
      capabilities: capabilities,
      policy: HdrRoutingPolicy(
        preferences: {
          HdrSourceClass.of(source): const [HdrStrategy.baseLayerConvert],
        },
        allowExperimental: policy.allowExperimental,
      ),
      preference: preference,
      excluded: excluded,
    );
    final route = prediction.selected.route;
    if (!prediction.playable ||
        route == null ||
        route.strategy != HdrStrategy.baseLayerConvert ||
        route.outputTransfer != HdrOutputTransfer.pq ||
        route.targetTrc != 'pq' ||
        route.surfaceTransfer != surfaceTransfer ||
        route.topology != HdrTopology.platformView ||
        route.vo != 'gpu-next' ||
        route.hwdec != 'mediacodec-copy') {
      throw const HdrPlaybackBlocked(HdrDegradeReason.unsupportedStrategy);
    }
    return prediction;
  }
}
