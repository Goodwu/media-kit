import 'hdr_route.dart';

/// The vendor YUV window presentation arm failed to arm, or its terminal
/// cleanup failed. Fail-closed for the YUV attempt: a silently skipped arm
/// would open the NV12 window without the PQ/LIMITED injection (misleading
/// playback), and a failed disarm must surface as cleanup debt rather than
/// leak an armed flag past its attempt.
class HdrOutputPreparationFailure implements Exception {
  const HdrOutputPreparationFailure(this.reason, {this.cause});
  final HdrDegradeReason reason;
  final Object? cause;
  @override
  String toString() => 'HdrOutputPreparationFailure(${reason.name}, $cause)';
}

/// This output initialization is rejected by the process-level admission:
/// another session or engine currently holds the YUV window arm write
/// admission, retains its cleanup debt, has a non-YUV initialization
/// mid-flight, or this manager re-entered an initialization that is still
/// in flight (B1). The rejected attempt fails outright — every route it
/// could degrade to would still initialize an output over process-global
/// atomics or in-flight state this attempt does not own, which is exactly
/// the silent-poisoning regression this guard exists to prevent. Deliberately
/// NOT an [HdrOutputPreparationFailure], so the session's failure-driven
/// replanning never treats a cross-session conflict as a route capability
/// problem.
class HdrOutputLeaseConflict implements Exception {
  const HdrOutputLeaseConflict(this.description);
  final String description;
  @override
  String toString() => 'HdrOutputLeaseConflict($description)';
}
