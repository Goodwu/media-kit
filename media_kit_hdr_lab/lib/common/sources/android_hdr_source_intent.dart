// MIGRATED (S10/S13): the library implementation lives in media_kit_video/lib/src/hdr/;
// this file is kept only for hdr_lab tests that still reference it and is no longer
// wired into the 01 test page.
class AndroidHdrSourceSnapshot<T> {
  const AndroidHdrSourceSnapshot(this.requestSerial, this.session);

  final int requestSerial;
  final T? session;
}

/// Tracks page-level open intent before asynchronous coordinator setup starts.
/// Only the newest completed request may become the page's active session.
class AndroidHdrSourceIntent<T> {
  int _serial = 0;
  int _pending = 0;
  String? _source;
  T? _session;

  String? get source => _source;
  T? get session => _session;
  int get pending => _pending;

  int begin() {
    ++_pending;
    // The coordinator invalidates the previous generation immediately, even
    // if this request later fails during identity verification.
    _source = null;
    _session = null;
    return ++_serial;
  }

  void succeed(int serial, String source, T session) {
    if (_pending < 1) throw StateError('No pending HDR open');
    --_pending;
    if (serial == _serial) {
      _source = source;
      _session = session;
    }
  }

  void fail(int serial) {
    if (_pending < 1) throw StateError('No pending HDR open');
    --_pending;
  }

  AndroidHdrSourceSnapshot<T> snapshot() =>
      AndroidHdrSourceSnapshot<T>(_serial, _session);

  bool mayResume(AndroidHdrSourceSnapshot<T> snapshot) =>
      _pending == 0 &&
      _session != null &&
      snapshot.requestSerial == _serial &&
      identical(snapshot.session, _session);
}
