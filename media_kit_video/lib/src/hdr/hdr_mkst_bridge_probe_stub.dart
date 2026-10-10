/// Host/web stand-in for the native bridge probe: no dynamic library can be
/// opened off the device, so the official backend capability is absent.
bool mkstBridgeInitialized() => false;
