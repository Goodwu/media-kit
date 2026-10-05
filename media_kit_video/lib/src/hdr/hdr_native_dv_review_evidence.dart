import 'package:media_kit/media_kit.dart' show FileLoadedRecord;

import '../video_controller/android_video_controller/platform_surface_release.dart';
import 'android_mediacodec_configuration.dart';
import 'hdr_native_dv_option_owner.dart';

/// Internal observation of a configured decoder on one owned source/output.
/// It proves neither visible frames nor an HDR display mode. Equal output
/// snapshots across awaits do not prove uninterrupted binding between them.
class HdrNativeDvReviewEvidence {
  const HdrNativeDvReviewEvidence({
    required this.source,
    required this.loaded,
    required this.controller,
    required this.output,
    required this.configuration,
    required this.hwdecCurrent,
  });

  final HdrOptionSourceIdentity source;
  final FileLoadedRecord loaded;
  final Object controller;
  final AndroidSurfaceAccountId output;
  final AndroidMediaCodecConfiguration configuration;
  final String hwdecCurrent;
}

/// Synchronous current-output sample. No output readiness wait holds Player.lock.
class HdrNativeDvOutputSnapshot {
  const HdrNativeDvOutputSnapshot(this.controller, this.identity);
  final Object controller;
  final AndroidSurfaceAccountId identity;

  bool matches(HdrNativeDvOutputSnapshot other) =>
      identical(controller, other.controller) && identity == other.identity;
}

enum HdrNativeDvReviewFailureKind {
  ownership,
  sourceIdentity,
  fileLoaded,
  outputIdentity,
  configuration,
  hwdec,
  timeout,
}

/// No cleanup is attempted here. The caller must retain ownership failures
/// (including restoration debt) when deciding whether a retry is safe.
class HdrNativeDvReviewFailure implements Exception {
  const HdrNativeDvReviewFailure(this.kind, {this.cause});
  final HdrNativeDvReviewFailureKind kind;
  final Object? cause;

  @override
  String toString() => 'HdrNativeDvReviewFailure(${kind.name}, $cause)';
}
