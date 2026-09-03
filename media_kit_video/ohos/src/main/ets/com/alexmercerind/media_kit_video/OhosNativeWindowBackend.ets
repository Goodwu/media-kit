/** Fail-closed compile boundary for future XComponent/OHNativeWindow HDR output. */
export class OhosNativeWindowBackend {
  isCapable(): boolean { return false; }
  isActive(): boolean { return false; }
}
