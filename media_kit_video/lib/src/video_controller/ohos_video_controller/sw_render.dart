// Keep the OHOS FFI implementation out of JavaScript and WebAssembly builds.
// Runtime platform checks cannot prevent unsupported libraries being compiled.
export 'sw_render_stub.dart' if (dart.library.io) 'sw_render_io.dart';
