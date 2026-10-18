"""Recognize an exact Flutter-generated include, never rewrite app inputs.

Source: Flutter abaf9c523780a608bd46686fd5e53740a07077f8,
packages/flutter_tools/lib/src/macos/cocoapods.dart, _addPodsDependencyToFlutterXcconfig.
The generator prepends exactly one optional Pods include to the untouched input.
"""
import hashlib

MACOS_MODES = {
    'macos/Flutter/Flutter-Debug.xcconfig': 'debug',
    'macos/Flutter/Flutter-Release.xcconfig': 'release',
}


def digest(data):
    return hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()


def is_generated_cocoapods_include(path: str, original_blob: str, actual: bytes) -> bool:
    mode = MACOS_MODES.get(path)
    if mode is None:
        return False
    prefix = ('#include? "Pods/Target Support Files/Pods-Runner/'
              f'Pods-Runner.{mode}.xcconfig"\n').encode()
    if not actual.startswith(prefix):
        return False
    original = actual[len(prefix):]
    # Flutter does not add an include when one is already present. Reject
    # duplicate includes and do not normalize line endings or original bytes.
    if b'Pods/Target Support Files/Pods-' in original:
        return False
    return digest(original) == original_blob
