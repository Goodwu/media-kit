/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.

/// {@template hdr_output_report}
///
/// HdrOutputReport
/// ---------------
/// Typed result of a native HDR output operation (create, configure, reset).
///
/// The common fields are typed; [data] carries the platform's full report
/// (e.g. `backend`, `surfaceId`, `generation`, mastering metadata echoes) so
/// diagnostics never lose information to the abstraction.
///
/// {@endtemplate}
class HdrOutputReport {
  const HdrOutputReport({
    this.capable = false,
    this.active = false,
    this.stale = false,
    this.failureReason,
    this.outputEpoch,
    this.data = const <String, dynamic>{},
  });

  factory HdrOutputReport.fromMap(Map<String, dynamic> map) {
    return HdrOutputReport(
      capable: map['capable'] == true,
      active: map['active'] == true,
      stale: map['stale'] == true,
      failureReason: map['failureReason'] is String
          ? map['failureReason'] as String
          : null,
      outputEpoch: map['outputEpoch'] is int ? map['outputEpoch'] as int : null,
      data: map,
    );
  }

  /// Whether the platform can provide a native HDR output at all.
  final bool capable;

  /// Whether the native HDR output is currently active.
  final bool active;

  /// Whether this report describes a superseded transaction; its result
  /// must not be published over a newer output state.
  final bool stale;

  /// Machine-readable failure reason when [capable] or [active] is false.
  final String? failureReason;

  /// Native output epoch this report belongs to, when the platform reports
  /// one.
  final int? outputEpoch;

  /// The platform's full report map.
  final Map<String, dynamic> data;

  @override
  String toString() => 'HdrOutputReport($data)';
}
