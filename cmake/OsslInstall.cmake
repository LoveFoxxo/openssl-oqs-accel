# Install software and, when built, the FIPS provider without pulling in docs.
foreach(_v OSSL_BUILD_DIR OSSL_MAKE)
  if(NOT DEFINED ${_v} OR "${${_v}}" STREQUAL "")
    message(FATAL_ERROR "OsslInstall: required variable ${_v} is not set")
  endif()
endforeach()
separate_arguments(_make_args NATIVE_COMMAND "${OSSL_MAKE_ARGS}")

execute_process(
  COMMAND "${OSSL_MAKE}" ${_make_args} install_sw
  WORKING_DIRECTORY "${OSSL_BUILD_DIR}"
  RESULT_VARIABLE _rc)
if(NOT _rc EQUAL 0)
  message(FATAL_ERROR "OsslInstall: install_sw failed with ${_rc}")
endif()

if(EXISTS "${OSSL_BUILD_DIR}/providers/fips.dll"
   OR EXISTS "${OSSL_BUILD_DIR}/providers/fips.so"
   OR EXISTS "${OSSL_BUILD_DIR}/providers/fips.dylib")
  execute_process(
    COMMAND "${OSSL_MAKE}" ${_make_args} install_fips
    WORKING_DIRECTORY "${OSSL_BUILD_DIR}"
    RESULT_VARIABLE _rc)
  if(NOT _rc EQUAL 0)
    message(FATAL_ERROR "OsslInstall: install_fips failed with ${_rc}")
  endif()
endif()
