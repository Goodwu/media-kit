# This file is a part of media_kit (https://github.com/media-kit/media-kit).
#
# Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
# All rights reserved.
# Use of this source code is governed by MIT license that can be found in the LICENSE file.

# The file is moded for the purpose of building application with libmpv embeded.
# Copyright © 2024 & Predidit
# All rights reserved.

cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "media_kit_video")
set(CMAKE_CXX_STANDARD 17)
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "media_kit_video_plugin")

set(CMAKE_BUILD_WITH_INSTALL_RPATH TRUE)
set(CMAKE_INSTALL_RPATH "$ORIGIN")
set(CMAKE_INSTALL_RPATH_USE_LINK_PATH TRUE)

if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|amd64|AMD64")
  set(ARCH_NAME "x86_64")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64|ARM64")
  set(ARCH_NAME "aarch64")
else()
  message(FATAL_ERROR "Unsupported architecture: ${CMAKE_SYSTEM_PROCESSOR}")
endif()

message(STATUS "Detected architecture: ${ARCH_NAME}")

set(LIBMPV_BUNDLE_FILES)
set(MEDIA_KIT_EXTERNAL_NATIVE_PACKAGE FALSE)
foreach(_input MEDIA_KIT_NATIVE_PACKAGE_ROOT MEDIA_KIT_NATIVE_PACKAGE_MANIFEST MEDIA_KIT_NATIVE_PACKAGE_MANIFEST_SHA256)
  if(DEFINED ENV{${_input}})
    set(MEDIA_KIT_EXTERNAL_NATIVE_PACKAGE TRUE)
  endif()
endforeach()
set(_routing_native_inputs_set FALSE)
foreach(_input MEDIA_KIT_LINUX_NATIVE_ROOT MEDIA_KIT_LINUX_NATIVE_RECEIPT MEDIA_KIT_LINUX_NATIVE_APP_ROOT MEDIA_KIT_LINUX_NATIVE_APP_SHA MEDIA_KIT_LINUX_NATIVE_MEDIA_KIT_SHA)
  if(DEFINED ${_input} AND NOT "${${_input}}" STREQUAL "")
    set(_routing_native_inputs_set TRUE)
  endif()
endforeach()

if(MEDIA_KIT_EXTERNAL_NATIVE_PACKAGE)
  if(MEDIA_KIT_ROUTING_MODE OR _routing_native_inputs_set)
    message(FATAL_ERROR "Do not combine generic native packages with legacy Linux routing inputs")
  endif()
  if(NOT MEDIA_KIT_LIBS_AVAILABLE)
    message(FATAL_ERROR "Explicit Linux native packages require media_kit_libs_linux")
  endif()
  set(MEDIA_KIT_PACKAGE_PLATFORM linux)
  set(MEDIA_KIT_PACKAGE_ARCHITECTURE "${ARCH_NAME}")
  if(ARCH_NAME STREQUAL "aarch64")
    set(MEDIA_KIT_PACKAGE_ARCHITECTURE arm64)
  endif()
  get_filename_component(_media_kit_package_source "${CMAKE_CURRENT_SOURCE_DIR}" REALPATH)
  include("${_media_kit_package_source}/../../tool/native_package/consume.cmake")
  get_filename_component(LIBMPV_PATH "${MEDIA_KIT_PACKAGE_RUNTIME}" DIRECTORY)
  set(LIBMPV_HEADER_UNZIP_DIR "${MEDIA_KIT_PACKAGE_INCLUDE}")
  set(LIBMPV_BUNDLE_FILES ${MEDIA_KIT_PACKAGE_BUNDLE})
elseif(MEDIA_KIT_ROUTING_MODE)
  if(NOT ARCH_NAME STREQUAL "x86_64")
    message(FATAL_ERROR "routing Linux native inputs currently require x86_64")
  endif()
  if(NOT MEDIA_KIT_LIBS_AVAILABLE)
    message(FATAL_ERROR "routing Linux mode requires the media_kit_libs_linux package")
  endif()
  foreach(_input MEDIA_KIT_LINUX_NATIVE_ROOT MEDIA_KIT_LINUX_NATIVE_RECEIPT MEDIA_KIT_LINUX_NATIVE_APP_ROOT MEDIA_KIT_LINUX_NATIVE_APP_SHA MEDIA_KIT_LINUX_NATIVE_MEDIA_KIT_SHA)
    if(NOT DEFINED ${_input} OR "${${_input}}" STREQUAL "")
      message(FATAL_ERROR "routing Linux mode requires ${_input}")
    endif()
    if(_input MATCHES "_SHA$")
      string(LENGTH "${${_input}}" _routing_sha_length)
      if(NOT _routing_sha_length EQUAL 40 OR NOT "${${_input}}" MATCHES "^[0-9a-f]+$")
        message(FATAL_ERROR "routing Linux ${_input} must be a lowercase Git SHA")
      endif()
    elseif(NOT IS_ABSOLUTE "${${_input}}" OR NOT "${${_input}}" MATCHES "^[A-Za-z0-9_./+-]+$")
      message(FATAL_ERROR "routing Linux ${_input} must be absolute and use safe path characters")
    endif()
  endforeach()
  if(NOT IS_DIRECTORY "${MEDIA_KIT_LINUX_NATIVE_ROOT}" OR NOT EXISTS "${MEDIA_KIT_LINUX_NATIVE_RECEIPT}" OR NOT IS_DIRECTORY "${MEDIA_KIT_LINUX_NATIVE_APP_ROOT}")
    message(FATAL_ERROR "routing Linux native root, receipt, or trusted App root is missing")
  endif()
  find_program(ROUTING_PYTHON3 NAMES python3)
  find_program(ROUTING_READELF NAMES readelf)
  if(NOT ROUTING_PYTHON3 OR NOT ROUTING_READELF)
    message(FATAL_ERROR "routing Linux native verification requires python3 and readelf")
  endif()
  get_filename_component(MEDIA_KIT_LINUX_NATIVE_MEDIA_KIT_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." REALPATH)
  if(NOT "${MEDIA_KIT_LINUX_NATIVE_MEDIA_KIT_ROOT}" MATCHES "^[A-Za-z0-9_./+-]+$")
    message(FATAL_ERROR "media-kit source root contains unsafe path characters")
  endif()
  set(_routing_verifier "${CMAKE_CURRENT_SOURCE_DIR}/verify_routing_linux_native_local.py")
  if(NOT EXISTS "${_routing_verifier}")
    message(FATAL_ERROR "trusted media-kit Linux native preflight is missing")
  endif()
  set(_routing_data "-")
  execute_process(
    COMMAND "${ROUTING_PYTHON3}" "${_routing_verifier}"
      --app-root "${MEDIA_KIT_LINUX_NATIVE_APP_ROOT}"
      --media-kit-root "${MEDIA_KIT_LINUX_NATIVE_MEDIA_KIT_ROOT}"
      --expected-app-sha "${MEDIA_KIT_LINUX_NATIVE_APP_SHA}"
      --expected-media-kit-sha "${MEDIA_KIT_LINUX_NATIVE_MEDIA_KIT_SHA}"
      --root "${MEDIA_KIT_LINUX_NATIVE_ROOT}"
      --receipt "${MEDIA_KIT_LINUX_NATIVE_RECEIPT}"
      --readelf "${ROUTING_READELF}" --local-input --write-cmake "${_routing_data}"
    RESULT_VARIABLE _routing_verify_result
    OUTPUT_VARIABLE _routing_data_lines
    ERROR_VARIABLE _routing_verify_stderr
  )
  if(NOT _routing_verify_result EQUAL 0)
    message(FATAL_ERROR "routing Linux native verification failed: ${_routing_data_lines}${_routing_verify_stderr}")
  endif()
  string(REGEX REPLACE "\n$" "" _routing_data_lines "${_routing_data_lines}")
  string(REPLACE "\n" ";" _routing_lines "${_routing_data_lines}")
  set(_routing_schema_count 0)
  set(_routing_libmpv_count 0)
  set(_routing_include_count 0)
  foreach(_line IN LISTS _routing_lines)
    if(_line MATCHES "^schema=1$")
      math(EXPR _routing_schema_count "${_routing_schema_count} + 1")
    elseif(_line MATCHES "^libmpv=([A-Za-z0-9_./+-]+)$")
      math(EXPR _routing_libmpv_count "${_routing_libmpv_count} + 1")
      set(_routing_libmpv "${CMAKE_MATCH_1}")
    elseif(_line MATCHES "^include=([A-Za-z0-9_./+-]+)$")
      math(EXPR _routing_include_count "${_routing_include_count} + 1")
      set(_routing_include "${CMAKE_MATCH_1}")
    elseif(_line MATCHES "^bundle=([A-Za-z0-9_./+-]+)$")
      list(APPEND LIBMPV_BUNDLE_FILES "${CMAKE_MATCH_1}")
    else()
      message(FATAL_ERROR "routing Linux verifier emitted unknown or unsafe CMake data")
    endif()
  endforeach()
  if(NOT _routing_schema_count EQUAL 1 OR NOT _routing_libmpv_count EQUAL 1 OR NOT _routing_include_count EQUAL 1 OR NOT LIBMPV_BUNDLE_FILES)
    message(FATAL_ERROR "routing Linux verifier emitted incomplete CMake data")
  endif()
  set(LIBMPV_PATH "${MEDIA_KIT_LINUX_NATIVE_ROOT}/lib")
  set(LIBMPV_HEADER_UNZIP_DIR "${MEDIA_KIT_LINUX_NATIVE_ROOT}/include")
  if(NOT "${_routing_libmpv}" STREQUAL "${LIBMPV_PATH}/libmpv.so.2" OR NOT "${_routing_include}" STREQUAL "${LIBMPV_HEADER_UNZIP_DIR}")
    message(FATAL_ERROR "routing Linux verifier output escaped the accepted payload layout")
  endif()
elseif(_routing_native_inputs_set)
  message(FATAL_ERROR "Linux native root/receipt/App inputs require MEDIA_KIT_ROUTING_MODE=ON")
else()
if(ARCH_NAME STREQUAL "x86_64")
  set(LIBMPV_ZIP_URL "https://github.com/Predidit/libmpv-linux-build/releases/download/20260810/libmpv_x86_64.zip")
  set(LIBMPV_ZIP_SHA256 "45922100e5240bf69a72fa2ae140d5b54e1ed03993a8a3746dc798e3ae8ad6e4")
  set(LIBMPV_HEADER_ZIP_URL "https://github.com/Predidit/libmpv-linux-build/releases/download/20260810/libmpv_x86_64_header.zip")
  set(LIBMPV_HEADER_ZIP_SHA256 "c654ee0145167694c7ab55c02810d59b5e73e09c5404b32c0b037b53e42c164d")
elseif(ARCH_NAME STREQUAL "aarch64")
  set(LIBMPV_ZIP_URL "https://github.com/Predidit/libmpv-linux-build/releases/download/20260810/libmpv_aarch64.zip")
  set(LIBMPV_ZIP_SHA256 "da0609556e2864dbe828102972edea96173a4be1ad1427a7493942dccb039b9f")
  set(LIBMPV_HEADER_ZIP_URL "https://github.com/Predidit/libmpv-linux-build/releases/download/20260810/libmpv_aarch64_header.zip")
  set(LIBMPV_HEADER_ZIP_SHA256 "1333f1717bd2449bd99ffdf3fd4653bdf919c4113d0b49f54f8dbd94a8dc678c")
endif()

set(LIBMPV_ZIP_PATH "${CMAKE_BINARY_DIR}/libmpv_${ARCH_NAME}.zip")
set(LIBMPV_UNZIP_DIR "${CMAKE_BINARY_DIR}/mpv")

make_directory("${LIBMPV_UNZIP_DIR}") 
message(STATUS "create libmpv unzip directory ${LIBMPV_UNZIP_DIR}")

message(STATUS "downloading libmpv from ${LIBMPV_ZIP_URL} to ${LIBMPV_ZIP_PATH}")
file(DOWNLOAD ${LIBMPV_ZIP_URL} ${LIBMPV_ZIP_PATH} SHOW_PROGRESS STATUS download_status)

list(GET download_status 0 download_status_code)
if(NOT download_status_code EQUAL 0)
  message(FATAL_ERROR "libmpv download failed. err: ${download_status_code}")
else()
  message(STATUS "libmpv download completed.")
endif()

message(STATUS "Verifying SHA256 checksum for ${LIBMPV_ZIP_PATH}")
file(SHA256 ${LIBMPV_ZIP_PATH} computed_sha256)
if(NOT computed_sha256 STREQUAL "${LIBMPV_ZIP_SHA256}")
  message(FATAL_ERROR "SHA256 checksum mismatch! Expected: ${LIBMPV_ZIP_SHA256}, Got: ${computed_sha256}")
else()
  message(STATUS "SHA256 checksum verification passed.")
endif()

message(STATUS "unzip libmpv to ${LIBMPV_UNZIP_DIR}")
execute_process(
  COMMAND unzip -o -q ${LIBMPV_ZIP_PATH} -d ${LIBMPV_UNZIP_DIR}
  WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
  RESULT_VARIABLE unzip_result
)

if(NOT unzip_result EQUAL 0)
  message(FATAL_ERROR "unzip libmpv failed, err: ${unzip_result}")
else()
  message(STATUS "unzip libmpv success.")
endif()

set(LIBMPV_PATH "${LIBMPV_UNZIP_DIR}")

if(EXISTS "${LIBMPV_PATH}/libmpv.so.2")
  message(STATUS "libmpv.so.2 founded ${LIBMPV_PATH}/libmpv.so.2")
else()
  message(FATAL_ERROR "libmpv.so.2 not founded ${LIBMPV_PATH}")
endif()

set(LIBMPV_HEADER_ZIP_PATH "${CMAKE_BINARY_DIR}/libmpv_${ARCH_NAME}_header.zip")
set(LIBMPV_HEADER_UNZIP_DIR "${CMAKE_BINARY_DIR}/mpv/include")

message(STATUS "downloading libmpv header from ${LIBMPV_HEADER_ZIP_URL} to ${LIBMPV_HEADER_ZIP_PATH}")
file(DOWNLOAD ${LIBMPV_HEADER_ZIP_URL} ${LIBMPV_HEADER_ZIP_PATH} SHOW_PROGRESS STATUS download_status)

list(GET download_status 0 download_status_code)
if(NOT download_status_code EQUAL 0)
  message(FATAL_ERROR "libmpv header download failed. err: ${download_status_code}")
else()
  message(STATUS "libmpv header download completed.")
endif()

message(STATUS "Verifying SHA256 checksum for ${LIBMPV_HEADER_ZIP_PATH}")
file(SHA256 ${LIBMPV_HEADER_ZIP_PATH} computed_header_sha256)
if(NOT computed_header_sha256 STREQUAL "${LIBMPV_HEADER_ZIP_SHA256}")
  message(FATAL_ERROR "SHA256 checksum mismatch! Expected: ${LIBMPV_HEADER_ZIP_SHA256}, Got: ${computed_header_sha256}")
else()
  message(STATUS "SHA256 checksum verification passed.")
endif()

message(STATUS "unzip libmpv header to ${LIBMPV_HEADER_UNZIP_DIR}")
execute_process(
  COMMAND unzip -o -q ${LIBMPV_HEADER_ZIP_PATH} -d ${LIBMPV_HEADER_UNZIP_DIR}
  RESULT_VARIABLE unzip_result
)

if(NOT unzip_result EQUAL 0)
  message(FATAL_ERROR "unzip libmpv header failed, err: ${unzip_result}")
else()
  message(STATUS "unzip libmpv header success.")
endif()

endif()

if(MEDIA_KIT_LIBS_AVAILABLE)
  add_library(
    ${PLUGIN_NAME} SHARED
    "media_kit_video_plugin.cc"
    "texture_gl.cc"
    "texture_sw.cc"
    "video_output_manager.cc"
    "video_output.cc"
    "wayland_native_surface_backend.cc"
    "gl_render_thread.cc"
    "utils.cc"
  )

  # add runpath, shared libs of a release bundle is in lib dir, plugin must add $ORIGIN to runpath to find libmpv
  target_link_options(${PLUGIN_NAME} PRIVATE -Wl,--enable-new-dtags -Wl,-z,origin)
  set_target_properties(${PLUGIN_NAME} PROPERTIES 
  BUILD_WITH_INSTALL_RPATH TRUE
  INSTALL_RPATH "$ORIGIN:$ORIGIN/lib"
  INSTALL_RPATH_USE_LINK_PATH TRUE)

  add_library(
     libmpv SHARED IMPORTED
  )

  apply_standard_settings(${PLUGIN_NAME})

  find_package(PkgConfig REQUIRED)
  pkg_check_modules(epoxy IMPORTED_TARGET epoxy)

  set_target_properties(
    ${PLUGIN_NAME} PROPERTIES
    CXX_VISIBILITY_PRESET hidden
  )

  set_target_properties(
    libmpv PROPERTIES
    IMPORTED_LOCATION "${LIBMPV_PATH}/libmpv.so.2"
  )

  target_compile_definitions(
    ${PLUGIN_NAME} PRIVATE
    FLUTTER_PLUGIN_IMPL
  )

  target_compile_options(${PLUGIN_NAME} PRIVATE "${epoxy_CFLAGS_OTHER}")

  target_include_directories(
    ${PLUGIN_NAME} INTERFACE
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
    "${epoxy_INCLUDE_DIRS}"
  )

  target_include_directories(
    ${PLUGIN_NAME} PRIVATE
    "${LIBMPV_HEADER_UNZIP_DIR}"
  )

  target_link_libraries(
    ${PLUGIN_NAME} PRIVATE
    flutter
    PkgConfig::GTK
    libmpv
    PkgConfig::epoxy
  )

else()
  message(NOTICE "media_kit: WARNING: package:media_kit_libs_*** not found.")

  add_library(
    ${PLUGIN_NAME} SHARED
    "media_kit_video_plugin.cc"
  )

  # add runpath, shared libs of a release bundle is in lib dir, plugin must add $ORIGIN to runpath to find libmpv
  target_link_options(${PLUGIN_NAME} PRIVATE -Wl,--enable-new-dtags -Wl,-z,origin)
  set_target_properties(${PLUGIN_NAME} PROPERTIES 
  BUILD_WITH_INSTALL_RPATH TRUE
  INSTALL_RPATH "$ORIGIN:$ORIGIN/lib"
  INSTALL_RPATH_USE_LINK_PATH TRUE)

  apply_standard_settings(${PLUGIN_NAME})

  set_target_properties(
    ${PLUGIN_NAME} PROPERTIES
    CXX_VISIBILITY_PRESET hidden
  )

  target_compile_definitions(
    ${PLUGIN_NAME} PRIVATE
    FLUTTER_PLUGIN_IMPL
    "MEDIA_KIT_LIBS_NOT_FOUND=1"
  )

  target_include_directories(
    ${PLUGIN_NAME} INTERFACE
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
  )

  target_link_libraries(
    ${PLUGIN_NAME} PRIVATE
    flutter
    PkgConfig::GTK
  )
endif()

# The reviewed Linux bundle places the plugin and all accepted DSOs side by
# side in bundle/lib. Do not let CMake append acquisition/build paths to its
# runtime search path when using verified external inputs.
if(MEDIA_KIT_ROUTING_MODE OR MEDIA_KIT_EXTERNAL_NATIVE_PACKAGE)
  set_target_properties(${PLUGIN_NAME} PROPERTIES
    INSTALL_RPATH "$ORIGIN"
    INSTALL_RPATH_USE_LINK_PATH FALSE)
endif()

message(STATUS "create libmpv install directory ${CMAKE_BINARY_DIR}/mpv")
file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/mpv")

if(MEDIA_KIT_ROUTING_MODE)
  set(_routing_postbuild_result "${CMAKE_BINARY_DIR}/routing-linux-native-plugin.json")
  add_custom_command(TARGET ${PLUGIN_NAME} POST_BUILD
    COMMAND "${ROUTING_PYTHON3}" "${_routing_verifier}"
      --postbuild-plugin "$<TARGET_FILE:${PLUGIN_NAME}>"
      --app-root "${MEDIA_KIT_LINUX_NATIVE_APP_ROOT}"
      --media-kit-root "${MEDIA_KIT_LINUX_NATIVE_MEDIA_KIT_ROOT}"
      --expected-app-sha "${MEDIA_KIT_LINUX_NATIVE_APP_SHA}"
      --expected-media-kit-sha "${MEDIA_KIT_LINUX_NATIVE_MEDIA_KIT_SHA}"
      --root "${MEDIA_KIT_LINUX_NATIVE_ROOT}"
      --receipt "${MEDIA_KIT_LINUX_NATIVE_RECEIPT}"
      --result "${_routing_postbuild_result}"
      --readelf "${ROUTING_READELF}"
    VERBATIM
  )
endif()

# install(FILES "${LIBMPV_PATH}/libmpv.so.2" DESTINATION lib)

if(MEDIA_KIT_ROUTING_MODE OR MEDIA_KIT_EXTERNAL_NATIVE_PACKAGE)
  set(media_kit_video_bundled_libraries ${LIBMPV_BUNDLE_FILES} PARENT_SCOPE)
else()
  set(media_kit_video_bundled_libraries "${LIBMPV_PATH}/libmpv.so.2" PARENT_SCOPE)
endif()
