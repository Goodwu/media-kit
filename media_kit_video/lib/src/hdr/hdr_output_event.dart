/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'hdr_capabilities.dart';
import 'hdr_output_report.dart';
import 'hdr_route.dart';
import 'hdr_source_descriptor.dart';

/// Base type of the session event stream (R3): every event carries the open
/// generation it belongs to. Events are informational — the library never
/// switches sources or retries on the caller's behalf.
abstract class HdrOutputEvent {
  const HdrOutputEvent(this.generation);

  final int generation;
}

/// A route was applied and verified for the current generation.
class HdrRouteAppliedEvent extends HdrOutputEvent {
  const HdrRouteAppliedEvent(
    super.generation, {
    required this.route,
    required this.report,
  });

  final HdrRoute route;
  final HdrOutputReport report;

  @override
  String toString() => 'HdrRouteAppliedEvent(gen: $generation, route: $route)';
}

/// A degradation step happened (R3.1/R3.2): a candidate failed and the next
/// one was (or will be) tried, a preference forced SDR, or a capability was
/// lost. Carries the typed reason and a diagnostic text.
class HdrDegradedEvent extends HdrOutputEvent {
  const HdrDegradedEvent(
    super.generation, {
    required this.reason,
    this.diagnostic = '',
    this.from,
    this.to,
  });

  final HdrDegradeReason reason;
  final String diagnostic;

  /// The route that failed (or was abandoned), when known.
  final HdrRoute? from;

  /// The route the session moved (or will move) to, when known.
  final HdrRoute? to;

  @override
  String toString() => 'HdrDegradedEvent(gen: $generation, '
      'reason: ${reason.name}, from: ${from?.strategy.name}, '
      'to: ${to?.strategy.name}, diagnostic: $diagnostic)';
}

/// The decoder review produced a different source description than the one
/// the route was planned against (R2.3). [rebuilt] says whether the session
/// performed the single allowed in-place rebuild; a second mismatch is
/// reported as-is without another rebuild.
class HdrReclassifiedEvent extends HdrOutputEvent {
  const HdrReclassifiedEvent(
    super.generation, {
    required this.previous,
    required this.current,
    required this.rebuilt,
  });

  final HdrSourceDescriptor previous;
  final HdrSourceDescriptor current;
  final bool rebuilt;

  @override
  String toString() => 'HdrReclassifiedEvent(gen: $generation, '
      'previous: $previous, current: $current, rebuilt: $rebuilt)';
}

/// The device capability snapshot changed (system HDR toggle, display
/// switch). Recovery is reported only — the session does not automatically
/// upgrade back to HDR (R3.4).
class HdrCapabilityChangedEvent extends HdrOutputEvent {
  const HdrCapabilityChangedEvent(super.generation, this.capabilities);

  final HdrCapabilities capabilities;

  @override
  String toString() => 'HdrCapabilityChangedEvent(gen: $generation, '
      'capabilities: $capabilities)';
}

/// An error: playback blocked (`p5PipelineUnavailable`, R3.3), an open
/// failure, or an unexpected backend error.
class HdrErrorEvent extends HdrOutputEvent {
  const HdrErrorEvent(
    super.generation, {
    this.reason,
    this.error,
    this.diagnostic = '',
  });

  /// Typed reason when there is one (e.g. `p5PipelineUnavailable`).
  final HdrDegradeReason? reason;

  /// The underlying error object, when any.
  final Object? error;

  final String diagnostic;

  @override
  String toString() => 'HdrErrorEvent(gen: $generation, '
      'reason: ${reason?.name}, error: $error, diagnostic: $diagnostic)';
}
