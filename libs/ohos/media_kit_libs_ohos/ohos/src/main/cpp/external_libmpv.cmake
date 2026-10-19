# Optional current-build input. An explicit input NEVER falls back to a release.
# Both environment values must be supplied by the native build's receipt.
function(media_kit_ohos_external_libmpv archive_var sha_var external_var)
  set(${external_var} FALSE PARENT_SCOPE)
  if(NOT DEFINED ENV{MEDIA_KIT_OHOS_LIBMPV_ARCHIVE} AND
     NOT DEFINED ENV{MEDIA_KIT_OHOS_LIBMPV_SHA256})
    return()
  endif()
  set(archive "$ENV{MEDIA_KIT_OHOS_LIBMPV_ARCHIVE}")
  set(expected "$ENV{MEDIA_KIT_OHOS_LIBMPV_SHA256}")
  string(LENGTH "${expected}" digest_length)
  if("${archive}" STREQUAL "" OR NOT digest_length EQUAL 64 OR
     NOT "${expected}" MATCHES "^[0-9a-fA-F]+$")
    message(FATAL_ERROR "OHOS external libmpv requires an archive and a 64-digit SHA256")
  endif()
  if(NOT IS_ABSOLUTE "${archive}" OR "${archive}" MATCHES ";" OR
     NOT EXISTS "${archive}" OR IS_DIRECTORY "${archive}")
    message(FATAL_ERROR "OHOS external libmpv must be an existing absolute archive path")
  endif()
  get_filename_component(archive "${archive}" REALPATH)
  file(SHA256 "${archive}" actual)
  string(TOLOWER "${expected}" expected)
  if(NOT "${actual}" STREQUAL "${expected}")
    # Never delete or overwrite the caller's input on a mismatch.
    message(FATAL_ERROR "OHOS external libmpv SHA256 mismatch; refusing release fallback")
  endif()
  set(${archive_var} "${archive}" PARENT_SCOPE)
  set(${sha_var} "${actual}" PARENT_SCOPE)
  set(${external_var} TRUE PARENT_SCOPE)
  message(STATUS "OHOS current-build libmpv SHA256: ${actual}")
endfunction()
