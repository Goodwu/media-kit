#pragma once

namespace media_kit_video {

// Compilation boundary for the future D3D11 HDR flip-model backend.
// It intentionally reports false until the swap-chain/color-space probe exists.
class D3D11NativeSurfaceBackend {
 public:
  bool IsCapable() const { return false; }
  bool IsActive() const { return false; }
};

}  // namespace media_kit_video
