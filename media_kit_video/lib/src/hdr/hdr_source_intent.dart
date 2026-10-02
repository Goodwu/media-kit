/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.

class HdrSourceSnapshot<T> {
  const HdrSourceSnapshot(this.requestSerial, this.session);

  final int requestSerial;
  final T? session;
}

/// Tracks page-level open intent before asynchronous coordinator setup starts.
/// Only the newest completed request may become the page's active session.
///
/// Ported from hdr_lab's `AndroidHdrSourceIntent` with identical semantics.
class HdrSourceIntent<T> {
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
    // if this request later fails during preparation.
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

  HdrSourceSnapshot<T> snapshot() => HdrSourceSnapshot<T>(_serial, _session);

  bool mayResume(HdrSourceSnapshot<T> snapshot) =>
      _pending == 0 &&
      _session != null &&
      snapshot.requestSerial == _serial &&
      identical(snapshot.session, _session);
}
