# This file is a part of media_kit (https://github.com/media-kit/media-kit).
#
# Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
# All rights reserved.
# Use of this source code is governed by MIT license that can be found in the LICENSE file.

cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "media_kit_video")
set(CMAKE_CXX_STANDARD 17)
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "media_kit_video_plugin")

# This is shipped as part of package:media_kit_libs_*** package(s).
# Must be built before this target.
option(MEDIA_KIT_VIDEO_LIBS_AVAILABLE "package:media_kit video libraries are available." OFF)
set(LIBMPV_SRC "${CMAKE_BINARY_DIR}/libmpv")
set(LIBMPV_INCLUDE "${LIBMPV_SRC}/include")
set(LIBMPV_IMPORT_LIBRARY "${LIBMPV_SRC}/libmpv.dll.a")
set(MEDIA_KIT_EXTERNAL_NATIVE_PACKAGE FALSE)
foreach(_input MEDIA_KIT_NATIVE_PACKAGE_ROOT MEDIA_KIT_NATIVE_PACKAGE_MANIFEST MEDIA_KIT_NATIVE_PACKAGE_MANIFEST_SHA256)
  if(DEFINED ENV{${_input}})
    set(MEDIA_KIT_EXTERNAL_NATIVE_PACKAGE TRUE)
  endif()
endforeach()
if(MEDIA_KIT_EXTERNAL_NATIVE_PACKAGE)
  if(NOT MEDIA_KIT_VIDEO_LIBS_AVAILABLE)
    message(FATAL_ERROR "Explicit Windows native packages require media_kit_libs_windows_video")
  endif()
  string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" _package_processor)
  string(TOLOWER "${CMAKE_GENERATOR_PLATFORM}" _package_generator)
  set(MEDIA_KIT_PACKAGE_PLATFORM windows)
  if(_package_generator MATCHES "^(arm64|aarch64)$" OR
     (_package_generator STREQUAL "" AND _package_processor MATCHES "^(arm64|aarch64)$"))
    set(MEDIA_KIT_PACKAGE_ARCHITECTURE arm64)
  elseif(_package_generator MATCHES "^(x64|amd64|x86_64)$" OR
         (_package_generator STREQUAL "" AND _package_processor MATCHES "^(x64|amd64|x86_64)$"))
    set(MEDIA_KIT_PACKAGE_ARCHITECTURE x86_64)
  else()
    message(FATAL_ERROR "Unsupported Windows native package architecture")
  endif()
  get_filename_component(_media_kit_package_source "${CMAKE_CURRENT_SOURCE_DIR}" REALPATH)
  include("${_media_kit_package_source}/../../tool/native_package/consume.cmake")
  set(LIBMPV_INCLUDE "${MEDIA_KIT_PACKAGE_INCLUDE}/mpv")
  set(LIBMPV_IMPORT_LIBRARY "${MEDIA_KIT_PACKAGE_IMPORT_LIBRARY}")
endif()

# Deal with MSVC incompatiblity
add_compile_definitions(_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR)

if(MEDIA_KIT_VIDEO_LIBS_AVAILABLE)
  include_directories(
    "${LIBMPV_INCLUDE}"
  )

  add_library(
    ${PLUGIN_NAME} SHARED
    "d3d11_renderer.cc"
    "d3d11_native_surface_backend.cc"
    "mailbox_swap_chain.cc"
    "media_kit_video_plugin_c_api.cc"
    "media_kit_video_plugin.cc"
    "video_output_manager.cc"
    "video_output.cc"
    "utils.cc"
    ${PLUGIN_SOURCES}
  )

  apply_standard_settings(${PLUGIN_NAME})

  set_target_properties(
    ${PLUGIN_NAME} PROPERTIES
    CXX_VISIBILITY_PRESET hidden
  )
  target_compile_definitions(
    ${PLUGIN_NAME} PRIVATE
    FLUTTER_PLUGIN_IMPL
  )

  target_compile_options(${PLUGIN_NAME} PRIVATE "/utf-8")

  target_include_directories(
    ${PLUGIN_NAME} INTERFACE
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
  )

  target_link_libraries(
    ${PLUGIN_NAME} PRIVATE
    flutter
    flutter_wrapper_plugin

    # Link to libmpv.
    "${LIBMPV_IMPORT_LIBRARY}"
  )
else()
  message(NOTICE "media_kit: WARNING: package:media_kit_libs_*** not found.")

  add_library(
    ${PLUGIN_NAME} SHARED
    "media_kit_video_plugin_c_api.cc"
    ${PLUGIN_SOURCES}
  )

  apply_standard_settings(${PLUGIN_NAME})

  set_target_properties(
    ${PLUGIN_NAME} PROPERTIES
    CXX_VISIBILITY_PRESET hidden
  )

  target_compile_definitions(
    ${PLUGIN_NAME} PRIVATE
    FLUTTER_PLUGIN_IMPL

    # Add macro to indicate that libmpv from package:media_kit_libs_*** are not found.
    "MEDIA_KIT_LIBS_NOT_FOUND=1"
  )

  target_include_directories(
    ${PLUGIN_NAME} INTERFACE
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
  )

  target_link_libraries(
    ${PLUGIN_NAME} PRIVATE
    flutter
    flutter_wrapper_plugin
  )
endif()

set(
  media_kit_video_bundled_libraries
  ""
  PARENT_SCOPE
)
