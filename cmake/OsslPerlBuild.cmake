# Build Windows perl from a clean, source-revision-keyed archive in the build
# tree. This avoids stale Config.pm paths and all in-source build pollution.
foreach(_v OSSL_PERL_SRC OSSL_PERL_WORK OSSL_PERL_GIT OSSL_PERL_CCTYPE
           OSSL_PERL_ARCH OSSL_MAKE OSSL_TOOL_DIR)
  if(NOT DEFINED ${_v} OR "${${_v}}" STREQUAL "")
    message(FATAL_ERROR "OsslPerlBuild: required variable ${_v} is not set")
  endif()
endforeach()

execute_process(
  COMMAND "${OSSL_PERL_GIT}" -C "${OSSL_PERL_SRC}" rev-parse HEAD
  RESULT_VARIABLE _rc OUTPUT_VARIABLE _revision ERROR_VARIABLE _err
  OUTPUT_STRIP_TRAILING_WHITESPACE)
if(NOT _rc EQUAL 0)
  message(FATAL_ERROR "OsslPerlBuild: cannot read source revision: ${_err}")
endif()

set(_fingerprint "${_revision}|${OSSL_PERL_CCTYPE}|${OSSL_PERL_ARCH}|${OSSL_TOOL_DIR}")
set(_stamp "${OSSL_PERL_WORK}/build-fingerprint.txt")
set(_previous "")
if(EXISTS "${_stamp}")
  file(READ "${_stamp}" _previous)
  string(STRIP "${_previous}" _previous)
endif()
if(NOT _previous STREQUAL _fingerprint OR NOT EXISTS "${OSSL_PERL_WORK}/win32/Makefile")
  file(REMOVE_RECURSE "${OSSL_PERL_WORK}")
  file(MAKE_DIRECTORY "${OSSL_PERL_WORK}")
  set(_archive "${OSSL_PERL_WORK}.tar")
  file(REMOVE "${_archive}")
  execute_process(
    COMMAND "${OSSL_PERL_GIT}" -C "${OSSL_PERL_SRC}" archive
            --format=tar "--output=${_archive}" HEAD
    RESULT_VARIABLE _rc ERROR_VARIABLE _err)
  if(NOT _rc EQUAL 0)
    message(FATAL_ERROR "OsslPerlBuild: git archive failed: ${_err}")
  endif()
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E tar xf "${_archive}"
    WORKING_DIRECTORY "${OSSL_PERL_WORK}"
    RESULT_VARIABLE _rc ERROR_VARIABLE _err)
  file(REMOVE "${_archive}")
  if(NOT _rc EQUAL 0)
    message(FATAL_ERROR "OsslPerlBuild: archive extraction failed: ${_err}")
  endif()
  file(WRITE "${_stamp}" "${_fingerprint}\n")
endif()

if(OSSL_PERL_ARCH STREQUAL "x64")
  set(_perl_arch "PROCESSOR_ARCHITECTURE=AMD64" "WIN64=define")
elseif(OSSL_PERL_ARCH STREQUAL "arm64")
  set(_perl_arch "PROCESSOR_ARCHITECTURE=ARM64" "WIN64=define")
elseif(OSSL_PERL_ARCH STREQUAL "x86")
  set(_perl_arch "PROCESSOR_ARCHITECTURE=x86" "WIN64=undef")
else()
  message(FATAL_ERROR "OsslPerlBuild: unsupported architecture ${OSSL_PERL_ARCH}")
endif()

# vcvarsall may leave PROCESSOR_ARCHITECTURE=x86 in a cross-compilation shell.
# Pass the selected target explicitly so compiler and linker agree.
execute_process(
  COMMAND "${OSSL_MAKE}" "CCTYPE=${OSSL_PERL_CCTYPE}" ${_perl_arch}
          "INST_TOP=${OSSL_TOOL_DIR}"
  WORKING_DIRECTORY "${OSSL_PERL_WORK}/win32"
  RESULT_VARIABLE _rc OUTPUT_VARIABLE _out ERROR_VARIABLE _err)
file(WRITE "${OSSL_PERL_WORK}/build.log" "${_out}\n${_err}")
if(NOT _rc EQUAL 0)
  message(FATAL_ERROR "OsslPerlBuild: nmake failed (${_rc}); see ${OSSL_PERL_WORK}/build.log")
endif()
message(STATUS "OsslPerlBuild: built revision ${_revision}")
