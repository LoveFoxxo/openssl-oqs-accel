# Shared platform detection, isolated prefixes and command environments.
include_guard(GLOBAL)

set(OSSL_STAGE_DIR "${CMAKE_BINARY_DIR}/stage" CACHE PATH
    "Base install prefix for OpenSSL and build tools")
set(OSSL_DEPS_DIR "${CMAKE_BINARY_DIR}/deps" CACHE PATH
    "Base install prefix for CMake-built dependencies")
set(OSSL_TOOL_DIR "${OSSL_STAGE_DIR}/tools" CACHE PATH
    "Prefix for tools built from source (perl, nasm)")
file(MAKE_DIRECTORY "${OSSL_STAGE_DIR}" "${OSSL_DEPS_DIR}" "${OSSL_TOOL_DIR}")

if(CMAKE_CONFIGURATION_TYPES)
  set(OSSL_DEP_PREFIX "${OSSL_DEPS_DIR}/$<CONFIG>")
  set(OSSL_INSTALL_DIR "${OSSL_STAGE_DIR}/$<CONFIG>")
else()
  set(OSSL_DEP_PREFIX "${OSSL_DEPS_DIR}")
  set(OSSL_INSTALL_DIR "${OSSL_STAGE_DIR}")
endif()
set(OSSL_OPENSSL_BINARY_DIR "${CMAKE_BINARY_DIR}/openssl/$<CONFIG>")

if(CMAKE_SIZEOF_VOID_P EQUAL 8)
  set(OSSL_BITS 64)
else()
  set(OSSL_BITS 32)
endif()

set(OSSL_VCVARSALL "" CACHE FILEPATH "vcvarsall.bat; auto-detected when empty")
function(ossl_find_vcvarsall out_var)
  if(OSSL_VCVARSALL AND EXISTS "${OSSL_VCVARSALL}")
    set(${out_var} "${OSSL_VCVARSALL}" PARENT_SCOPE)
    return()
  endif()
  set(_found "")
  # The selected compiler is authoritative even in minimal shells where the
  # ProgramFiles environment variables are absent.
  string(REGEX MATCH "^(.+/VC)/Tools/MSVC/" _vc_match "${CMAKE_C_COMPILER}")
  if(_vc_match AND EXISTS "${CMAKE_MATCH_1}/Auxiliary/Build/vcvarsall.bat")
    set(_found "${CMAKE_MATCH_1}/Auxiliary/Build/vcvarsall.bat")
  endif()
  if(_found)
    set(${out_var} "${_found}" PARENT_SCOPE)
    return()
  endif()
  find_program(_vswhere NAMES vswhere
    HINTS "$ENV{ProgramFiles\(x86\)}/Microsoft Visual Studio/Installer"
          "$ENV{ProgramFiles}/Microsoft Visual Studio/Installer"
          "C:/Program Files (x86)/Microsoft Visual Studio/Installer")
  if(_vswhere)
    execute_process(COMMAND "${_vswhere}" -latest -products * -property installationPath
                    OUTPUT_VARIABLE _vs OUTPUT_STRIP_TRAILING_WHITESPACE
                    ERROR_QUIET)
    string(STRIP "${_vs}" _vs)
    if(EXISTS "${_vs}/VC/Auxiliary/Build/vcvarsall.bat")
      set(_found "${_vs}/VC/Auxiliary/Build/vcvarsall.bat")
    endif()
  endif()
  if(NOT _found)
    foreach(_c "$ENV{VSINSTALLDIR}VC/Auxiliary/Build/vcvarsall.bat"
               "$ENV{VCINSTALLDIR}../../Auxiliary/Build/vcvarsall.bat")
      file(TO_CMAKE_PATH "${_c}" _c2)
      if(EXISTS "${_c2}")
        set(_found "${_c2}")
        break()
      endif()
    endforeach()
  endif()
  set(${out_var} "${_found}" PARENT_SCOPE)
endfunction()

if(CMAKE_VS_PLATFORM_NAME)
  string(TOLOWER "${CMAKE_VS_PLATFORM_NAME}" OSSL_MSVC_ARCH)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(ARM64|aarch64)")
  set(OSSL_MSVC_ARCH "arm64")
elseif(OSSL_BITS EQUAL 64)
  set(OSSL_MSVC_ARCH "x64")
else()
  set(OSSL_MSVC_ARCH "x86")
endif()
if(OSSL_MSVC_ARCH STREQUAL "win32")
  set(OSSL_MSVC_ARCH "x86")
endif()
if(MSVC)
  ossl_find_vcvarsall(OSSL_VCVARSALL_BAT)
  if(NOT OSSL_VCVARSALL_BAT)
    message(FATAL_ERROR "vcvarsall.bat was not found; set OSSL_VCVARSALL explicitly")
  endif()
endif()

# A single generic wrapper preserves generator expressions in the actual
# command arguments. The previous per-command wrappers froze those expressions
# into batch files before CMake could expand them.
function(ossl_wrap out_var)
  if(MSVC)
    set(_f "${CMAKE_BINARY_DIR}/ossl-run-${OSSL_MSVC_ARCH}.cmd")
    file(WRITE "${_f}"
"@echo off\r
call \"${OSSL_VCVARSALL_BAT}\" ${OSSL_MSVC_ARCH} >nul\r
if errorlevel 1 exit /b %errorlevel%\r
set \"PATH=${OSSL_TOOL_DIR}/bin;${OSSL_STAGE_DIR}/bin;%PATH%\"\r
%*\r
")
    set(${out_var} cmd /d /c "${_f}" ${ARGN} PARENT_SCOPE)
  elseif(WIN32)
    set(${out_var}
        "${CMAKE_COMMAND}" -E env "PATH=${OSSL_TOOL_DIR}/bin;${OSSL_STAGE_DIR}/bin;$ENV{PATH}"
        ${ARGN} PARENT_SCOPE)
  else()
    set(${out_var}
        "${CMAKE_COMMAND}" -E env "PATH=${OSSL_TOOL_DIR}/bin:${OSSL_STAGE_DIR}/bin:$ENV{PATH}"
        ${ARGN} PARENT_SCOPE)
  endif()
endfunction()

set(OSSL_JOBS 8 CACHE STRING "Parallel jobs used for dependency builds")
if(NOT OSSL_JOBS MATCHES "^[1-9][0-9]*$")
  message(FATAL_ERROR "OSSL_JOBS must be a positive integer")
endif()
if(WIN32)
  set(OSSL_OPENSSL_MAKE "nmake" CACHE STRING "Make tool for the OpenSSL build (nmake/jom)")
  set(OSSL_OPENSSL_MAKE_ARGS "" CACHE STRING "Extra flags forwarded to the make tool")
else()
  set(OSSL_OPENSSL_MAKE "make" CACHE STRING "Make tool for the OpenSSL build")
  set(OSSL_OPENSSL_MAKE_ARGS "-j${OSSL_JOBS}" CACHE STRING "Extra flags forwarded to the make tool")
endif()
option(OSSL_VERBOSE "Pass VERBOSE=1 to the OpenSSL build step" OFF)
if(OSSL_VERBOSE)
  string(APPEND OSSL_OPENSSL_MAKE_ARGS " VERBOSE=1")
  string(STRIP "${OSSL_OPENSSL_MAKE_ARGS}" OSSL_OPENSSL_MAKE_ARGS)
endif()

# Remove wrappers left by older revisions; the current wrapper is deterministic.
file(GLOB _ossl_stale_wrappers "${CMAKE_BINARY_DIR}/ossl-run-*.cmd")
foreach(_f IN LISTS _ossl_stale_wrappers)
  if(NOT _f STREQUAL "${CMAKE_BINARY_DIR}/ossl-run-${OSSL_MSVC_ARCH}.cmd")
    file(REMOVE "${_f}")
  endif()
endforeach()
unset(_ossl_stale_wrappers)
