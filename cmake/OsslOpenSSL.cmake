# The OpenSSL stage: CMake owns configuration, dependencies, incremental builds,
# installation and optional tests. OpenSSL's upstream Configure generates the
# platform makefile; it is not replaced or reimplemented here.
include_guard(GLOBAL)
include(ExternalProject)

option(OSSL_BUILD_SHARED "Build shared libcrypto/libssl in addition to static libraries" ON)
option(OSSL_ENABLE_TESTS "Build OpenSSL tests and expose the ossl-check target" OFF)
option(OSSL_ENABLE_DOCS  "Build the OpenSSL documentation" OFF)
set(OSSL_CONFIGURE_TARGET "" CACHE STRING
    "Configure target (VC-WIN64A, linux-x86_64, ...); auto when empty")

if(OSSL_CONFIGURE_TARGET STREQUAL "")
  if(WIN32)
    if(OSSL_MSVC_ARCH STREQUAL "arm64")
      set(OSSL_CONFIGURE_TARGET "VC-ARM64")
    elseif(OSSL_BITS EQUAL 64)
      set(OSSL_CONFIGURE_TARGET "VC-WIN64A")
    else()
      set(OSSL_CONFIGURE_TARGET "VC-WIN32")
    endif()
  elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(arm64|aarch64|ARM64)$")
      set(OSSL_CONFIGURE_TARGET "darwin64-arm64-cc")
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|AMD64)$")
      set(OSSL_CONFIGURE_TARGET "darwin64-x86_64-cc")
    else()
      message(FATAL_ERROR "Unsupported macOS architecture; set OSSL_CONFIGURE_TARGET")
    endif()
  endif()
endif()

set(OSSL_BASE_ARGS
    "--prefix=${OSSL_INSTALL_DIR}"
    "--openssldir=${OSSL_INSTALL_DIR}/ssl"
    "--libdir=lib")
if(NOT OSSL_BUILD_SHARED)
  list(APPEND OSSL_BASE_ARGS "no-shared")
endif()
if(NOT OSSL_ENABLE_TESTS)
  list(APPEND OSSL_BASE_ARGS "no-tests")
endif()
if(NOT OSSL_ENABLE_DOCS)
  list(APPEND OSSL_BASE_ARGS "no-docs")
endif()
if(NOT OSSL_ENABLE_ASM)
  list(APPEND OSSL_BASE_ARGS "no-asm")
endif()

# Explicit, reviewable features. Weak/deprecated ciphers, legacy providers and
# TLS compression are intentionally not enabled by a speculative probe.
set(OSSL_FEATURES
    "enable-cmp;enable-fips;enable-rfc3779;enable-thread-pool;enable-quic"
    CACHE STRING "Semicolon-separated OpenSSL feature arguments")

if(MSVC)
  set(_ossl_libpaths)
else()
  set(_ossl_libpaths "")
endif()
if(OSSL_WITH_ZLIB)
  list(APPEND OSSL_BASE_ARGS enable-zlib
       "--with-zlib-include=${OSSL_ZLIB_INCLUDE}")
  if(MSVC)
    list(APPEND _ossl_libpaths "${OSSL_ZLIB_LIB}")
    list(APPEND OSSL_BASE_ARGS "--with-zlib-lib=libzs.lib")
  else()
    list(APPEND OSSL_BASE_ARGS "--with-zlib-lib=${OSSL_ZLIB_LIB}")
  endif()
endif()
if(OSSL_WITH_ZSTD)
  list(APPEND OSSL_BASE_ARGS enable-zstd
       "--with-zstd-include=${OSSL_ZSTD_INCLUDE}")
  if(MSVC)
    list(APPEND _ossl_libpaths "${OSSL_ZSTD_LIB}")
    list(APPEND OSSL_BASE_ARGS "--with-zstd-lib=zstd_static.lib")
  else()
    list(APPEND OSSL_BASE_ARGS "--with-zstd-lib=${OSSL_ZSTD_LIB}")
  endif()
endif()
if(OSSL_WITH_BROTLI)
  list(APPEND OSSL_BASE_ARGS enable-brotli
       "--with-brotli-include=${OSSL_BROTLI_INCLUDE}")
  if(MSVC)
    list(APPEND _ossl_libpaths "${OSSL_BROTLI_LIB}")
  else()
    list(APPEND OSSL_BASE_ARGS "--with-brotli-lib=${OSSL_BROTLI_LIB}")
  endif()
endif()

set(OSSL_MSVC_LIBFLAGS "")
if(MSVC AND _ossl_libpaths)
  list(REMOVE_DUPLICATES _ossl_libpaths)
  foreach(_lp IN LISTS _ossl_libpaths)
    string(REPLACE "\\" "/" _lp "${_lp}")
    string(APPEND OSSL_MSVC_LIBFLAGS " /LIBPATH:${_lp}")
  endforeach()
  string(STRIP "${OSSL_MSVC_LIBFLAGS}" OSSL_MSVC_LIBFLAGS)
endif()

option(OSSL_WITH_OQS_ACCEL
  "Use liboqs ML-KEM after deterministic self-tests and per-operation timing" ON)
set(OSSL_OQS_CFLAGS "")
set(OSSL_OQS_LDFLAGS "")
set(OSSL_OQS_LDLIBS "")
if(OSSL_WITH_OQS_ACCEL AND NOT OSSL_WITH_OQS)
  message(FATAL_ERROR
    "OSSL_WITH_OQS_ACCEL=ON requires OSSL_WITH_OQS=ON (or disable acceleration)")
endif()
if(OSSL_WITH_OQS_ACCEL)
  list(APPEND OSSL_BASE_ARGS "enable-oqs-accel")
  set(OSSL_OQS_CFLAGS "-I${OSSL_OQS_INCLUDE}")
  if(MSVC)
    string(REPLACE "\\" "/" _oqs_libdir "${OSSL_OQS_LIB}")
    set(OSSL_OQS_LDFLAGS "/LIBPATH:${_oqs_libdir}")
    set(OSSL_OQS_LDLIBS "oqs.lib")
  else()
    set(OSSL_OQS_LDFLAGS "-L${OSSL_OQS_LIB}")
    set(OSSL_OQS_LDLIBS "-loqs -lm -lpthread")
  endif()
endif()

string(REPLACE ";" " " OSSL_BASE_ARGS_STR "${OSSL_BASE_ARGS}")
string(REPLACE ";" " " OSSL_FEATURES_STR "${OSSL_FEATURES}")
set(_ossl_defs
  "-DOSSL_SOURCE_DIR=${OSSL_SOURCE_DIR}"
  "-DOSSL_PERL=${OSSL_PERL_EXECUTABLE}"
  "-DOSSL_C_COMPILER=${CMAKE_C_COMPILER}"
  "-DOSSL_BUILD_DIR=${OSSL_OPENSSL_BINARY_DIR}"
  "-DOSSL_TARGET=${OSSL_CONFIGURE_TARGET}"
  "-DOSSL_BASE_ARGS=${OSSL_BASE_ARGS_STR}"
  "-DOSSL_FEATURES=${OSSL_FEATURES_STR}"
  "-DOSSL_USER_ARGS=${OSSL_OPENSSL_ARGS}"
  "-DOSSL_MSVC_LDFLAGS=${OSSL_MSVC_LIBFLAGS}"
  "-DOSSL_OQS_CFLAGS=${OSSL_OQS_CFLAGS}"
  "-DOSSL_OQS_LDFLAGS=${OSSL_OQS_LDFLAGS}"
  "-DOSSL_OQS_LDLIBS=${OSSL_OQS_LDLIBS}")
ossl_wrap(_ossl_build_cmd "${CMAKE_COMMAND}" ${_ossl_defs}
          "-DOSSL_MAKE=${OSSL_OPENSSL_MAKE}"
          "-DOSSL_MAKE_ARGS=${OSSL_OPENSSL_MAKE_ARGS}"
          -P "${CMAKE_CURRENT_LIST_DIR}/OsslBuild.cmake")
ossl_wrap(_ossl_install_cmd "${CMAKE_COMMAND}"
          "-DOSSL_BUILD_DIR=${OSSL_OPENSSL_BINARY_DIR}"
          "-DOSSL_MAKE=${OSSL_OPENSSL_MAKE}"
          "-DOSSL_MAKE_ARGS=${OSSL_OPENSSL_MAKE_ARGS}"
          -P "${CMAKE_CURRENT_LIST_DIR}/OsslInstall.cmake")

ExternalProject_Add(ossl-openssl
  SOURCE_DIR        "${OSSL_SOURCE_DIR}"
  DOWNLOAD_COMMAND  ""
  UPDATE_COMMAND    ""
  PATCH_COMMAND     ""
  CONFIGURE_COMMAND ""
  BUILD_COMMAND     ${_ossl_build_cmd}
  INSTALL_COMMAND   ${_ossl_install_cmd}
  DEPENDS           ${OSSL_TOOL_TARGETS} ${OSSL_DEP_TARGETS}
  # Configuration is fingerprinted inside the always-run build step, and the
  # generated makefile then evaluates source/header dependencies incrementally.
  BUILD_ALWAYS      TRUE
  INSTALL_ALWAYS    TRUE
  LOG_BUILD TRUE LOG_INSTALL TRUE)

add_custom_target(all-tools)
if(OSSL_TOOL_TARGETS)
  add_dependencies(all-tools ${OSSL_TOOL_TARGETS})
endif()
add_custom_target(all-deps)
if(OSSL_DEP_TARGETS)
  add_dependencies(all-deps ${OSSL_DEP_TARGETS})
endif()
add_custom_target(openssl-all)
add_dependencies(openssl-all ossl-openssl)

if(OSSL_ENABLE_TESTS)
  ossl_wrap(_ossl_test_cmd "${CMAKE_COMMAND}"
            "-DOSSL_BUILD_DIR=${OSSL_OPENSSL_BINARY_DIR}"
            "-DOSSL_MAKE=${OSSL_OPENSSL_MAKE}"
            "-DOSSL_MAKE_ARGS=${OSSL_OPENSSL_MAKE_ARGS}"
            "-DOSSL_MAKE_TARGET=test"
            "-DOSSL_LOG=${OSSL_OPENSSL_BINARY_DIR}/openssl-test.log"
            -P "${CMAKE_CURRENT_LIST_DIR}/OsslBuild.cmake")
  add_custom_target(ossl-check COMMAND ${_ossl_test_cmd} VERBATIM)
  add_dependencies(ossl-check ossl-openssl)
endif()
