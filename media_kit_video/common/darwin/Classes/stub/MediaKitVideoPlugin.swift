#if canImport(Flutter)
  import Flutter
#elseif canImport(FlutterMacOS)
  import FlutterMacOS
#endif

public class MediaKitVideoPlugin: NSObject, FlutterPlugin {
  public static func register(with _: FlutterPluginRegistrar) {}

  #if os(macOS)
  // No-op counterparts of the plugin's shutdown hooks: without the libs
  // packages there is no libmpv wakeup owner to drain, but the host's
  // AppDelegate must compile identically with and without them.
  public static func prepareForEngineShutdown(_: FlutterEngine) {}

  public static func recordWakeupShutdownDiagnostic(
    _: String,
    fields _: [String: Int] = [:]
  ) {}
  #endif
}
