# Run one OpenSSL make target. Failures are fatal and are never hidden by
# silently removing requested algorithms or changing the configuration.
foreach(_v OSSL_BUILD_DIR OSSL_MAKE)
  if(NOT DEFINED ${_v} OR "${${_v}}" STREQUAL "")
    message(FATAL_ERROR "OsslBuild: required variable ${_v} is not set")
  endif()
endforeach()

# The normal build carries the complete configuration definitions. The test
# target omits OSSL_PERL and therefore runs only the already-built test target.
if(DEFINED OSSL_PERL)
  include("${OSSL_SOURCE_DIR}/cmake/OsslConfigure.cmake")
endif()

separate_arguments(_make_args NATIVE_COMMAND "${OSSL_MAKE_ARGS}")
set(_target_args)
if(DEFINED OSSL_MAKE_TARGET AND NOT OSSL_MAKE_TARGET STREQUAL "")
  list(APPEND _target_args "${OSSL_MAKE_TARGET}")
endif()
if(NOT DEFINED OSSL_LOG OR OSSL_LOG STREQUAL "")
  set(OSSL_LOG "${OSSL_BUILD_DIR}/openssl-build.log")
endif()

execute_process(
  COMMAND "${OSSL_MAKE}" ${_make_args} ${_target_args}
  WORKING_DIRECTORY "${OSSL_BUILD_DIR}"
  RESULT_VARIABLE _rc
  OUTPUT_VARIABLE _out
  ERROR_VARIABLE  _err)
file(WRITE "${OSSL_LOG}" "${_out}\n${_err}")

if(NOT _rc EQUAL 0)
  message(FATAL_ERROR "OsslBuild: make failed (${_rc}), see ${OSSL_LOG}")
endif()
message(STATUS "OsslBuild: succeeded; log: ${OSSL_LOG}")
