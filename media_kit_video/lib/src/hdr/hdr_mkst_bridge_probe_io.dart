import 'dart:ffi';

/// Official backend capability probe (frozen A2 contract): the bridge
/// reports its explicit init state through the verify-only
/// `mkst_ensure_init` export; 1 = an owner bound it (capability present),
/// 0 = not. Any load, lookup or call failure reads as absent. The probe
/// NEVER initializes the bridge — the Java explicit init is the only
/// initialization entry — so calling it from a bare Dart thread cannot
/// poison the owner-scoped init.
bool mkstBridgeInitialized() {
  try {
    final bridge = DynamicLibrary.open('libmedia_kit_video_hdr_bridge.so');
    final ensureInit =
        bridge.lookupFunction<Int Function(), int Function()>('mkst_ensure_init');
    return ensureInit() == 1;
  } catch (_) {
    return false;
  }
}
