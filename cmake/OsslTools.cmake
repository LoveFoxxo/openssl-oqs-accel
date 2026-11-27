# =============================================================================
#  OsslTools.cmake - perl and nasm
#
#  OSSL_TOOL_MODE = AUTO   : staged copy -> host copy -> build from source
#                    BUILD  : always build from the bundled submodule
#                    SYSTEM : never build, require the host copy
#
#  Both tools are ordinary git submodules of this repository, so a plain
#  `git submodule update --init` is enough for CMake to build them.
# =============================================================================
include_guard(GLOBAL)
include(ExternalProject)

set(OSSL_TOOL_MODE "AUTO" CACHE STRING "How to obtain perl/nasm: AUTO, BUILD or SYSTEM")
set_property(CACHE OSSL_TOOL_MODE PROPERTY STRINGS AUTO BUILD SYSTEM)
if(NOT OSSL_TOOL_MODE MATCHES "^(AUTO|BUILD|SYSTEM)$")
  message(FATAL_ERROR "OSSL_TOOL_MODE must be AUTO, BUILD or SYSTEM")
endif()

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
function(ossl_shell_script out_var text)
  string(SHA256 _tag "${text}")
  string(SUBSTRING "${_tag}" 0 16 _tag)
  set(_f "${CMAKE_BINARY_DIR}/ossl-sh-${_tag}.sh")
  file(WRITE "${_f}" "#!/bin/sh\nset -e\n${text}\n")
  set(${out_var} sh "${_f}" PARENT_SCOPE)
endfunction()

set(OSSL_TOOL_TARGETS "")     # ExternalProject targets other stages depend on
set(OSSL_NASM_EXECUTABLE "")
set(OSSL_PERL_EXECUTABLE "")

# ---------------------------------------------------------------------------
# perl
# ---------------------------------------------------------------------------
set(_ossl_staged_perl "${OSSL_TOOL_DIR}/bin/perl${CMAKE_EXECUTABLE_SUFFIX}")
find_program(_ossl_system_perl NAMES perl NO_CACHE)
if(OSSL_TOOL_MODE STREQUAL "AUTO" AND EXISTS "${_ossl_staged_perl}")
  set(_ossl_host_perl "${_ossl_staged_perl}")
else()
  set(_ossl_host_perl "${_ossl_system_perl}")
endif()

set(_ossl_host_perl_usable FALSE)
if(_ossl_host_perl)
  # A minimal Git-for-Windows perl has an executable but lacks modules required
  # by OpenSSL's config.pm. Test the real dependency instead of accepting it.
  execute_process(
    COMMAND "${_ossl_host_perl}" -MLocale::Maketext::Simple -MIPC::Cmd -e 1
    RESULT_VARIABLE _perl_rc OUTPUT_QUIET ERROR_QUIET)
  if(_perl_rc EQUAL 0)
    set(_ossl_host_perl_usable TRUE)
  else()
    message(STATUS "OpenSSL tools: host perl lacks required modules: ${_ossl_host_perl}")
  endif()
endif()

set(OSSL_BUILD_PERL OFF)
if(OSSL_TOOL_MODE STREQUAL "SYSTEM")
  if(NOT _ossl_host_perl_usable)
    message(FATAL_ERROR
      "OSSL_TOOL_MODE=SYSTEM requires perl with Locale::Maketext::Simple and IPC::Cmd")
  endif()
elseif(OSSL_TOOL_MODE STREQUAL "BUILD")
  set(OSSL_BUILD_PERL ON)
elseif(NOT _ossl_host_perl_usable)
  set(OSSL_BUILD_PERL ON)
endif()

if(OSSL_BUILD_PERL)
  if(WIN32)
    # Build from a clean archive in the build tree. A previous in-source perl
    # build may contain an absolute source path from another machine.
    set(_cctype "")
    if(MSVC_VERSION GREATER_EQUAL 1950)
      set(_cctype MSVC145)
    elseif(MSVC_VERSION GREATER_EQUAL 1930)
      set(_cctype MSVC143)
    elseif(MSVC_VERSION GREATER_EQUAL 1920)
      set(_cctype MSVC142)
    elseif(MSVC_VERSION GREATER_EQUAL 1910)
      set(_cctype MSVC141)
    else()
      set(_cctype MSVC140)
    endif()
    set(OSSL_PERL_CCTYPE "${_cctype}" CACHE STRING
        "CCTYPE passed to perl5/win32/Makefile (MSVC140..MSVC145)")
    find_program(_ossl_git_executable NAMES git)
    if(NOT _ossl_git_executable)
      message(FATAL_ERROR "Building bundled perl requires git")
    endif()
    set(_perl_work "${CMAKE_BINARY_DIR}/perl")
    ossl_wrap(_perl_build "${CMAKE_COMMAND}"
              "-DOSSL_PERL_SRC=${OSSL_SOURCE_DIR}/perl5"
              "-DOSSL_PERL_WORK=${_perl_work}"
              "-DOSSL_PERL_GIT=${_ossl_git_executable}"
              "-DOSSL_PERL_CCTYPE=${OSSL_PERL_CCTYPE}"
              "-DOSSL_PERL_ARCH=${OSSL_MSVC_ARCH}"
              "-DOSSL_MAKE=${OSSL_OPENSSL_MAKE}"
              "-DOSSL_TOOL_DIR=${OSSL_TOOL_DIR}"
              -P "${CMAKE_CURRENT_LIST_DIR}/OsslPerlBuild.cmake")
    ossl_wrap(_perl_install "${CMAKE_COMMAND}"
              "-DOSSL_PERL_SRC=${_perl_work}"
              "-DOSSL_PERL_STAGE=${OSSL_TOOL_DIR}"
              -P "${CMAKE_CURRENT_LIST_DIR}/OsslStagePerl.cmake")
    ExternalProject_Add(ossl-perl
      SOURCE_DIR        ${OSSL_SOURCE_DIR}/perl5/win32
      DOWNLOAD_COMMAND  ""
      UPDATE_COMMAND    ""
      PATCH_COMMAND     ""
      CONFIGURE_COMMAND ""
      BUILD_COMMAND     ${_perl_build}
      INSTALL_COMMAND   ${_perl_install}
      BUILD_ALWAYS      TRUE
      INSTALL_ALWAYS    TRUE
      LOG_BUILD TRUE LOG_INSTALL TRUE)
  else()
    ossl_shell_script(_perl_cfg
      "${OSSL_SOURCE_DIR}/perl5/Configure -des -Dprefix=${OSSL_TOOL_DIR} -Dusethreads\n")
    ossl_shell_script(_perl_build
      "cd '${OSSL_SOURCE_DIR}/perl5' && make -j${OSSL_JOBS}\n")
    ossl_shell_script(_perl_install
      "cd '${OSSL_SOURCE_DIR}/perl5' && make install\n")
    ExternalProject_Add(ossl-perl
      SOURCE_DIR        ${OSSL_SOURCE_DIR}/perl5
      DOWNLOAD_COMMAND  ""
      UPDATE_COMMAND    ""
      PATCH_COMMAND     ""
      CONFIGURE_COMMAND ${_perl_cfg}
      BUILD_COMMAND     ${_perl_build}
      INSTALL_COMMAND   ${_perl_install}
      BUILD_IN_SOURCE   TRUE
      LOG_CONFIGURE TRUE LOG_BUILD TRUE LOG_INSTALL TRUE)
  endif()
  list(APPEND OSSL_TOOL_TARGETS ossl-perl)
  set(OSSL_PERL_EXECUTABLE "${_ossl_staged_perl}")
  message(STATUS "OpenSSL tools: perl will be built from source -> ${OSSL_PERL_EXECUTABLE}")
else()
  set(OSSL_PERL_EXECUTABLE "${_ossl_host_perl}")
  message(STATUS "OpenSSL tools: perl -> ${OSSL_PERL_EXECUTABLE}")
endif()

# ---------------------------------------------------------------------------
# nasm (only needed when OpenSSL builds its own assembly)
# ---------------------------------------------------------------------------
option(OSSL_ENABLE_ASM "Let OpenSSL build its assembly implementations" ON)

if(NOT OSSL_ENABLE_ASM)
  message(STATUS "OpenSSL tools: nasm skipped (assembly disabled)")
else()

set(_ossl_staged_nasm "${OSSL_TOOL_DIR}/bin/nasm${CMAKE_EXECUTABLE_SUFFIX}")
find_program(_ossl_system_nasm NAMES nasm NO_CACHE)
if(OSSL_TOOL_MODE STREQUAL "AUTO" AND EXISTS "${_ossl_staged_nasm}")
  set(_ossl_host_nasm "${_ossl_staged_nasm}")
else()
  set(_ossl_host_nasm "${_ossl_system_nasm}")
endif()

set(OSSL_BUILD_NASM OFF)
if(OSSL_TOOL_MODE STREQUAL "SYSTEM")
  if(NOT _ossl_host_nasm)
    message(FATAL_ERROR "OSSL_TOOL_MODE=SYSTEM but nasm was not found on PATH")
  endif()
elseif(OSSL_TOOL_MODE STREQUAL "BUILD")
  set(OSSL_BUILD_NASM ON)
elseif(NOT _ossl_host_nasm)
  set(OSSL_BUILD_NASM ON)
endif()

set(OSSL_NASM_URL
    "https://www.nasm.us/pub/nasm/releasebuilds/2.16.03/win64/nasm-2.16.03-win64.zip"
    CACHE STRING "Prebuilt nasm archive used when the source tree cannot be built")
set(OSSL_NASM_URL_HASH
    "SHA256=3ee4782247bcb874378d02f7eab4e294a84d3d15f3f6ee2de2f47a46aa7226e6"
    CACHE STRING "Required hash for OSSL_NASM_URL")

if(OSSL_BUILD_NASM)
  if(WIN32)
    # nasm's git checkout does not carry config/config.h.in (it is produced by
    # autoheader), so the MSVC makefile cannot run from a plain submodule.
    # Build from source when the generated tree is there, otherwise fall back
    # to the official binary so the chain still completes.
    if(EXISTS "${OSSL_SOURCE_DIR}/nasm/config/config.h.in")
      ossl_wrap(_nasm_build nmake /f "Mkfiles/msvc.mak" EXTERNAL_DEPENDENCIES=0)
      file(MAKE_DIRECTORY "${OSSL_TOOL_DIR}/bin")
      ossl_wrap(_nasm_install ${CMAKE_COMMAND} -E copy
                "${OSSL_SOURCE_DIR}/nasm/nasm.exe" "${_ossl_staged_nasm}")
      ExternalProject_Add(ossl-nasm
        SOURCE_DIR        ${OSSL_SOURCE_DIR}/nasm
        DOWNLOAD_COMMAND  ""
        UPDATE_COMMAND    ""
        PATCH_COMMAND     ""
        CONFIGURE_COMMAND ""
        BUILD_IN_SOURCE   TRUE
        BUILD_COMMAND     ${_nasm_build}
        INSTALL_COMMAND   ${_nasm_install}
        LOG_BUILD TRUE LOG_INSTALL TRUE)
    else()
      message(STATUS "OpenSSL tools: nasm source tree is not autoconf-ready, "
                     "using the official binary instead")
      add_custom_target(ossl-nasm
        COMMAND "${CMAKE_COMMAND}"
                "-DOSSL_NASM_URL=${OSSL_NASM_URL}"
                "-DOSSL_NASM_URL_HASH=${OSSL_NASM_URL_HASH}"
                "-DOSSL_NASM_DEST=${_ossl_staged_nasm}"
                -P "${CMAKE_CURRENT_LIST_DIR}/OsslFetchNasm.cmake"
        COMMENT "Fetching nasm into the staging area"
        VERBATIM)
    endif()
  else()
    ossl_shell_script(_nasm_cfg
      "cd '${OSSL_SOURCE_DIR}/nasm' && ./autogen.sh && ./configure --prefix=${OSSL_TOOL_DIR}\n")
    ossl_shell_script(_nasm_build
      "cd '${OSSL_SOURCE_DIR}/nasm' && make -j${OSSL_JOBS}\n")
    # "make install" also installs the man pages, which nasm's git tree does not
    # carry (nasm.1 is generated by doc tools).  Only the binary is staged.
    ossl_shell_script(_nasm_install
      "cd '${OSSL_SOURCE_DIR}/nasm' && mkdir -p '${OSSL_TOOL_DIR}/bin' && cp -f nasm '${_ossl_staged_nasm}'\n")
    ExternalProject_Add(ossl-nasm
      SOURCE_DIR        ${OSSL_SOURCE_DIR}/nasm
      DOWNLOAD_COMMAND  ""
      UPDATE_COMMAND    ""
      PATCH_COMMAND     ""
      CONFIGURE_COMMAND ${_nasm_cfg}
      BUILD_COMMAND     ${_nasm_build}
      INSTALL_COMMAND   ${_nasm_install}
      BUILD_IN_SOURCE   TRUE
      LOG_CONFIGURE TRUE LOG_BUILD TRUE LOG_INSTALL TRUE)
  endif()
  list(APPEND OSSL_TOOL_TARGETS ossl-nasm)
  set(OSSL_NASM_EXECUTABLE "${_ossl_staged_nasm}")
  message(STATUS "OpenSSL tools: nasm will be built from source -> ${OSSL_NASM_EXECUTABLE}")
else()
  set(OSSL_NASM_EXECUTABLE "${_ossl_host_nasm}")
  message(STATUS "OpenSSL tools: nasm -> ${OSSL_NASM_EXECUTABLE}")
endif()

endif()
