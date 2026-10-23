# Included only for an explicit native package. The caller sets the platform
# and normalized target architecture before including this trusted helper.
if(NOT MEDIA_KIT_PACKAGE_PLATFORM OR NOT MEDIA_KIT_PACKAGE_ARCHITECTURE)
  message(FATAL_ERROR "Native package consumer requires a platform and architecture")
endif()

if(NOT "$ENV{MEDIA_KIT_NATIVE_PACKAGE_PYTHON}" STREQUAL "")
  set(_native_package_python "$ENV{MEDIA_KIT_NATIVE_PACKAGE_PYTHON}")
else()
  find_program(_native_package_python NAMES python3 python)
endif()
if(NOT _native_package_python)
  message(FATAL_ERROR "Explicit native packages require Python 3")
endif()

set(_native_package_data "${CMAKE_CURRENT_BINARY_DIR}/media-kit-native-package.cmake")
execute_process(
  COMMAND "${_native_package_python}" "${CMAKE_CURRENT_LIST_DIR}/package.py"
    consume --platform "${MEDIA_KIT_PACKAGE_PLATFORM}"
    --architecture "${MEDIA_KIT_PACKAGE_ARCHITECTURE}"
    --cmake "${_native_package_data}"
  RESULT_VARIABLE _native_package_status
  OUTPUT_VARIABLE _native_package_stdout
  ERROR_VARIABLE _native_package_stderr
)
if(NOT _native_package_status EQUAL 0)
  message(FATAL_ERROR "Explicit native package verification failed: ${_native_package_stderr}${_native_package_stdout}")
endif()
include("${_native_package_data}")
message(STATUS "Using verified ${MEDIA_KIT_PACKAGE_PLATFORM}/${MEDIA_KIT_PACKAGE_ARCHITECTURE} native package ${MEDIA_KIT_PACKAGE_MANIFEST_SHA256}")
