# CMake-built dependencies, installed separately from OpenSSL so that stale
# installed OpenSSL headers can never shadow the current build's headers.
include_guard(GLOBAL)
include(ExternalProject)

option(OSSL_WITH_ZLIB   "Build zlib from the bundled submodule" ON)
option(OSSL_WITH_ZSTD   "Build zstd from the bundled submodule" ON)
option(OSSL_WITH_BROTLI "Build brotli from the bundled submodule" ON)
option(OSSL_WITH_OQS    "Build liboqs from the bundled submodule" ON)
option(OSSL_STATIC_MSVC_RUNTIME "Link the static MSVC runtime (/MT)" OFF)

set(OSSL_DEP_TARGETS "")
set(_ossl_common_cmake_args
  -DCMAKE_BUILD_TYPE=$<CONFIG>
  -DBUILD_SHARED_LIBS=OFF
  -DBUILD_TESTING=OFF
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON)
if(MSVC AND OSSL_STATIC_MSVC_RUNTIME)
  list(APPEND _ossl_common_cmake_args
       "-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

function(ossl_add_cmake_dep name source_dir)
  cmake_parse_arguments(ARG "" "" "ARGS" ${ARGN})
  ExternalProject_Add(${name}
    SOURCE_DIR        "${source_dir}"
    DOWNLOAD_COMMAND  ""
    UPDATE_COMMAND    ""
    PATCH_COMMAND     ""
    LIST_SEPARATOR    "|"
    CMAKE_ARGS
      -DCMAKE_INSTALL_PREFIX=${OSSL_DEP_PREFIX}
      ${_ossl_common_cmake_args}
      ${ARG_ARGS}
    BUILD_COMMAND
      ${CMAKE_COMMAND} --build <BINARY_DIR> --config $<CONFIG> --parallel ${OSSL_JOBS}
    INSTALL_COMMAND
      ${CMAKE_COMMAND} --install <BINARY_DIR> --config $<CONFIG>
    # Re-evaluate each dependency's own dependency graph. The nested builds are
    # incremental; reinstalling is required to propagate newly built archives.
    BUILD_ALWAYS      TRUE
    INSTALL_ALWAYS    TRUE
    LOG_CONFIGURE TRUE LOG_BUILD TRUE LOG_INSTALL TRUE)
endfunction()

if(OSSL_WITH_ZLIB)
  ossl_add_cmake_dep(ossl-zlib "${OSSL_SOURCE_DIR}/zlib"
    ARGS -DZLIB_BUILD_SHARED=OFF
         -DZLIB_BUILD_STATIC=ON
         -DZLIB_BUILD_TESTING=OFF
         -DZLIB_BUILD_EXAMPLES=OFF)
  list(APPEND OSSL_DEP_TARGETS ossl-zlib)
  set(OSSL_ZLIB_INCLUDE "${OSSL_DEP_PREFIX}/include")
  set(OSSL_ZLIB_LIB     "${OSSL_DEP_PREFIX}/lib")
else()
  set(OSSL_ZLIB_INCLUDE "")
  set(OSSL_ZLIB_LIB     "")
endif()

if(OSSL_WITH_ZSTD)
  ossl_add_cmake_dep(ossl-zstd "${OSSL_SOURCE_DIR}/zstd/build/cmake"
    ARGS -DZSTD_BUILD_SHARED=OFF
         -DZSTD_BUILD_STATIC=ON
         -DZSTD_BUILD_PROGRAMS=OFF
         -DZSTD_BUILD_TESTS=OFF
         -DZSTD_BUILD_CONTRIB=OFF
         -DZSTD_MULTITHREAD_SUPPORT=OFF)
  list(APPEND OSSL_DEP_TARGETS ossl-zstd)
  set(OSSL_ZSTD_INCLUDE "${OSSL_DEP_PREFIX}/include")
  set(OSSL_ZSTD_LIB     "${OSSL_DEP_PREFIX}/lib")
else()
  set(OSSL_ZSTD_INCLUDE "")
  set(OSSL_ZSTD_LIB     "")
endif()

if(OSSL_WITH_BROTLI)
  ossl_add_cmake_dep(ossl-brotli "${OSSL_SOURCE_DIR}/brotli"
    ARGS -DBROTLI_BUILD_TOOLS=OFF
         -DBROTLI_DISABLE_TESTS=ON
         -DBROTLI_BUILD_FOR_PACKAGE=OFF
         -DBUILD_SHARED_LIBS=OFF)
  list(APPEND OSSL_DEP_TARGETS ossl-brotli)
  set(OSSL_BROTLI_INCLUDE "${OSSL_DEP_PREFIX}/include")
  set(OSSL_BROTLI_LIB     "${OSSL_DEP_PREFIX}/lib")
else()
  set(OSSL_BROTLI_INCLUDE "")
  set(OSSL_BROTLI_LIB     "")
endif()

set(OSSL_OQS_PROFILE "fast" CACHE STRING
    "liboqs profile: fast (ML-KEM only) or full (all enabled algorithms)")
set_property(CACHE OSSL_OQS_PROFILE PROPERTY STRINGS fast full)
if(NOT OSSL_OQS_PROFILE MATCHES "^(fast|full)$")
  message(FATAL_ERROR "OSSL_OQS_PROFILE must be fast or full")
endif()

if(OSSL_WITH_OQS)
  # liboqs and libcrypto vendor some Keccak/SHA3 x4 routines under identical
  # global names. Prefix the liboqs copies in both C and preprocessed ASM.
  set(_oqs_clash_syms
      keccak_1600_extract_bytes_x4 keccak_1600_init_state
      keccak_1600_load_state_x4 keccak_1600_partial_add_x4
      keccak_1600_save_state_x4
      SHA3_shake128_x4_avx512vl SHA3_shake128_x4_inc_absorb_avx512vl
      SHA3_shake128_x4_inc_finalize_avx512vl SHA3_shake128_x4_inc_squeeze_avx512vl
      SHA3_shake256_x4_avx512vl SHA3_shake256_x4_inc_absorb_avx512vl
      SHA3_shake256_x4_inc_finalize_avx512vl SHA3_shake256_x4_inc_squeeze_avx512vl)
  set(_oqs_cflags "")
  foreach(_s IN LISTS _oqs_clash_syms)
    string(APPEND _oqs_cflags " -D${_s}=oqs_${_s}")
  endforeach()
  string(STRIP "${_oqs_cflags}" _oqs_cflags)

  set(_oqs_args
      "-DCMAKE_C_FLAGS=${_oqs_cflags}"
      "-DCMAKE_ASM_FLAGS=${_oqs_cflags}"
      -DOQS_BUILD_ONLY_LIB=ON
      -DOQS_BUILD_SHARED_LIBS=OFF
      -DOQS_BUILD_TESTS=OFF
      -DOQS_BUILD_BENCH=OFF
      -DBUILD_TESTING=OFF
      -DOQS_USE_OPENSSL=OFF)
  if(OSSL_OQS_PROFILE STREQUAL "fast")
    # ExternalProject converts '|' back to CMake list separators.
    list(APPEND _oqs_args
      "-DOQS_MINIMAL_BUILD=KEM_ml_kem_512|KEM_ml_kem_768|KEM_ml_kem_1024")
  endif()
  if(WIN32)
    list(APPEND _oqs_args -DOQS_PERMIT_UNSUPPORTED_ARCHITECTURE=ON)
  endif()
  ossl_add_cmake_dep(ossl-liboqs "${OSSL_SOURCE_DIR}/liboqs" ARGS ${_oqs_args})
  list(APPEND OSSL_DEP_TARGETS ossl-liboqs)
  set(OSSL_OQS_INCLUDE "${OSSL_DEP_PREFIX}/include")
  set(OSSL_OQS_LIB     "${OSSL_DEP_PREFIX}/lib")
else()
  set(OSSL_OQS_INCLUDE "")
  set(OSSL_OQS_LIB     "")
endif()
