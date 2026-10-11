import 'dart:ui' show FlutterView, PlatformDispatcher;

/// The intended output, not a Player or a native video Surface.
///
/// A null target in query means device-only. Default display must be chosen
/// explicitly. Flutter IDs are opaque and are NOT OS display/window IDs.
class VideoOutputTarget {
  const VideoOutputTarget.applicationView()
      : kind = 'applicationView',
        view = null,
        platform = null,
        displayId = null;
  const VideoOutputTarget.defaultDisplay()
      : kind = 'defaultDisplay',
        view = null,
        platform = null,
        displayId = null;
  VideoOutputTarget.flutterView(FlutterView flutterView)
      : kind = 'flutterView',
        view = flutterView,
        platform = null,
        displayId = null;
  VideoOutputTarget.nativeDisplay(
      {required this.platform, required this.displayId})
      : kind = 'nativeDisplay',
        view = null {
    if (platform == null ||
        platform!.isEmpty ||
        displayId == null ||
        displayId! < 0) {
      throw ArgumentError(
          'A platform namespace and valid OS display ID are required');
    }
  }

  final String kind;
  final FlutterView? view;
  final String? platform;
  final int? displayId;

  Map<String, Object?> toMap() {
    final currentView = view;
    if (currentView != null) {
      final dispatcher = PlatformDispatcher.instance;
      // The first Android adapter can resolve its attached implicit view.
      // Non-implicit/multi-view requests remain unresolved, never mapped by
      // casting Flutter display.id to an Android display ID.
      final live = dispatcher.views.any((v) => identical(v, currentView));
      return <String, Object?>{
        'kind': kind,
        'viewId': currentView.viewId,
        'live': live,
        'implicit': live && identical(dispatcher.implicitView, currentView),
      };
    }
    return <String, Object?>{
      'kind': kind,
      if (platform != null) 'platform': platform,
      if (displayId != null) 'displayId': displayId,
    };
  }
}
