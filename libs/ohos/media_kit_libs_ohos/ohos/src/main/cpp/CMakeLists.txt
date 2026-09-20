cmake_minimum_required(VERSION 3.15)

# ------------------------------------------------------------------------------
function(download_and_verify url sha locationForArchive)
  # Check if the archive exists.
  if(EXISTS "${locationForArchive}")
    file(SHA256 "${locationForArchive}" ARCHIVE_SHA)

    # If SHA256 doesn't match, delete the archive to download again.
    if(NOT sha STREQUAL ARCHIVE_SHA)
      file(REMOVE "${locationForArchive}")
      message(STATUS "SHA256 mismatch. File deleted.")
    endif()
  endif()

  # Download the archive if it doesn't exist.
  if(NOT EXISTS "${locationForArchive}")
    message(STATUS "Downloading archive from ${url}...")
    file(DOWNLOAD "${url}" "${locationForArchive}")
    message(STATUS "Downloaded archive to ${locationForArchive}.")

    # Verify SHA256 of the newly downloaded file.
    file(SHA256 "${locationForArchive}" ARCHIVE_SHA)

    if(sha STREQUAL ARCHIVE_SHA)
      message(STATUS "${locationForArchive} Verification successful.")
    else()
      message(FATAL_ERROR "${locationForArchive} Integrity check failed, please try to re-build project again.")
    endif()
  endif()
endfunction()

function(check_directory_exists_and_not_empty dir result_var)
  # Check if the directory exists
  if(EXISTS "${dir}")
    # Check if the directory is not empty
    file(GLOB dir_contents "${dir}/*")

    if(dir_contents)
      set(${result_var} TRUE PARENT_SCOPE)
    else()
      set(${result_var} FALSE PARENT_SCOPE)
      message(STATUS "Directory ${dir} exists but is empty!")
    endif()
  else()
    set(${result_var} FALSE PARENT_SCOPE)
    message(STATUS "Directory ${dir} does not exist!")
  endif()
endfunction()

# libmpv archive containing the pre-built shared libraries.
set(LIBMPV "libmpv_aarch64.zip")

# Download URL & SHA256 hash of the libmpv archive.
set(LIBMPV_URL "https://github.com/Goodwu/libmpv-ohos-build/releases/download/20260920/${LIBMPV}")
# This archive contains the OHOS color-contract and output-mapping diagnostics
# used by the current real-device investigation.  Keep the checksum strict:
# replacing the archive without updating this provenance record must fail.
set(LIBMPV_SHA "29b8bd4de54bb61c6fbb549022af5d9082d7b057a5901a1d388597ff15114191")

# Download location of the libmpv archive.
set(LIBMPV_ARCHIVE "${CMAKE_CURRENT_SOURCE_DIR}/${LIBMPV}")
set(LIBMPV_SRC "${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/arm64-v8a/")

download_and_verify(
  ${LIBMPV_URL}
  ${LIBMPV_SHA}
  ${LIBMPV_ARCHIVE}
)

# The native archive is consumed through the shared libs/arm64-v8a directory.
# Do not remove that directory during configure: another CMake/HAP invocation
# may be reading it, and an interrupted configure would leave it empty. Make
# extraction an explicit build step with an archive dependency instead.
set(LIBMPV_EXTRACT_STAMP "${CMAKE_CURRENT_BINARY_DIR}/libmpv-extract.stamp")
# ------------------------------------------------------------------------------

project(mediakit_libs_ohos)

set(LIBS
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/arm64-v8a/libmpv.so.2)

add_library(mediakit_ohos_hdr SHARED hdr_output.cc)
target_link_libraries(mediakit_ohos_hdr PUBLIC native_window)

add_custom_command(
  OUTPUT "${LIBMPV_EXTRACT_STAMP}"
  COMMAND "${CMAKE_COMMAND}" -E rm -rf "${LIBMPV_SRC}"
  COMMAND "${CMAKE_COMMAND}" -E make_directory "${LIBMPV_SRC}"
  COMMAND "${CMAKE_COMMAND}" -E chdir "${LIBMPV_SRC}"
          "${CMAKE_COMMAND}" -E tar -xf "${LIBMPV_ARCHIVE}"
  COMMAND "${CMAKE_COMMAND}" -E touch "${LIBMPV_EXTRACT_STAMP}"
  DEPENDS "${LIBMPV_ARCHIVE}"
  VERBATIM
)
add_custom_target("LIBMPV_EXTRACT" ALL DEPENDS "${LIBMPV_EXTRACT_STAMP}")
add_dependencies(mediakit_ohos_hdr "LIBMPV_EXTRACT")

link_libraries(DART_SHARED_LIB ${LIBS})
