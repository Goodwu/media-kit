/// Backend-owned resources, separate from route planning and output reports.
/// Session only calls the awaited terminal operations of this interface.
abstract class HdrOutputResources<P> {
  Future<void> endAttempt(P plan);
  Future<void> dispose();
}

/// Optional backend lifecycle policy. It never appears in public preferences.
abstract class HdrOutputRequestPolicy {
  void validateOpenRequest();
  void validateConfigurationChange();
}
