#pragma once

namespace media_kit_video {

// Compilation boundary for the future Wayland color-management backend.
class WaylandNativeSurfaceBackend {
 public:
  bool IsCapable() const { return false; }
  bool IsActive() const { return false; }
};

}  // namespace media_kit_video
