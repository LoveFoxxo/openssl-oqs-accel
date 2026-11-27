# Build-time OpenSSL configuration. Tools and dependencies are built before
# this script; every requested option is explicit and configuration failures
# are fatal rather than silently weakening the result.
foreach(_v OSSL_SOURCE_DIR OSSL_PERL OSSL_BUILD_DIR)
  if(NOT DEFINED ${_v} OR "${${_v}}" STREQUAL "")
    message(FATAL_ERROR "OsslConfigure: required variable ${_v} is not set")
  endif()
endforeach()
if(NOT EXISTS "${OSSL_PERL}")
  message(FATAL_ERROR "OsslConfigure: perl not found at ${OSSL_PERL}")
endif()
file(MAKE_DIRECTORY "${OSSL_BUILD_DIR}")

separate_arguments(_base_args NATIVE_COMMAND "${OSSL_BASE_ARGS}")
separate_arguments(_features NATIVE_COMMAND "${OSSL_FEATURES}")
separate_arguments(_user_args NATIVE_COMMAND "${OSSL_USER_ARGS}")
set(_target_args)
if(DEFINED OSSL_TARGET AND NOT OSSL_TARGET STREQUAL "")
  list(APPEND _target_args "${OSSL_TARGET}")
endif()
set(_final ${_target_args} ${_base_args} ${_features} ${_user_args})
string(REPLACE ";" " " _final_str "${_final}")
file(WRITE "${OSSL_BUILD_DIR}/configure-args.txt" "${_final_str}\n")
message(STATUS "OsslConfigure: perl Configure ${_final_str}")

# Configure replaces a target's built-in flags when these environment variables
# are present. Preserve the MSVC defaults when dependency paths force us to set
# LDFLAGS, and preserve all caller-supplied environment flags.
set(_ossl_ldflags "$ENV{LDFLAGS}")
if(OSSL_MSVC_LDFLAGS)
  string(PREPEND _ossl_ldflags "/nologo /debug ")
  string(APPEND _ossl_ldflags " ${OSSL_MSVC_LDFLAGS}")
endif()
if(OSSL_OQS_LDFLAGS)
  string(APPEND _ossl_ldflags " ${OSSL_OQS_LDFLAGS}")
endif()
string(STRIP "${_ossl_ldflags}" _ossl_ldflags)
if(_ossl_ldflags)
  set(ENV{LDFLAGS} "${_ossl_ldflags}")
endif()

set(_ossl_cflags "$ENV{CFLAGS}")
if(OSSL_OQS_CFLAGS)
  string(APPEND _ossl_cflags " ${OSSL_OQS_CFLAGS}")
endif()
string(STRIP "${_ossl_cflags}" _ossl_cflags)
if(_ossl_cflags)
  set(ENV{CFLAGS} "${_ossl_cflags}")
endif()

set(_ossl_ldlibs "$ENV{LDLIBS}")
if(OSSL_OQS_LDLIBS)
  string(APPEND _ossl_ldlibs " ${OSSL_OQS_LDLIBS}")
endif()
string(STRIP "${_ossl_ldlibs}" _ossl_ldlibs)
if(_ossl_ldlibs)
  set(ENV{LDLIBS} "${_ossl_ldlibs}")
endif()

# ExternalProject stamps are configuration-independent under a multi-config
# generator. Use a content fingerprint instead, so each Debug/Release directory
# reconfigures exactly when its effective inputs change.
file(SHA256 "${OSSL_SOURCE_DIR}/Configure" _configure_hash)
file(SHA256 "${OSSL_SOURCE_DIR}/configdata.pm.in" _configdata_hash)
string(SHA256 _fingerprint
  "${_final_str}\n${_ossl_ldflags}\n${_ossl_cflags}\n${_ossl_ldlibs}\n${OSSL_C_COMPILER}\n${OSSL_PERL}\n${_configure_hash}\n${_configdata_hash}")
set(_stamp "${OSSL_BUILD_DIR}/configure-fingerprint.txt")
set(_previous "")
if(EXISTS "${_stamp}")
  file(READ "${_stamp}" _previous)
  string(STRIP "${_previous}" _previous)
endif()
if(_previous STREQUAL _fingerprint
   AND EXISTS "${OSSL_BUILD_DIR}/configdata.pm"
   AND (EXISTS "${OSSL_BUILD_DIR}/makefile"
        OR EXISTS "${OSSL_BUILD_DIR}/Makefile"))
  message(STATUS "OsslConfigure: configuration unchanged")
  return()
endif()

execute_process(
  COMMAND "${OSSL_PERL}" "${OSSL_SOURCE_DIR}/Configure" ${_final}
  WORKING_DIRECTORY "${OSSL_BUILD_DIR}"
  RESULT_VARIABLE _rc
  OUTPUT_VARIABLE _out
  ERROR_VARIABLE  _err
  OUTPUT_STRIP_TRAILING_WHITESPACE
  ERROR_STRIP_TRAILING_WHITESPACE)
file(WRITE "${OSSL_BUILD_DIR}/openssl-configure.log" "${_out}\n${_err}\n")
if(NOT _rc EQUAL 0 OR "${_out}\n${_err}" MATCHES "Unsupported option|Cannot continue")
  file(REMOVE "${_stamp}")
  message(FATAL_ERROR
    "OsslConfigure: Configure failed (${_rc}); see ${OSSL_BUILD_DIR}/openssl-configure.log")
endif()
file(WRITE "${_stamp}" "${_fingerprint}\n")
