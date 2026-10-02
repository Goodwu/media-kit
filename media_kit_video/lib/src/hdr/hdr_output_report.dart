/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'hdr_open_plan.dart';
import 'hdr_route.dart';
import 'hdr_source_descriptor.dart';

/// {@template hdr_output_report}
///
/// HdrOutputReport
/// ---------------
/// The listenable routing state of the current open generation (R4.2): the
/// source description and where it came from, the predicted and actually
/// applied routes with the skipped candidates, the dataspace outcome,
/// `hwdec-current`, whether verification completed, the degradation reason
/// or error, and the open generation.
///
/// A report only ever describes the current generation; the session never
/// publishes one for a superseded open.
///
/// {@endtemplate}
class HdrOutputReport {
  const HdrOutputReport({
    this.generation = 0,
    this.source,
    this.sourceOrigin,
    this.prediction,
    this.actual,
    this.dataSpaceRequested,
    this.dataSpacePath,
    this.dataSpaceReadback,
    this.hwdecCurrent,
    this.verified = false,
    this.degradeReason,
    this.diagnostic,
    this.error,
  });

  /// The open generation this report belongs to.
  final int generation;

  /// The description of the current source, when known.
  final HdrSourceDescriptor? source;

  /// Whether [source] came from the caller hint or from the decoder review;
  /// null when neither has happened yet.
  final HdrReportSource? sourceOrigin;

  /// The prediction the route was selected from, including the full
  /// candidate list with skip reasons.
  final HdrRoutePrediction? prediction;

  /// The route actually being executed, when playback opened.
  final HdrRoute? actual;

  /// Dataspace requested for the GPU surface (`pq`/`hlg`), when the route
  /// needs one.
  final String? dataSpaceRequested;

  /// Actual applied dataspace path: `ndk`/`surfaceControl`/`ext:<id>`/`none`.
  final String? dataSpacePath;

  /// The dataspace read back from the surface (e.g. `DATASPACE_BT2020_PQ`),
  /// or `none`.
  final String? dataSpaceReadback;

  /// The observed `hwdec-current`, when read.
  final String? hwdecCurrent;

  /// Whether the decoder review completed for this generation.
  final bool verified;

  /// The typed degradation reason, when the open degraded (or was blocked,
  /// e.g. `p5PipelineUnavailable`) or runs on an unsupported platform
  /// (`unsupportedPlatform`).
  final HdrDegradeReason? degradeReason;

  /// Human-readable diagnostics: a persisted review mismatch, a dataspace
  /// path/readback detail, or a backend failure message.
  final String? diagnostic;

  /// The error object when the open failed.
  final Object? error;

  HdrOutputReport copyWith({
    int? generation,
    HdrSourceDescriptor? source,
    HdrReportSource? sourceOrigin,
    HdrRoutePrediction? prediction,
    HdrRoute? actual,
    String? dataSpaceRequested,
    String? dataSpacePath,
    String? dataSpaceReadback,
    String? hwdecCurrent,
    bool? verified,
    HdrDegradeReason? degradeReason,
    String? diagnostic,
    Object? error,
  }) {
    return HdrOutputReport(
      generation: generation ?? this.generation,
      source: source ?? this.source,
      sourceOrigin: sourceOrigin ?? this.sourceOrigin,
      prediction: prediction ?? this.prediction,
      actual: actual ?? this.actual,
      dataSpaceRequested: dataSpaceRequested ?? this.dataSpaceRequested,
      dataSpacePath: dataSpacePath ?? this.dataSpacePath,
      dataSpaceReadback: dataSpaceReadback ?? this.dataSpaceReadback,
      hwdecCurrent: hwdecCurrent ?? this.hwdecCurrent,
      verified: verified ?? this.verified,
      degradeReason: degradeReason ?? this.degradeReason,
      diagnostic: diagnostic ?? this.diagnostic,
      error: error ?? this.error,
    );
  }

  @override
  String toString() => 'HdrOutputReport(gen: $generation, '
      'source: $source (${sourceOrigin?.name}), actual: $actual, '
      'dataspace: $dataSpaceRequested/$dataSpacePath/$dataSpaceReadback, '
      'hwdec: $hwdecCurrent, verified: $verified, '
      'degrade: ${degradeReason?.name}, diagnostic: $diagnostic, '
      'error: $error)';
}
