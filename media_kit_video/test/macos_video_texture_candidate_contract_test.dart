import 'dart:io';

void _require(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

int _platformViewCount({
  required bool candidate,
  required bool active,
  required bool macos,
  required bool ohos,
}) {
  final candidateMount = candidate ? 1 : 0;
  final activeMount = active && !ohos && !macos ? 1 : 0;
  return candidateMount + activeMount;
}

void main() {
  final source = File('lib/src/video/video_texture.dart').readAsStringSync();
  final nativeSurfaceState = source.indexOf('final nativeSurface =');
  final macosCandidate = source.indexOf('final nativeMacosCandidate =');
  final candidateMount = source.indexOf(
    'if (nativeSurfaceCandidate)',
    macosCandidate,
  );
  final textureFallback = source.indexOf('if (!nativeSurface)', candidateMount);
  // Whitespace-tolerant: the upstream merge re-indented this block, which must
  // not affect the guarded composition-order contract.
  final activeMount = source.substring(textureFallback).indexOf(
        RegExp(
          r'if \(nativeSurface &&\s*'
          r'!nativeOhosCandidate &&\s*'
          r'!nativeMacosCandidate\)',
        ),
      ) +
      textureFallback;

  _require(
    nativeSurfaceState >= 0 &&
        RegExp(
          r'final nativeSurface\s*=\s*nativeSurfaceCandidate\s*&&[\s\S]*?'
          r'nativeSurfaceActive',
        ).hasMatch(source.substring(nativeSurfaceState, macosCandidate)) &&
        macosCandidate >= 0 &&
        source.indexOf('Platform.isMacOS;', macosCandidate) > macosCandidate,
    'normal native-surface activation must remain notifier-driven and the '
    'single-mount exception must be scoped to macOS candidates',
  );
  _require(
    candidateMount > macosCandidate &&
        textureFallback > candidateMount &&
        activeMount > textureFallback,
    'candidate PlatformView, Texture fallback, and active legacy mount must '
    'retain their composition order',
  );
  _require(
    RegExp(
          r'Platform\s*\.isAndroid\s*&&\s*notifier\.configuration\s*'
          r'\.usePlatformView',
        ).hasMatch(source) &&
        source.contains('final nativeOhosCandidate ='),
    'Android PlatformView and OHOS native-candidate selection must remain '
    'unchanged',
  );

  final candidateBranch = source.substring(candidateMount, textureFallback);
  _require(
    RegExp(
      r'child:\s*nativeMacosCandidate\s*\?\s*nativeVideo\s*:\s*Center\(',
    ).hasMatch(candidateBranch),
    'the stable macOS candidate must directly fill its Positioned.fill box',
  );
  _require(
    candidateBranch.contains('width: nativeOhosSurface') &&
        candidateBranch.contains('? surfaceWidth') &&
        candidateBranch.contains('height: nativeOhosSurface') &&
        candidateBranch.contains('? surfaceHeight') &&
        candidateBranch.contains('nativeVideo,'),
    'OHOS and other candidate surfaces must retain Center and SizedBox sizing',
  );
  _require(
    source.substring(textureFallback, activeMount).contains('child: Texture('),
    'Texture must remain the fallback overlay while native output is inactive',
  );

  _require(
    _platformViewCount(
          candidate: true,
          active: false,
          macos: true,
          ohos: false,
        ) ==
        1,
    'an inactive macOS candidate must mount one PlatformViewVideo',
  );
  _require(
    _platformViewCount(
          candidate: true,
          active: true,
          macos: true,
          ohos: false,
        ) ==
        1,
    'macOS candidate-to-active promotion must not mount a second AppKitView',
  );
  _require(
    _platformViewCount(
          candidate: true,
          active: true,
          macos: false,
          ohos: true,
        ) ==
        1,
    'OHOS must retain its existing single candidate surface',
  );
  _require(
    _platformViewCount(
          candidate: true,
          active: true,
          macos: false,
          ohos: false,
        ) ==
        2,
    'non-macOS/non-OHOS platforms must retain the existing active branch',
  );
}
