dnl -*- autoconf -*-

dnl --------------------------------------------------------------
dnl http://autoconf-archive.cryp.to/ac_c_long_long_.html
dnl Provides a test for the existance of the long long int type and defines HAVE_LONG_LONG if it is found.
AC_DEFUN([AC_C_LONG_LONG],
[AC_MSG_CHECKING(size of long long)
if test "$GCC" = yes; then
  ac_cv_c_long_long=yes
else
  AC_TRY_COMPILE(,[long long int i;],
  ac_cv_c_long_long=yes,
  ac_cv_c_long_long=no)
fi
if test $ac_cv_c_long_long = yes; then
  AC_RUN_IFELSE([AC_LANG_SOURCE([[#include <stdio.h>
int main() {
  const char *int_type;
  int bits;
  unsigned long long x = 1;
  FILE *f=fopen("conftestval", "w");
  if (!f) exit(1);
  for (bits = 0; x; bits++) {
    x <<= 1;
  }
  fprintf(f,"ECL_LONG_LONG_BITS='%d'",bits);
  exit(0);
}]])],[eval "`cat conftestval`"],[],[])
fi
if test -z "$ECL_LONG_LONG_BITS"; then
  AC_MSG_RESULT(not available)
else
  AC_MSG_RESULT([$ECL_LONG_LONG_BITS])
  AC_DEFINE(ecl_long_long_t, long long, [compiler understands long long])
  AC_DEFINE(ecl_ulong_long_t, unsigned long long, [compiler understands long long])
  AC_DEFINE_UNQUOTED([ECL_LONG_LONG_BITS],[$ECL_LONG_LONG_BITS])
fi
])

dnl --------------------------------------------------------------
dnl Add *feature* for conditional compilation.
AC_DEFUN([ECL_ADD_FEATURE], [
LSP_FEATURES="(cons :$1 ${LSP_FEATURES})"
])

dnl --------------------------------------------------------------
dnl Add lisp module to compile; if second argument is given,
dnl compile module into Lisp library if we don't support shared
dnl libraries.
dnl
AC_DEFUN([ECL_ADD_LISP_MODULE], [
  ECL_ADD_FEATURE([wants-$1])
])

dnl --------------------------------------------------------------
dnl Add lisp module and build it into the compiler.
dnl
AC_DEFUN([ECL_ADD_BUILTIN_MODULE], [
  ECL_ADD_FEATURE([builtin-$1])
])

dnl --------------------------------------------------------------
dnl Set up a configuration file for the case when we are cross-
dnl compiling
dnl
AC_DEFUN(ECL_CROSS_CONFIG,[
if test "x${cross_compiling}" = "xyes"; then
  if test -n "${with_cross_config}" -a -f "${with_cross_config}"; then
    . ${with_cross_config}
  elif test -f ./cross_config; then
    . ./cross_config
  elif test -n "${srcdir}" -a -f ${srcdir}/cross_config; then
    . ${srcdir}/cross_config
  else
    test -z ${with_cross_config} && cross_config=`pwd`/cross_config
    cat > ${with_cross_config} <<EOF
###
### YOU ARE TRYING TO CROSS COMPILE ECL.
### PLEASE FOLLOW THESE INSTRUCTIONS:
###
### 1) Vital information cannot be determined at configuration time
### because we are not able to run test programs. A file called
###		${cross_config}
### has been created, that you will have to fill out. Please do
### it before invoking "configure" again.

### 1.1) Direction of growth of the stack
ECL_STACK_DIR=up

### 1.2) Choose an integer datatype which is large enough to host a pointer
CL_FIXNUM_TYPE=int
CL_FIXNUM_BITS=32
CL_FIXNUM_MAX=536870911L
CL_FIXNUM_MIN=-536870912L

### 1.3) Order of bytes within a word
ECL_BIGENDIAN=no

### 1.4) What characters signal an end of line. May be LF (Linefeed or \\n)
###      CR (Carriage return or \\r), and CRLF (CR followed by LF).
ECL_NEWLINE=LF

### 1.5) Can we guess how many characters are available for reading from
###      the FILE structure?
###          0 = no
###          1 = (f)->_IO_read_end - (f)->_IO_read_ptr
###          2 = (f)->_r
###          3 = (f)->_cnt
ECL_FILE_CNT=0

### 2) To cross-compile ECL so that it runs on the system
###		${host}
### you need to first compile ECL on the system in which you are building
### the cross-compiled files, that is
###		${build}
### By default we assume that ECL can be accessed from some directory in
### the path.
ECL_TO_RUN=`which ecl`
EOF
    cat ${with_cross_config}
    AC_MSG_ERROR(Configuration aborted)
  fi
  if test "${ECL_TO_RUN}" = "failed"; then
    AC_MSG_ERROR(The program ECL is not installed in your system)
  fi
  ECL_MIN_TO_RUN=`${ECL_TO_RUN} -eval '(progn (print (truename "sys:ecl_min")) (si:quit))' \
	| grep '\#\P' | sed 's,#P"\(.*\)",\1,'`
  if test -z "${ECL_MIN_TO_RUN}" -o "${ECL_MIN_TO_RUN}" = "failed"  ; then
    AC_MSG_ERROR(The program ECL-MIN is not installed in your system)
  fi
  DPP_TO_RUN=`${ECL_TO_RUN} -eval '(progn (print (truename "sys:dpp")) (si:quit))' \
	| grep '\#\P' | sed 's,#P"\(.*\)",\1,'`
  if test -z "${DPP_TO_RUN}" -o "${DPP_TO_RUN}" = "failed"  ; then
    AC_MSG_ERROR(The program DPP is not installed in your system)
  fi
  dnl (echo '#!/bin/sh'; echo exec ${ECL_TO_RUN} -eval "'"'(push :cross *features*)'"'" '$''*') > CROSS-COMPILER
  (echo '#!/bin/sh'; echo exec ${ECL_MIN_TO_RUN} '$''*') > CROSS-COMPILER
  (echo '#!/bin/sh'; echo exec ${DPP_TO_RUN} '$''*') > CROSS-DPP
  chmod +x CROSS-COMPILER CROSS-DPP
  ECL_ADD_FEATURE([cross])
fi
])

dnl --------------------------------------------------------------
dnl Make srcdir absolute, if it isn't already.  It's important to
dnl avoid running the path through pwd unnecessarily, since pwd can
dnl give you automounter prefixes, which can go away.
dnl
AC_DEFUN(ECL_MAKE_ABSOLUTE_SRCDIR,[
AC_SUBST(true_srcdir)
AC_SUBST(true_builddir)
PWDCMD="pwd";
case "${srcdir}" in
  /* | ?:/* ) ;;
  *  ) srcdir="`(cd ${srcdir}; ${PWDCMD})`";
esac
if uname -a | grep -i 'mingw32' > /dev/null; then
  true_srcdir=`(cd ${srcdir}; pwd -W)`
  true_builddir=`pwd -W`
else
  true_srcdir=`(cd ${srcdir}; pwd)`
  true_builddir=`pwd`
fi
])

dnl
dnl --------------------------------------------------------------
dnl Define a name for this operating system and set some defaults
dnl
AC_DEFUN(ECL_GUESS_HOST_OS,[
#### Some command variations:
AC_SUBST(CP)
AC_SUBST(RM)
AC_SUBST(MV)
AC_SUBST(EXE_SUFFIX)
RM="rm -f"
CP="cp"
MV="mv"

### Guess the operating system
AC_SUBST(ARCHITECTURE)dnl	Type of processor for which this is compiled
AC_SUBST(SOFTWARE_TYPE)dnl	Type of operating system
AC_SUBST(SOFTWARE_VERSION)dnl	Version number of operating system
AC_SUBST(MACHINE_VERSION)dnl	Version of the machine

AC_SUBST(ECL_LDRPATH)dnl	Sometimes the path for finding DLLs must be hardcoded.
AC_SUBST(LIBPREFIX)dnl	Name components of a statically linked library
AC_SUBST(LIBEXT)
AC_SUBST(SHAREDEXT)dnl	Name components of a dynamically linked library
AC_SUBST(SHAREDPREFIX)
AC_SUBST(OBJEXT)dnl	These are set by autoconf
AC_SUBST(EXEEXT)
AC_SUBST(INSTALL_TARGET)dnl Which type of installation: flat directory or unix like.
AC_SUBST(thehost)
ECL_LDRPATH=''
SHAREDEXT='so'
SHAREDPREFIX='lib'
LIBPREFIX='lib'
LIBEXT='a'
PICFLAG='-fPIC'
THREAD_CFLAGS=''
THREAD_LIBS=''
THREAD_GC_FLAGS='--enable-threads=posix'
INSTALL_TARGET='install'
THREAD_OBJ='threads threads_mutex'
clibs=''
SONAME=''
SONAME_LDFLAGS=''
case "${host_os}" in
	# libdir may have a dollar expression inside
	linux*)
		thehost='linux'
		THREAD_CFLAGS='-D_THREAD_SAFE'
		THREAD_LIBS='-lpthread'
		SHARED_LDFLAGS="-shared ${LDFLAGS}"
		BUNDLE_LDFLAGS="-shared ${LDFLAGS}"
		ECL_LDRPATH='-Wl,--rpath,~A'
		clibs="-ldl"
		# Maybe CFLAGS="-D_ISOC99_SOURCE ${CFLAGS}" ???
		CFLAGS="-D_GNU_SOURCE -D_FILE_OFFSET_BITS=64 ${CFLAGS}"
		SONAME="${SHAREDPREFIX}ecl.${SHAREDEXT}.SOVERSION"
		SONAME_LDFLAGS="-Wl,-soname,SONAME"
		;;
	gnu*)
		thehost='gnu'
		THREAD_CFLAGS='-D_THREAD_SAFE'
		THREAD_LIBS='-lpthread'
		SHARED_LDFLAGS="-shared ${LDFLAGS}"
		BUNDLE_LDFLAGS="-shared ${LDFLAGS}"
		ECL_LDRPATH='-Wl,--rpath,~A'
		clibs="-ldl"
		CFLAGS="-D_GNU_SOURCE ${CFLAGS}"
		SONAME="${SHAREDPREFIX}ecl.${SHAREDEXT}.SOVERSION"
		SONAME_LDFLAGS="-Wl,-soname,SONAME"
		;;
	kfreebsd*-gnu)
		thehost='kfreebsd'
		THREAD_CFLAGS='-D_THREAD_SAFE'
		THREAD_LIBS='-lpthread'
		SHARED_LDFLAGS="-shared ${LDFLAGS}"
		BUNDLE_LDFLAGS="-shared ${LDFLAGS}"
		ECL_LDRPATH='-Wl,--rpath,~A'
		clibs="-ldl"
		CFLAGS="-D_GNU_SOURCE ${CFLAGS}"
		SONAME="${SHAREDPREFIX}ecl.${SHAREDEXT}.SOVERSION"
		SONAME_LDFLAGS="-Wl,-soname,SONAME"
		;;
	freebsd*)
		thehost='freebsd'
		THREAD_LIBS='-lpthread'
		SHARED_LDFLAGS="-shared ${LDFLAGS}"
		BUNDLE_LDFLAGS="-shared ${LDFLAGS}"
		ECL_LDRPATH="-Wl,--rpath,~A"
		clibs=""
		SONAME="${SHAREDPREFIX}ecl.${SHAREDEXT}.SOVERSION"
		SONAME_LDFLAGS="-Wl,-soname,SONAME"
		;;
	netbsd*)
		thehost='netbsd'
		THREAD_LIBS='-lpthread'
		SHARED_LDFLAGS="-shared ${LDFLAGS}"
		BUNDLE_LDFLAGS="-shared ${LDFLAGS}"
		ECL_LDRPATH="-Wl,--rpath,~A"
		clibs=""
		SONAME="${SHAREDPREFIX}ecl.${SHAREDEXT}.SOVERSION"
		SONAME_LDFLAGS="-Wl,-soname,SONAME"
		;;
	openbsd*)
		thehost='openbsd'
		THREAD_CFLAGS=''
		THREAD_LIBS=''
		SHARED_LDFLAGS="-shared ${LDFLAGS}"
		BUNDLE_LDFLAGS="-shared ${LDFLAGS}"
		ECL_LDRPATH="-Wl,--rpath,~A"
		clibs="-lpthread -lm"
		SONAME="${SHAREDPREFIX}ecl.${SHAREDEXT}.SOVERSION"
		SONAME_LDFLAGS="-Wl,-soname,SONAME"
		;;
	solaris*)
		thehost='sun4sol2'
		THREAD_LIBS='-lrt -lpthread'
		SHARED_LDFLAGS="-dy -G ${LDFLAGS}"
		BUNDLE_LDFLAGS="-dy -G ${LDFLAGS}"
		ECL_LDRPATH='-Wl,-R,~A'
		TCPLIBS='-lsocket -lnsl -lintl'
		clibs='-ldl'
		# We should use C99 and _XOPEN_SOURCE=600, but Solaris 10
		# ships with GCC 3.4.3 which does not support C99
		# CFLAGS="${CFLAGS} -std=gnu99"
		enable_slow_config=yes
		;;
	cygwin*)
		thehost='cygwin'
		shared='yes'
		THREAD_CFLAGS='-D_THREAD_SAFE'
		THREAD_LIBS='-lpthread'
		SHARED_LDFLAGS="-shared ${LDFLAGS}"
		BUNDLE_LDFLAGS="-shared ${LDFLAGS}"
		SHAREDPREFIX=''
		SHAREDEXT='dll'
		PICFLAG=''
		;;
	mingw*)
		thehost='mingw32'
		clibs=''
		shared='yes'
		THREAD_CFLAGS='-D_THREAD_SAFE'
		THREAD_GC_FLAGS='--enable-threads=win32'
		SHARED_LDFLAGS=''
		BUNDLE_LDFLAGS=''
		SHAREDPREFIX=''
		SHAREDEXT='dll'
		PICFLAG=''
		INSTALL_TARGET='flatinstall'
		TCPLIBS='-lws2_32'
		;;
	darwin*)
		thehost='darwin'
		shared='yes'
		SHAREDEXT='dylib'
		PICFLAG='-fPIC -fno-common'
		SHARED_LDFLAGS="-dynamiclib -flat_namespace -undefined suppress ${LDFLAGS}"
		BUNDLE_LDFLAGS="-bundle ${LDFLAGS}"
		ECL_LDRPATH=''
		THREAD_CFLAGS='-D_THREAD_SAFE'
		THREAD_LIBS='-lpthread'
		# The GMP library has not yet been ported to Intel-OSX
		case "`uname -m`" in
		i386*|x86_64) gmp_build=none-apple-${host_os};;
		*) ABI=32;;
		esac
                if test "x$ABI" = "x64"; then
                  if echo "$CFLAGS" | grep -v '[ ]*-m64' >/dev/null ; then
                     CFLAGS="-m64 $CFLAGS"
                     LDFLAGS="-m64 $LDFLAGS"
                  fi
                  # Needed when building the old version of GMP.
                  # Should be removed when moving to MPIR
                  ABI="long"
                fi
                if test "x$ABI" = "x32"; then
                  ABI="long"
                fi
                # The Boehm-Weiser GC library shipped with Fink does not work
                # well with our signal handler.
                enable_boehm=included
		SONAME="${SHAREDPREFIX}ecl.SOVERSION.${SHAREDEXT}"
		SONAME_LDFLAGS="-Wl,-install_name,@libdir\@/SONAME -Wl,-compatibility_version,${PACKAGE_VERSION}"
		;;
	nsk*)
		# HP Non-Stop platform
		thehost='nonstop'
		shared='yes'
		PICFLAG='-call_shared'
		THREAD_CFLAGS='-spthread'
		SHARED_LDFLAGS="-shared ${LDFLAGS}"
		BUNDLE_LDFLAGS="-shared ${LDFLAGS}"
		ECL_LDRPATH='-Wld=\"-rld_l ~A\"'
		clibs="-Wld=-lrld"
		;;
	*)
		thehost="$host_os"
		shared="no"
		;;
esac
case "${host_cpu}" in
	alpha*)
		CFLAGS="${CFLAGS} -mieee";;
esac
ECL_CFLAGS="-D${thehost}"
AC_MSG_CHECKING(for ld flags when building shared libraries)
if test "${enable_shared}" = "yes"; then
AC_MSG_RESULT([${SHARED_LDFLAGS}])
CFLAGS="${CFLAGS} ${PICFLAG}"
else
shared="no";
AC_MSG_RESULT(cannot build)
fi
LIBS="${clibs} ${LIBS}"
AC_MSG_CHECKING(for required libraries)
AC_MSG_RESULT([${clibs}])
AC_MSG_CHECKING(for architecture)
ARCHITECTURE=`echo "${host_cpu}" | tr a-z A-Z` # i386 -> I386
AC_MSG_RESULT([${ARCHITECTURE}])
AC_MSG_CHECKING(for software type)
SOFTWARE_TYPE="$thehost"
SOFTWARE_VERSION=""
AC_MSG_RESULT([${SOFTWARE_TYPE} / ${SOFTWARE_VERSION}])
])

dnl
dnl --------------------------------------------------------------
dnl Check whether the FILE structure has a field with the number of
dnl characters left in the buffer.
dnl
AC_DEFUN(ECL_FILE_STRUCTURE,[
AC_SUBST(ECL_FILE_CNT)
if test -z "${ECL_FILE_CNT}"; then
ECL_FILE_CNT=0
AC_COMPILE_IFELSE([AC_LANG_PROGRAM([[#include <stdio.h>]], [[
int main() {
  FILE *f = fopen("conftestval","w");
  if ((f)->_IO_read_end - (f)->_IO_read_ptr)
    return 1;
}]])],[ECL_FILE_CNT=1],[])
AC_COMPILE_IFELSE([AC_LANG_PROGRAM([[#include <stdio.h>]], [[
int main() {
  FILE *f = fopen("conftestval","w");
  if ((f)->_r)
    return 1;
}]])],[ECL_FILE_CNT=2],[])
AC_COMPILE_IFELSE([AC_LANG_PROGRAM([[#include <stdio.h>]], [[
int main() {
  FILE *f = fopen("conftestval","w");
  if ((f)->_cnt)
    return 1;
}]])],[ECL_FILE_CNT=3],[])
fi
])
dnl
dnl --------------------------------------------------------------
dnl Check the existence of different integer types and that they
dnl have the right size;
dnl
AC_DEFUN(ECL_INTEGER_TYPES,[
ECL_STDINT_HEADER=""
ECL_UINT16_T=""
ECL_UINT32_T=""
ECL_UINT64_T=""
ECL_INT16_T=""
ECL_INT32_T=""
ECL_INT64_T=""
AC_SUBST(ECL_STDINT_HEADER)
AC_CHECK_HEADER([stdint.h],[AC_DEFINE(HAVE_STDINT_H)
ECL_STDINT_HEADER="#include <stdint.h>"],[])
if test -z "${ECL_STDINT_HEADER}"; then
AC_CHECK_HEADER([inttypes.h],[AC_DEFINE(HAVE_INTTYPES_H)
ECL_STDINT_HEADER="#include <inttypes.h>"],[])
fi
if test -n "${ECL_STDINT_HEADER}" -a -z "${ECL_UINT8_T}"; then
AC_COMPILE_IFELSE([AC_LANG_PROGRAM([[#ifdef HAVE_INTTYPES_H
#include <inttypes.h>
#else
#ifdef HAVE_STDINT_H
#include <stdint.h>
#endif
#endif]], [[
{
  uint8_t i = 0x80;
  if (i == 0)
    return 0;
  if ((i << 1))
    return 0;
  if ((i - 1) != 0x7F)
    return 0;
  return 1;
}]])],[ECL_UINT8_T=uint8_t;ECL_INT8_T=int8_t],[])
fi
if test -z "${ECL_UINT8_T}"; then
AC_COMPILE_IFELSE([AC_LANG_PROGRAM([], [[
{
  unsigned char c = 0x80;
  if (i == 0)
    return 0;
  if ((i << 1))
    return 0;
  if ((i - 1) != 0x7F)
    return 0;
  return 1;
}]])],[ECL_UINT8_T="unsigned char";ECL_INT8_T="signed char"],[])
fi
if test -n "${ECL_STDINT_HEADER}" -a -z "${ECL_UINT16_T}"; then
AC_COMPILE_IFELSE([AC_LANG_PROGRAM([[#ifdef HAVE_INTTYPES_H
#include <inttypes.h>
#else
#ifdef HAVE_STDINT_H
#include <stdint.h>
#endif
#endif]], [[
{
  uint16_t i = 0x8000UL;
  if (i == 0)
    return 0;
  if ((i << 1))
    return 0;
  if ((i - 1) != 0x7FFFUL)
    return 0;
  return 1;
}]])],[ECL_UINT16_T=uint16_t;ECL_INT16_T=int16_t],[])
fi
if test -n "${ECL_STDINT_HEADER}" -a -z "${ECL_UINT32_T}"; then
AC_COMPILE_IFELSE([AC_LANG_PROGRAM([[#ifdef HAVE_INTTYPES_H
#include <inttypes.h>
#else
#ifdef HAVE_STDINT_H
#include <stdint.h>
#endif
#endif]], [[
{
  uint32_t i = 0x80000000UL;
  if (i == 0)
    return 0;
  if ((i << 1))
    return 0;
  if ((i - 1) != 0x7FFFFFFFUL)
    return 0;
  return 1;
}]])],[ECL_UINT32_T=uint32_t;ECL_INT32_T=int32_t],[])
fi
if test -n "${ECL_STDINT_HEADER}" -a -z "${ECL_UINT64_T}"; then
AC_COMPILE_IFELSE([AC_LANG_PROGRAM([[#ifdef HAVE_INTTYPES_H
#include <inttypes.h>
#else
#ifdef HAVE_STDINT_H
#include <stdint.h>
#endif
#endif]], [[
{
  uint64_t i = 1;
  i <<= 63; if (i == 0) return 0;
  i <<= 1;  if (i) return 0;
  return 1;
}]])],[ECL_UINT64_T=uint64_t;ECL_INT64_T=int64_t],[])
fi
if test "${ECL_UINT16_T}${CL_FIXNUM_BITS}" = "16"; then
  ECL_UINT16_T="cl_index"
  ECL_INT16_T="cl_fixnum"
fi
if test "${ECL_UINT32_T}${CL_FIXNUM_BITS}" = "32"; then
  ECL_UINT32_T="cl_index"
  ECL_INT32_T="cl_fixnum"
fi
if test "${ECL_UINT64_T}${CL_FIXNUM_BITS}" = "64"; then
  ECL_UINT64_T="cl_index"
  ECL_INT64_T="cl_fixnum"
fi
AC_MSG_CHECKING(uint8_t type)
if test -n "${ECL_UINT8_T}"; then
  AC_DEFINE_UNQUOTED([ecl_uint8_t],[$ECL_UINT8_T])
  AC_DEFINE_UNQUOTED([ecl_int8_t],[$ECL_INT8_T])
  AC_MSG_RESULT(${ECL_UINT8_T})
else
  AC_MSG_RESULT(none)
  AC_MSG_ERROR(Can not build ECL without byte types)
fi
AC_MSG_CHECKING(uint16_t type)
if test -n "${ECL_UINT16_T}"; then
  AC_DEFINE_UNQUOTED([ecl_uint16_t],[$ECL_UINT16_T])
  AC_DEFINE_UNQUOTED([ecl_int16_t],[$ECL_INT16_T])
  AC_MSG_RESULT(${ECL_UINT16_T})
else
  AC_MSG_RESULT(none)
fi
AC_MSG_CHECKING(uint32_t type)
if test -n "${ECL_UINT32_T}"; then
  AC_DEFINE_UNQUOTED([ecl_uint32_t],[$ECL_UINT32_T])
  AC_DEFINE_UNQUOTED([ecl_int32_t],[$ECL_INT32_T])
  AC_MSG_RESULT(${ECL_UINT32_T})
else
  AC_MSG_RESULT(none)
fi
AC_MSG_CHECKING(uint64_t type)
if test -n "${ECL_UINT64_T}"; then
  AC_DEFINE_UNQUOTED([ecl_uint64_t],[$ECL_UINT64_T])
  AC_DEFINE_UNQUOTED([ecl_int64_t],[$ECL_INT64_T])
  AC_MSG_RESULT(${ECL_UINT64_T})
else
  AC_MSG_RESULT(none)
fi
])
dnl
dnl --------------------------------------------------------------
dnl Check the direction to which the stack grows (for garbage
dnl collection).
dnl
AC_DEFUN(ECL_STACK_DIRECTION,[
  AC_MSG_CHECKING(whether stack growns downwards)
if test -z "${ECL_STACK_DIR}" ; then
  AC_RUN_IFELSE([AC_LANG_SOURCE([[
char *f2() {
  char c;
  return &c;
}

int f1() {
  char d;
  return f2() - &d;
}

int main() {
  if (f1() > 0)
    return 1;
  else
    return 0;
}
]])],[ECL_STACK_DIR=down],[ECL_STACK_DIR=up],[])
fi
case "${ECL_STACK_DIR}" in
  down|DOWN) AC_MSG_RESULT(yes); AC_DEFINE(ECL_DOWN_STACK, [1], [Stack grows downwards]) ;;
  up|UP) AC_MSG_RESULT(no) ;;
  *) AC_MSG_ERROR(Unable to determine stack growth direction)
esac])
dnl
dnl ------------------------------------------------------------
dnl Find out a setjmp() that does not save signals. It is called
dnl in several architectures.
AC_DEFUN(ECL_FIND_SETJMP,[
AC_SUBST(ECL_SETJMP)
AC_SUBST(ECL_LONGJMP)
AC_CHECK_FUNC(_longjmp,
ECL_SETJMP="_setjmp";ECL_LONGJMP="_longjmp",
ECL_SETJMP="setjmp";ECL_LONGJMP="longjmp")])

dnl
dnl --------------------------------------------------------------
dnl Guess the right type and size for cl_fixnum. It must be large
dnl enough that convertion back and forth to pointer implies no
dnl loss of information.
AC_DEFUN(ECL_FIXNUM_TYPE,[
AC_SUBST(CL_FIXNUM_TYPE)
AC_SUBST(CL_FIXNUM_BITS)
AC_SUBST(CL_FIXNUM_MAX)
AC_SUBST(CL_FIXNUM_MIN)
AC_SUBST(CL_INT_BITS)
AC_SUBST(CL_LONG_BITS)
AC_MSG_CHECKING(appropiate type for fixnums)
if test -z "${CL_FIXNUM_TYPE}" ; then
  AC_RUN_IFELSE([AC_LANG_SOURCE([[#include <stdio.h>
int main() {
  const char *int_type;
  int bits;
  FILE *f=fopen("conftestval", "w");
  if (!f) exit(1);
  if (sizeof(int) >= sizeof(void*)) {
    unsigned int t = 1;
    signed int l = 0;
    int_type="int";
    for (bits=1; ((t << 1) >> 1) == t; bits++, t <<= 1);
    l = (~l) << (bits - 3);
#if 1
    fprintf(f,"CL_FIXNUM_MIN='%d';",l);
    fprintf(f,"CL_FIXNUM_MAX='%d';",-(l+1));
#else
    l++;
    fprintf(f,"CL_FIXNUM_MIN='%d';",l);
    fprintf(f,"CL_FIXNUM_MAX='%d';",-l);
#endif
  } else if (sizeof(long) >= sizeof(void*)) {
    unsigned long int t = 1;
    signed long int l = 0;
    int_type="long int";
    for (bits=1; ((t << 1) >> 1) == t; bits++, t <<= 1);
    l = (~l) << (bits - 3);
#if 1
    fprintf(f,"CL_FIXNUM_MIN='%ld';",l);
    fprintf(f,"CL_FIXNUM_MAX='%ld';",-(l+1));
#else
    l++;
    fprintf(f,"CL_FIXNUM_MIN='%ld';",l);
    fprintf(f,"CL_FIXNUM_MAX='%ld';",-l);
#endif
  } else {
    exit(1);
  }
  fprintf(f,"CL_FIXNUM_TYPE='%s';",int_type);
  fprintf(f,"CL_FIXNUM_BITS='%d';",bits);
  {
    unsigned int x = 1;
    for (bits = 0; x; bits++) {
      x <<= 1;
    }
    fprintf(f,"CL_INT_BITS='%d';",bits);
  }
  {
    unsigned long x = 1;
    for (bits = 0; x; bits++) {
      x <<= 1;
    }
    fprintf(f,"CL_LONG_BITS='%d'",bits);
  }
  exit(0);
}]])],[eval "`cat conftestval`"],[],[])
fi
if test -z "${CL_FIXNUM_TYPE}" ; then
AC_MSG_ERROR(There is no appropiate integer type for the cl_fixnum type)
fi
AC_MSG_RESULT([${CL_FIXNUM_TYPE}])])

dnl
dnl ------------------------------------------------------------
dnl Find out what is written for every '\n' character, when
dnl opening a text file.
dnl
AC_DEFUN(ECL_LINEFEED_MODE,[
AC_MSG_CHECKING(character sequence for end of line)
if test -z "${ECL_NEWLINE}" ; then
AC_RUN_IFELSE([AC_LANG_SOURCE([[#include <stdio.h>
int main() {
  FILE *f = fopen("conftestval","w");
  int c1, c2;
  char *output;
  if (f == NULL) exit(1);
  fprintf(f, "\n");
  fclose(f);
  f = fopen("conftestval","rb");
  if (f == NULL) exit(1);
  c1 = fgetc(f);
  c2 = fgetc(f);
  fclose(f);
  f = fopen("conftestval","w");
  if (f == NULL) exit(1);
  if (c1 == '\r')
    if (c2 == EOF)
      output="CR";
    else
      output="CRLF";
  else
    output="LF";
  fclose(f);
  f = fopen("conftestval","w");
  if (f == NULL) exit(1);
  fprintf(f, output);
  fclose(f);
  exit(0);
}
]])],[ECL_NEWLINE=`cat conftestval`],[],[])
fi
case "${ECL_NEWLINE}" in
  LF) AC_MSG_RESULT(lf) ;;
  CR) AC_MSG_RESULT(cr); AC_DEFINE(ECL_NEWLINE_IS_CR, [1], [Define if your newline is CR]) ;;
  CRLF) AC_MSG_RESULT(cr+lf); AC_DEFINE(ECL_NEWLINE_IS_CRLF, [1], [Define if your newline is CRLF]) ;;
  *) AC_MSG_ERROR(Unable to determine linefeed mode) ;;
esac
])

dnl
dnl ------------------------------------------------------------
dnl Find out which program we can use to install INFO files
dnl
AC_DEFUN(ECL_INSTALL_INFO,[
AC_SUBST(INSTALL_INFO)
AC_PATH_PROG(INSTALL_INFO, install-info, [/sbin/install-info],
[$PATH:/usr/bin:/usr/sbin:/usr/etc:/usr/libexec])
])

dnl
dnl ------------------------------------------------------------
dnl Use the configuration scripts in the GMP library for
dnl configuring ECL in a compatible way.
dnl
AC_DEFUN(ECL_GMP_BASED_CONFIG,[
AC_MSG_CHECKING([Using the GMP library to guess good compiler/linker flags])
if test ! -f gmp/config.status; then
  AC_MSG_ERROR([Cannot find GMP's configuration file. Aborting])
fi
GMP_CFLAGS=`grep '^s,@CFLAGS@' gmp/config.status| sed 's&s,@CFLAGS@,\(.*\),;t t&\1&'`
GMP_LDFLAGS=`grep '^s,@GMP_LDFLAGS@' gmp/config.status| sed 's&s,@GMP_LDFLAGS@,\(.*\),;t t&\1&'`;
# Notice that GMP_LDFLAGS is designed to be passed to libtool, and therefore
# some options could be prefixed by -Wc, which means "flag for the compiler".
LDFLAGS=`echo ${LDFLAGS} ${GMP_LDFLAGS} | sed 's%-Wc,%%g'`
CFLAGS=`echo ${CFLAGS} ${GMP_CFLAGS} | sed 's%-Wc,%%g'`
GMP_CFLAGS=""
GMP_LDFLAGS=""
#host=`grep '^s,@host@' config.status | sed 's&s,@host@,\(.*\),;t t&\1&'`
AC_MSG_CHECKING([C/C++ compiler flags])
AC_MSG_RESULT([${CFLAGS}])
AC_MSG_CHECKING([Linker flags])
AC_MSG_RESULT([${LDFLAGS}])
])

dnl
dnl ------------------------------------------------------------
dnl Do we have a non-portable implementation of calls to foreign
dnl functions?
dnl
AC_DEFUN([ECL_FFI],[
AC_CHECK_LIB( ffi, ffi_call, [has_ffi_lib=yes], [has_ffi_lib=no] )
if test $has_ffi_lib = yes; then
  AC_CHECK_HEADER( [ffi/ffi.h], [has_ffi_h=$has_ffi_lib], [has_ffi_h=no] )
fi
if test $has_ffi_h = "yes"; then
  AC_DEFINE(HAVE_LIBFFI)
  LDFLAGS="$LDFLAGS -lffi"
else
AC_MSG_CHECKING([whether we can dynamically build calls to C functions])
case "${host_cpu}" in
   i686 | i586 | pentium* | athlon* )
	EXTRA_OBJS="${EXTRA_OBJS} ffi_x86.o"
	if test "${enable_asmapply}" = "yes" ; then
		EXTRA_OBJS="${EXTRA_OBJS} apply_x86.o"
		AC_DEFINE(ECL_ASM_APPLY)
	fi
        # OSX may report i386 and still allow building 64-bits
        # executables.
        if test $CL_FIXNUM_BITS = 32; then
          AC_DEFINE(ECL_USE_VARARG_AS_POINTER)
        fi
	dynamic_ffi=yes
	;;
   x86_64 )
        if test "${CL_FIXNUM_BITS}" = 32 ; then
	  EXTRA_OBJS="${EXTRA_OBJS} ffi_x86.o"
	else
	  EXTRA_OBJS="${EXTRA_OBJS} ffi_x86_64.o"
	fi
	dynamic_ffi=yes
	;;
   *)
	dynamic_ffi=no
	;;
esac
AC_MSG_RESULT([${dynamic_ffi}])
if test "$dynamic_ffi" = "yes" ; then
  AC_DEFINE(ECL_DYNAMIC_FFI, 1, [we can build calls to foreign functions])
fi
fi
])

dnl --------------------------------------------------------------
dnl Provides a test for the existance of the __thread declaration and
dnl defines WITH___THREAD if it is found
AC_DEFUN([ECL___THREAD],
[AC_CACHE_CHECK(for __thread local data, ac_cv_ecl___thread,
AC_TRY_COMPILE(,[static __thread void *data;],
   ac_cv_ecl___thread=yes,
   ac_cv_ecl___thread=no))
dnl We deactivate this test because it seems to slow down ECL A LOT!!!
])

dnl ----------------------------------------------------------------------
dnl Choose the type of code to detect floating point exceptions and
dnl raise them.
dnl
AC_DEFUN([ECL_FPE_MODEL],
[AC_MSG_CHECKING([for code to detect FP exceptions])
case "${host_cpu}" in
   i686 |i586 | pentium* | athlon* )
	ECL_FPE_CODE="arch/fpe_x86.c"
	AC_MSG_RESULT([x86])
	;;
   x86_64* )
	ECL_FPE_CODE="arch/fpe_x86.c"
	AC_MSG_RESULT([x86_64])
	;;
   *)
        ECL_FPE_CODE="arch/fpe_none.c"
	AC_MSG_RESULT([not available])
	;;
esac
AC_SUBST(ECL_FPE_CODE)
])

dnl ----------------------------------------------------------------------
dnl Check whether we have unnamed POSIX semaphores available
AC_DEFUN([ECL_POSIX_SEMAPHORES],
[AC_MSG_CHECKING(working sem_init())
AC_RUN_IFELSE([AC_LANG_SOURCE([[
#ifdef HAVE_SEMAPHORE_H
#include <semaphore.h>
int main() {
  sem_t aux;
  if (sem_init(&aux, 0, 0))
    exit(1);
  exit(0);
#else
int main() {
  exit(1);
}
#endif
}]])],[working_sem_init=yes],[working_sem_init=no],[])
AC_MSG_RESULT([$working_sem_init])
if test $working_sem_init = yes ; then
  AC_DEFINE(ECL_SEMAPHORES)
  AC_DEFINE(HAVE_SEM_INIT)
fi
])

