cmake_minimum_required(VERSION 3.22.1)
project(media_kit_p5_probe)

add_library(media_kit_p5_probe SHARED p5_codec_probe.cpp p5_gpu_import_probe.cpp p5_native_reader_probe.cpp)
find_library(android-lib android)
find_library(dl-lib dl)
find_library(egl-lib EGL)
find_library(gles3-lib GLESv3)
target_link_libraries(media_kit_p5_probe ${android-lib} ${dl-lib} ${egl-lib} ${gles3-lib})
