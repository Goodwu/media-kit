cmake_minimum_required(VERSION 3.22.1)
project(media_kit_video_hdr_bridge)

add_library(media_kit_video_hdr_bridge SHARED surface_dataspace.cpp mediakit_surfacetexture_bridge.cpp)

# Compile-time version stamp read back through mkst_version() for telemetry
# of the opt-in surfacetexture hwdec backend.
add_definitions(-DMKSURF_VERSION="surfacetexture-poc-r2")

find_library(android-lib android)
find_library(log-lib log)
find_library(dl-lib dl)
find_library(egl-lib EGL)
find_library(gles2-lib GLESv2)

target_link_libraries(media_kit_video_hdr_bridge ${android-lib} ${log-lib} ${dl-lib} ${egl-lib} ${gles2-lib})
