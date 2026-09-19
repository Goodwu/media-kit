import 'dart:io';

void _require(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

void main() {
  final source = File('lib/src/video/video_texture.dart').readAsStringSync();
  final candidate = source.indexOf('final nativeOhosCandidate =');
  final textureFallback = source.indexOf('if (!nativeSurface)', candidate);

  _require(candidate >= 0 && textureFallback > candidate,
      'OHOS candidate must be declared before the Texture fallback');

  final candidateBranch = source.substring(candidate, textureFallback);
  _require(
      candidateBranch.contains('child: nativeVideo') &&
          !candidateBranch.contains('Opacity(') &&
          !candidateBranch.contains('Offstage(') &&
          !candidateBranch.contains('opacity:'),
      'inactive OHOS candidates must remain painted and must not be hidden');

  _require(
      source.contains('if (!nativeSurface)') &&
          source.contains('child: Texture(') &&
          RegExp(r'if \(nativeSurface\s*&&\s*!nativeOhosCandidate\)')
              .hasMatch(source),
      'Texture must remain the inactive fallback while active native output '
      'keeps its native rendering path');
}
