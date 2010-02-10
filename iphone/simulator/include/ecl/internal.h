/* -*- mode: c; c-basic-offset: 8 -*- */
/*
    internal.h -- Structures and functions that are not meant for the end user
*/
/*
    Copyright (c) 2001, Juan Jose Garcia Ripoll.

    ECL is free software; you can redistribute it and/or
    modify it under the terms of the GNU Library General Public
    License as published by the Free Software Foundation; either
    version 2 of the License, or (at your option) any later version.

    See file '../Copyright' for full details.
*/

#ifdef __cplusplus
extern "C" {
#endif

/* -------------------------------------------------------------------- *
 *	FUNCTIONS, VARIABLES AND TYPES NOT FOR GENERAL USE		*
 * -------------------------------------------------------------------- */

/* booting */
extern void init_all_symbols(void);
extern void init_alloc(void);
extern void init_backq(void);
extern void init_big();
#ifdef CLOS
extern void init_clos(void);
#endif
extern void init_error(void);
extern void init_eval(void);
extern void init_file(void);
#ifndef GBC_BOEHM
extern void init_GC(void);
#endif
extern void init_macros(void);
extern void init_number(void);
extern void init_read(void);
extern void init_stacks(cl_env_ptr, char *);
extern void init_unixint(int pass);
extern void init_unixtime(void);
#ifdef mingw32
extern void init_compiler(void);
#endif
#ifdef ECL_THREADS
extern void init_threads(cl_env_ptr);
#endif
extern void ecl_init_env(cl_env_ptr);
extern void init_lib_LSP(cl_object);

extern cl_env_ptr _ecl_alloc_env(void);
extern void _ecl_dealloc_env(cl_env_ptr);

/* alloc.d/alloc_2.d */

#ifdef GBC_BOEHM
#define ECL_COMPACT_OBJECT_EXTRA(x) ((void*)((x)->array.displaced))
#endif
extern void _ecl_set_max_heap_size(cl_index new_size);
extern cl_object ecl_alloc_bytecodes(cl_index data_size, cl_index code_size);

/* compiler.d */

struct cl_compiler_env {
	cl_object variables;		/* Variables, tags, functions, etc: the env. */
	cl_object macros;		/* Macros and function bindings */
	cl_fixnum lexical_level;	/* =0 if toplevel form */
	cl_object constants;		/* Constants for this form */
	cl_object lex_env;		/* Lexical env. for eval-when */
	cl_index env_depth;
	cl_index env_size;
        int mode;
	bool coalesce;
	bool stepping;
};

typedef struct cl_compiler_env *cl_compiler_env_ptr;

/* character.d */

#ifdef ECL_UNICODE
#define ECL_UCS_NONCHARACTER(c) \
	(((c) >= 0xFDD0 && (c) <= 0xFDEF) || \
	 (((c) & 0xFFFF) >= 0xFFFE && (((c) & 0xFFFF) <= 0xFFFF)))
#define ECL_UCS_PRIVATE(c) \
	(((c) >= 0xE000 && (c) <= 0xF8FF) || \
	 ((c) >= 0xF0000 && (c) <= 0xFFFD) || \
	 ((c) >= 0x100000 && (c) <= 0x10FFFD))
#define ECL_UCS_HIGH_SURROGATE(c) ((c) >= 0xD800 && (c) <= 0xDBFF)
#define ECL_UCS_LOW_SURROGATE(c) ((c) >= 0xDC00 && (c) <= 0xDFFF)
#endif


/* interpreter.d */

#define ECL_BUILD_STACK_FRAME(env,name,frame)	\
	struct ecl_stack_frame frame;\
	cl_object name = ecl_stack_frame_open(env, (cl_object)&frame, 0);

#ifdef ECL_USE_VARARG_AS_POINTER
#define ECL_STACK_FRAME_FROM_VA_LIST(e,f,va) do {                  \
                const cl_object __frame = (f);                     \
                __frame->frame.t = t_frame;                        \
                __frame->frame.stack = 0;                          \
                __frame->frame.env = (e);                          \
                __frame->frame.size = va[0].narg;                  \
                __frame->frame.base = va[0].sp? va[0].sp :         \
                        (cl_object*)va[0].args;                    \
        } while(0)
#else
#define ECL_STACK_FRAME_FROM_VA_LIST(e,f,va) do {                       \
                const cl_object __frame = (f);                          \
                cl_index i, __nargs = va[0].narg;                       \
                ecl_stack_frame_open((e), __frame, __nargs);            \
                for (i = 0; i < __nargs; i++) {                         \
                        __frame->frame.base[i] = cl_va_arg(va);         \
                }                                                       \
        } while (0)
#endif

#ifdef ECL_USE_VARARG_AS_POINTER
#define ECL_STACK_FRAME_VARARGS_BEGIN(narg,lastarg,frame)               \
        struct ecl_frame __ecl_frame;                                   \
        const cl_object frame = (cl_object)&__ecl_frame;                \
        const cl_env_ptr env = ecl_process_env();                       \
        frame->frame.t = t_frame;                                       \
        frame->frame.stack = 0;                                         \
        frame->frame.env = env;                                         \
        frame->frame.size = narg;                                       \
        if (narg < C_ARGUMENTS_LIMIT) {                                 \
                va_list args;                                           \
                va_start(args, lastarg);                                \
                frame->frame.base = (void*)args;                        \
        } else {                                                        \
                frame->frame.base = env->stack_top - narg;              \
        }
#define ECL_STACK_FRAME_VARARGS_END(frame)      \
        /* No stack consumed, no need to close frame */
#else
#define ECL_STACK_FRAME_VARARGS_BEGIN(narg,lastarg,frame)               \
        struct ecl_frame __ecl_frame;                                   \
        const cl_object frame = (cl_object)&__ecl_frame;                \
        const cl_env_ptr env = ecl_process_env();                       \
        frame->frame.t = t_frame;                                       \
        frame->frame.env = env;                                         \
        frame->frame.size = narg;                                       \
        if (narg < C_ARGUMENTS_LIMIT) {                                 \
                cl_index i;                                             \
                cl_object *p = frame->frame.base = env->values;         \
                va_list args;                                           \
                va_start(args, lastarg);                                \
                while (narg--) {                                        \
                        *p = va_arg(args, cl_object);                   \
                        ++p;                                            \
                }                                                       \
                frame->frame.stack = (void*)0x1;                        \
        } else {                                                        \
                frame->frame.base = env->stack_top - narg;              \
                frame->frame.stack = 0;                                 \
        }
#define ECL_STACK_FRAME_VARARGS_END(frame)      \
        /* No stack consumed, no need to close frame */
#endif

extern cl_object _ecl_bytecodes_dispatch_vararg(cl_narg narg, ...);
extern cl_object _ecl_bclosure_dispatch_vararg(cl_narg narg, ...);

/* ffi.d */

struct ecl_fficall {
	char *buffer_sp;
	size_t buffer_size;
	union ecl_ffi_values output;
	enum ecl_ffi_calling_convention cc;
	struct ecl_fficall_reg *registers;
	char buffer[ECL_FFICALL_LIMIT];
	cl_object cstring;
};

extern enum ecl_ffi_tag ecl_foreign_type_code(cl_object type);
#ifdef ECL_DYNAMIC_FFI
extern enum ecl_ffi_calling_convention ecl_foreign_cc_code(cl_object cc_type);
extern void ecl_fficall_prepare(cl_object return_type, cl_object arg_types, cl_object cc_type);
extern void ecl_fficall_push_bytes(void *data, size_t bytes);
extern void ecl_fficall_push_int(int word);
extern void ecl_fficall_align(int data);

extern struct ecl_fficall_reg *ecl_fficall_prepare_extra(struct ecl_fficall_reg *registers);
extern void ecl_fficall_push_arg(union ecl_ffi_values *data, enum ecl_ffi_tag type);
extern void ecl_fficall_execute(void *f_ptr, struct ecl_fficall *fficall, enum ecl_ffi_tag return_type);
extern void ecl_dynamic_callback_call(cl_object callback_info, char* buffer);
extern void* ecl_dynamic_callback_make(cl_object data, enum ecl_ffi_calling_convention cc_type);
#endif

/* file.d */

/*
 * POSIX specifies that the "b" flag is ignored. This is good, because
 * under MSDOS and Apple's OS we need to open text files in binary mode,
 * so that we get both the carriage return and the linefeed characters.
 * Otherwise, it would be complicated to implement file-position and
 * seek operations.
 */
#define OPEN_R	"rb"
#define OPEN_W	"wb"
#define OPEN_RW	"r+b"
#define OPEN_A	"ab"
#define OPEN_RA	"a+b"

#define ECL_FILE_STREAMP(strm) (type_of(strm) == t_stream && (strm)->stream.mode < smm_synonym)
#define STRING_OUTPUT_STRING(strm) (strm)->stream.object0
#define STRING_OUTPUT_COLUMN(strm) (strm)->stream.int1
#define STRING_INPUT_STRING(strm) (strm)->stream.object0
#define STRING_INPUT_POSITION(strm) (strm)->stream.int0
#define STRING_INPUT_LIMIT(strm) (strm)->stream.int1
#define TWO_WAY_STREAM_INPUT(strm) (strm)->stream.object0
#define TWO_WAY_STREAM_OUTPUT(strm) (strm)->stream.object1
#define SYNONYM_STREAM_SYMBOL(strm) (strm)->stream.object0
#define SYNONYM_STREAM_STREAM(strm) ecl_symbol_value((strm)->stream.object0)
#define BROADCAST_STREAM_LIST(strm) (strm)->stream.object0
#define ECHO_STREAM_INPUT(strm) (strm)->stream.object0
#define ECHO_STREAM_OUTPUT(strm) (strm)->stream.object1
#define CONCATENATED_STREAM_LIST(strm) (strm)->stream.object0
#define IO_STREAM_FILE(strm) ((strm)->stream.file.stream)
#define IO_STREAM_COLUMN(strm) (strm)->stream.int1
#define IO_STREAM_ELT_TYPE(strm) (strm)->stream.object0
#define IO_STREAM_FILENAME(strm) (strm)->stream.object1
#define IO_FILE_DESCRIPTOR(strm) (strm)->stream.file.descriptor
#define IO_FILE_COLUMN(strm) (strm)->stream.int1
#define IO_FILE_ELT_TYPE(strm) (strm)->stream.object0
#define IO_FILE_FILENAME(strm) (strm)->stream.object1

/* format.d */

#ifndef ECL_CMU_FORMAT
extern cl_object si_formatter_aux _ARGS((cl_narg narg, cl_object strm, cl_object string, ...));
#endif

/* hash.d */
extern cl_object ecl_extend_hashtable(cl_object hashtable);

/* gfun.d, kernel.lsp */

#define GFUN_NAME(x) ((x)->instance.slots[0])
#define GFUN_SPEC(x) ((x)->instance.slots[1])
#define GFUN_COMB(x) ((x)->instance.slots[2])

extern cl_object FEnot_funcallable_vararg(cl_narg narg, ...);

/* print.d */

#define ECL_PPRINT_QUEUE_SIZE			128
#define ECL_PPRINT_INDENTATION_STACK_SIZE	256

#ifdef ECL_LONG_FLOAT
extern int edit_double(int n, long double d, int *sp, char *s, int *ep);
#else
extern int edit_double(int n, double d, int *sp, char *s, int *ep);
#endif
extern void cl_write_object(cl_object x, cl_object stream);

/* global locks */

#ifdef ECL_THREADS
# define HASH_TABLE_LOCK(h) do {                                        \
                cl_object lock = (h)->hash.lock;                        \
                if (lock != Cnil) mp_get_lock_wait(lock);               \
        } while (0);
# define HASH_TABLE_UNLOCK(h) do {                                      \
                cl_object lock = (h)->hash.lock;                        \
                if (lock != Cnil) mp_giveup_lock(lock);                 \
        } while (0);
# define THREAD_OP_LOCK() mp_get_lock_wait(cl_core.global_lock)
# define THREAD_OP_UNLOCK() mp_giveup_lock(cl_core.global_lock)
# define PACKAGE_OP_LOCK() THREAD_OP_LOCK()
# define PACKAGE_OP_UNLOCK() THREAD_OP_UNLOCK()
# define ERROR_HANDLER_LOCK() THREAD_OP_LOCK()
# define ERROR_HANDLER_UNLOCK() THREAD_OP_UNLOCK()
#else
# define HASH_TABLE_LOCK(h)
# define HASH_TABLE_UNLOCK(h)
# define PACKAGE_OP_LOCK()
# define PACKAGE_OP_UNLOCK()
# define ERROR_HANDLER_LOCK()
# define ERROR_HANDLER_UNLOCK()
#endif /* ECL_THREADS */


/* read.d */
#ifdef ECL_UNICODE
#define	RTABSIZE	256		/*  read table size  */
#else
#define	RTABSIZE	CHAR_CODE_LIMIT	/*  read table size  */
#endif

/* threads.d */

#ifdef ECL_THREADS
extern ECL_API cl_object mp_suspend_loop();
extern ECL_API cl_object mp_break_suspend_loop();
#endif

/* time.d */

#define UTC_time_to_universal_time(x) ecl_plus(ecl_make_integer(x),cl_core.Jan1st1970UT)
extern cl_fixnum ecl_runtime(void);

/* unixint.d */

#ifdef ECL_DEFINE_FENV_CONSTANTS
# if defined(_MSC_VER) || defined(mingw32)
#  define HAVE_FEENABLEEXCEPT
#  include <float.h>
#  if defined(_MSC_VER)
#   define FE_DIVBYZERO EM_ZERODIVIDE
#   define FE_OVERFLOW  EM_OVERFLOW
#   define FE_UNDERFLOW EM_UNDERFLOW
#   define FE_INVALID   EM_INVALID
#   define FE_INEXACT   EM_INEXACT
typedef int fenv_t;
#  else
#   ifdef _MCW_EM
#    define MCW_EM _MCW_EM
#   else
#    define MCW_EM 0x0008001F
#   endif
#   define fenv_t int
#  endif
#  define feenableexcept(bits) { int cw = _controlfp(0,0); cw &= ~(bits); _controlfp(cw,MCW_EM); }
#  define fedisableexcept(bits) { int cw = _controlfp(0,0); cw |= (bits); _controlfp(cw,MCW_EM); }
#  define feholdexcept(bits) { *(bits) = _controlfp(0,0); _controlfp(0xffffffff, MCW_EM); }
#  define fesetenv(bits) _controlfp(*(bits), MCW_EM)
#  define feupdateenv(bits) fesetenv(bits)
# else /* !_MSC_VER */
#  ifndef HAVE_FENV_H
#   define FE_INVALID 1
#   define FE_DIVBYZERO 2
#   define FE_INEXACT 0
#   define FE_OVERFLOW 0
#   define FE_UNDERFLOW 0
#  endif /* !HAVE_FENV_H */
# endif /* !_MSC_VER */
#endif /* !ECL_DEFINE_FENV_CONSTANTS */

#define ECL_PI_D 3.14159265358979323846264338327950288
#define ECL_PI_L 3.14159265358979323846264338327950288l
#define ECL_PI2_D 1.57079632679489661923132169163975144
#define ECL_PI2_L 1.57079632679489661923132169163975144l

void ecl_deliver_fpe(void);
void ecl_interrupt_process(cl_object process, cl_object function);

/*
 * Fake several ISO C99 mathematical functions
 */

#ifndef HAVE_EXPF
# ifdef expf
#  undef expf
# endif
# define expf(x) exp((float)x)
#endif
#ifndef HAVE_LOGF
# ifdef logf
#  undef logf
# endif
# define logf(x) log((float)x)
#endif
#ifndef HAVE_SQRTF
# ifdef sqrtf
#  undef sqrtf
# endif
# define sqrtf(x) sqrt((float)x)
#endif
#ifndef HAVE_SINF
# ifdef sinf
#  undef sinf
# endif
# define sinf(x) sin((float)x)
#endif
#ifndef HAVE_COSF
# ifdef cosf
#  undef cosf
# endif
# define cosf(x) cos((float)x)
#endif
#ifndef HAVE_TANF
# ifdef tanf
#  undef tanf
# endif
# define tanf(x) tan((float)x)
#endif
#ifndef HAVE_SINHF
# ifdef sinhf
#  undef sinhf
# endif
# define sinhf(x) sinh((float)x)
#endif
#ifndef HAVE_COSHF
# ifdef coshf
#  undef coshf
# endif
# define coshf(x) cosh((float)x)
#endif
#ifndef HAVE_TANHF
# ifdef tanhf
#  undef tanhf
# endif
# define tanhf(x) tanh((float)x)
#endif

#ifndef HAVE_CEILF
# define ceilf(x) ceil((float)x)
#endif
#ifndef HAVE_FLOORF
# define floorf(x) floor((float)x)
#endif
#ifndef HAVE_FABSF
# define fabsf(x) fabs((float)x)
#endif
#ifndef HAVE_FREXPF
# define frexpf(x,y) frexp((float)x,y)
#endif
#ifndef HAVE_LDEXPF
# define ldexpf(x,y) ldexp((float)x,y)
#endif

#ifdef __cplusplus
}
#endif
