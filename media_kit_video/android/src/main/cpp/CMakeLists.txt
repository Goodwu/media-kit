cmake_minimum_required(VERSION 3.22.1)
project(media_kit_video_hdr_bridge)

add_library(media_kit_video_hdr_bridge SHARED surface_dataspace.cpp)

find_library(android-lib android)
find_library(log-lib log)
find_library(dl-lib dl)
find_library(egl-lib EGL)

target_link_libraries(media_kit_video_hdr_bridge ${android-lib} ${log-lib} ${dl-lib} ${egl-lib})
