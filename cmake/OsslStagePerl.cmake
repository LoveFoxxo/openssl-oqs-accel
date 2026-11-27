# =============================================================================
#  OsslStagePerl.cmake  (script mode)
#
#  Copies a freshly built perl into the staging area.  `nmake install` is not
#  used on purpose: the win32 build bakes INST_TOP into Config.pm at build time,
#  so an install-only override silently lands in C:\perl instead of the stage.
#
#  cmake -DOSSL_PERL_SRC=<perl5 dir> -DOSSL_PERL_STAGE=<stage/tools> -P ...
# =============================================================================

foreach(_v OSSL_PERL_SRC OSSL_PERL_STAGE)
  if(NOT DEFINED ${_v})
    message(FATAL_ERROR "OsslStagePerl: required variable ${_v} is not set")
  endif()
endforeach()

set(_bin "${OSSL_PERL_STAGE}/bin")
set(_lib "${OSSL_PERL_STAGE}/lib")
file(MAKE_DIRECTORY "${_bin}" "${_lib}")

# --- executables -----------------------------------------------------------
foreach(_exe perl.exe perlglob.exe wperl.exe)
  if(EXISTS "${OSSL_PERL_SRC}/${_exe}")
    file(COPY_FILE "${OSSL_PERL_SRC}/${_exe}" "${_bin}/${_exe}")
  endif()
endforeach()

# --- the perl DLL (perl5xx.dll) -------------------------------------------
file(GLOB _dlls "${OSSL_PERL_SRC}/perl[0-9]*.dll")
foreach(_d ${_dlls})
  get_filename_component(_n "${_d}" NAME)
  file(COPY_FILE "${_d}" "${_bin}/${_n}")
endforeach()

# --- module tree -----------------------------------------------------------
if(EXISTS "${OSSL_PERL_SRC}/lib")
  file(COPY "${OSSL_PERL_SRC}/lib/" DESTINATION "${_lib}")
endif()
if(EXISTS "${OSSL_PERL_SRC}/site/lib")
  file(COPY "${OSSL_PERL_SRC}/site/lib/" DESTINATION "${_lib}")
endif()

if(NOT EXISTS "${_bin}/perl.exe")
  message(FATAL_ERROR "OsslStagePerl: perl.exe was not produced by the build")
endif()

message(STATUS "OsslStagePerl: staged ${_bin}/perl.exe")
