import '../video_controller/platform_video_controller.dart';
import 'hdr_output_resources.dart';

/// Compatibility boundary for the explicit historical lab configuration.
/// This is not used to authorize or manufacture an ordinary output owner.
HdrOutputRequestPolicy createHdrOutputRequestPolicy(
        VideoControllerConfiguration configuration) =>
    _OutputRequestPolicy(configuration.android.lgExperimentOwnerToken != null);

class _OutputRequestPolicy implements HdrOutputRequestPolicy {
  _OutputRequestPolicy(this.singleOpen);
  final bool singleOpen;
  bool _used = false;

  @override
  void validateOpenRequest() {
    if (!singleOpen) return;
    if (_used) throw StateError('LG experiment Session permits one open attempt only');
    _used = true;
  }

  @override
  void validateConfigurationChange() {
    if (singleOpen) {
      throw StateError('LG single-open experiment rejects configuration controls');
    }
  }
}
