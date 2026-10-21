/// Backend-owned resources, separate from route planning and output reports.
/// Session only calls the awaited terminal operations of this interface.
abstract class HdrOutputResources<P> {
  Future<void> endAttempt(P plan);

  /// Terminal cleanup for an attempt whose output was ACCEPTED and stays
  /// live: keeps route-scoped presentation armed together with the ownership
  /// needed to protect it until replacement or disposal. The default falls back to the
  /// full [endAttempt] (implementations without a live-output concept are
  /// unaffected).
  Future<void> endAttemptRetainingWindow(P plan) => endAttempt(plan);

  Future<void> dispose();
}

/// Optional backend lifecycle policy. It never appears in public preferences.
abstract class HdrOutputRequestPolicy {
  void validateOpenRequest();
  void validateConfigurationChange();
}
