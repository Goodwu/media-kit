/// Official mkst bridge capability probe. The real (dart:ffi) variant is
/// selected on IO platforms; everywhere else the capability is absent.
export 'hdr_mkst_bridge_probe_stub.dart'
    if (dart.library.io) 'hdr_mkst_bridge_probe_io.dart';
