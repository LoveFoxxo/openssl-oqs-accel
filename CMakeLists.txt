# =============================================================================
#  OpenSSL unified build
#
#      git submodule update --init
#      cmake -S . -B build -G "Visual Studio 18 2026" -A x64
#      cmake --build build --config Release --target openssl-all
#
#  Stages, in order:
#      1. tools : nasm + perl            (built from source when missing)
#      2. deps  : zlib + zstd + brotli + liboqs (installed into build/deps)
#      3. openssl                         (Configure is driven by CMake)
# =============================================================================
cmake_minimum_required(VERSION 3.23)

project(OpenSSLUnified
        VERSION 4.2.0
        DESCRIPTION "CMake superbuild: tools + zlib/zstd/brotli/liboqs + OpenSSL"
        LANGUAGES C)

if(WIN32 AND NOT MSVC)
  message(FATAL_ERROR "The Windows unified build currently requires MSVC")
endif()

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_BINARY_DIR)
  message(FATAL_ERROR
    "In-source builds are not supported, they would pollute the OpenSSL tree. "
    "Use: cmake -S . -B build")
endif()

set(OSSL_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")

# user supplied extra Configure arguments, appended after everything else
set(OSSL_OPENSSL_ARGS "" CACHE STRING
    "Extra arguments forwarded verbatim to OpenSSL Configure")

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

include(OsslPlatform)   # staging layout, vcvars, command wrapping
include(OsslTools)      # perl + nasm
include(OsslDeps)       # zlib + zstd + liboqs
include(OsslOpenSSL)    # the Configure/build stage

# ---------------------------------------------------------------------------
# submodule sanity check
# ---------------------------------------------------------------------------
set(_missing)
foreach(_m zlib zstd brotli liboqs perl5 nasm)
  if(NOT EXISTS "${OSSL_SOURCE_DIR}/${_m}")
    list(APPEND _missing ${_m})
  endif()
endforeach()
if(_missing)
  message(WARNING
    "Submodules not initialized: ${_missing}. "
    "Run: git submodule update --init --recursive")
endif()

message(STATUS "")
message(STATUS "OpenSSL unified build")
message(STATUS "  final prefix : ${OSSL_INSTALL_DIR}")
message(STATUS "  deps prefix  : ${OSSL_DEP_PREFIX}")
message(STATUS "  perl         : ${OSSL_PERL_EXECUTABLE}")
message(STATUS "  nasm         : ${OSSL_NASM_EXECUTABLE}")
message(STATUS "  features     : ${OSSL_FEATURES}")
message(STATUS "  deps         : zlib=${OSSL_WITH_ZLIB} zstd=${OSSL_WITH_ZSTD} brotli=${OSSL_WITH_BROTLI} oqs=${OSSL_WITH_OQS}")
message(STATUS "  args file    : ${OSSL_OPENSSL_BINARY_DIR}/configure-args.txt")
message(STATUS "")
