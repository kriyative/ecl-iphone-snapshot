/* -*- mode: c; c-basic-offset: 8 -*- */
/*
    alloc_2.c -- Memory allocation based on the Boehmn GC.
*/
/*
    Copyright (c) 2001, Juan Jose Garcia Ripoll.

    ECL is free software; you can redistribute it and/or
    modify it under the terms of the GNU Library General Public
    License as published by the Free Software Foundation; either
    version 2 of the License, or (at your option) any later version.

    See file '../Copyright' for full details.
*/

#if defined(ECL_THREADS) && !defined(_MSC_VER)
#include <pthread.h>
#endif
#include <stdio.h>
#include <ecl/ecl.h>
#include <ecl/ecl-inl.h>
#include <ecl/internal.h>
#include <ecl/page.h>
#ifdef ECL_WSOCK
#include <winsock.h>
#endif

#ifdef GBC_BOEHM

static void finalize_queued();

/**********************************************************
 *		OBJECT ALLOCATION			  *
 **********************************************************/

void
_ecl_set_max_heap_size(cl_index new_size)
{
	const cl_env_ptr the_env = ecl_process_env();
	ecl_disable_interrupts_env(the_env);
	GC_set_max_heap_size(cl_core.max_heap_size = new_size);
	if (new_size == 0) {
		cl_index size = ecl_get_option(ECL_OPT_HEAP_SAFETY_AREA);
		cl_core.safety_region = ecl_alloc_atomic_unprotected(size);
	} else if (cl_core.safety_region) {
		GC_FREE(cl_core.safety_region);
		cl_core.safety_region = 0;
	}
	ecl_enable_interrupts_env(the_env);
}

static int failure;
static void *
out_of_memory_check(size_t requested_bytes)
{
        failure = 1;
        return 0;
}

static void
no_warnings(char *msg, void *arg)
{
}

static void *
out_of_memory(size_t requested_bytes)
{
	const cl_env_ptr the_env = ecl_process_env();
        int interrupts = the_env->disable_interrupts;
        int method = 0;
        if (!interrupts)
                ecl_disable_interrupts_env(the_env);
	/* Free the input / output buffers */
	the_env->string_pool = Cnil;
#ifdef ECL_THREADS
	/* The out of memory condition may happen in more than one thread */
        /* But then we have to ensure the error has not been solved */
	ERROR_HANDLER_LOCK();
#endif
        failure = 0;
        GC_gcollect();
        GC_oom_fn = out_of_memory_check;
        {
                void *output = GC_MALLOC(requested_bytes);
                GC_oom_fn = out_of_memory;
                if (output != 0 && failure == 0) {
                        ERROR_HANDLER_UNLOCK();
                        return output;
                }
        }
        if (cl_core.max_heap_size == 0) {
                /* We did not set any limit in the amount of memory,
                 * yet we failed, or we had some limits but we have
                 * not reached them. */
                if (cl_core.safety_region) {
                        /* We can free some memory and try handling the error */
                        GC_FREE(cl_core.safety_region);
                        the_env->string_pool = Cnil;
                        cl_core.safety_region = 0;
                        method = 0;
                } else {
                        /* No possibility of continuing */
                        method = 2;
                }
        } else {
                cl_core.max_heap_size += ecl_get_option(ECL_OPT_HEAP_SAFETY_AREA);
                GC_set_max_heap_size(cl_core.max_heap_size);
                method = 1;
        }
	ERROR_HANDLER_UNLOCK();
        ecl_enable_interrupts_env(the_env);
        switch (method) {
        case 0:	cl_error(1, @'ext::storage-exhausted');
                break;
        case 1: cl_cerror(2, make_constant_base_string("Extend heap size"),
                          @'ext::storage-exhausted');
                break;
        default:
                ecl_internal_error("Memory exhausted, quitting program.");
                break;
        }
        if (!interrupts)
                ecl_disable_interrupts_env(the_env);
        GC_set_max_heap_size(cl_core.max_heap_size +=
                             cl_core.max_heap_size / 2);
        /* Default allocation. Note that we do not allocate atomic. */
        return GC_MALLOC(requested_bytes);
}

#ifdef alloc_object
#undef alloc_object
#endif

static size_t type_size[t_end];

cl_object
ecl_alloc_object(cl_type t)
{
	const cl_env_ptr the_env = ecl_process_env();

	/* GC_MALLOC already resets objects */
	switch (t) {
	case t_fixnum:
		return MAKE_FIXNUM(0); /* Immediate fixnum */
	case t_character:
		return CODE_CHAR(' '); /* Immediate character */
#ifdef ECL_SHORT_FLOAT
	case t_shortfloat:
#endif
#ifdef ECL_LONG_FLOAT
	case t_longfloat:
#endif
	case t_singlefloat:
	case t_doublefloat: {
		cl_object obj;
		ecl_disable_interrupts_env(the_env);
		obj = (cl_object)GC_MALLOC_ATOMIC(type_size[t]);
		ecl_enable_interrupts_env(the_env);
                obj->d.t = t;
                return obj;
	}
	case t_bignum:
	case t_ratio:
	case t_complex:
	case t_symbol:
	case t_package:
	case t_hashtable:
	case t_array:
	case t_vector:
	case t_base_string:
#ifdef ECL_UNICODE
	case t_string:
#endif
	case t_bitvector:
	case t_stream:
	case t_random:
	case t_readtable:
	case t_pathname:
	case t_bytecodes:
	case t_bclosure:
	case t_cfun:
	case t_cfunfixed:
	case t_cclosure:
#ifdef CLOS
	case t_instance:
#else
	case t_structure:
#endif
#ifdef ECL_THREADS
	case t_process:
        case t_lock:
        case t_condition_variable:
#endif
#ifdef ECL_SEMAPHORES:
        case t_semaphores:
#endif
	case t_foreign:
	case t_codeblock: {
		cl_object obj;
		ecl_disable_interrupts_env(the_env);
		obj = (cl_object)GC_MALLOC(type_size[t]);
		ecl_enable_interrupts_env(the_env);
                obj->d.t = t;
                return obj;
	}
	default:
		printf("\ttype = %d\n", t);
		ecl_internal_error("alloc botch.");
	}
}

cl_object
ecl_alloc_compact_object(cl_type t, cl_index extra_space)
{
	const cl_env_ptr the_env = ecl_process_env();
        cl_index size = type_size[t];
        cl_object x;
        ecl_disable_interrupts_env(the_env);
        x = (cl_object)GC_MALLOC_ATOMIC(size + extra_space);
        ecl_enable_interrupts_env(the_env);
        x->array.t = t;
        x->array.displaced = (void*)(((char*)x) + size);
        return x;
}

cl_object
ecl_cons(cl_object a, cl_object d)
{
	const cl_env_ptr the_env = ecl_process_env();
	struct ecl_cons *obj;
	ecl_disable_interrupts_env(the_env);
	obj = GC_MALLOC(sizeof(struct ecl_cons));
	ecl_enable_interrupts_env(the_env);
#ifdef ECL_SMALL_CONS
	obj->car = a;
	obj->cdr = d;
	return ECL_PTR_CONS(obj);
#else
	obj->t = t_list;
	obj->car = a;
	obj->cdr = d;
	return (cl_object)obj;
#endif
}

cl_object
ecl_list1(cl_object a)
{
	const cl_env_ptr the_env = ecl_process_env();
	struct ecl_cons *obj;
	ecl_disable_interrupts_env(the_env);
	obj = GC_MALLOC(sizeof(struct ecl_cons));
	ecl_enable_interrupts_env(the_env);
#ifdef ECL_SMALL_CONS
	obj->car = a;
	obj->cdr = Cnil;
	return ECL_PTR_CONS(obj);
#else
	obj->t = t_list;
	obj->car = a;
	obj->cdr = Cnil;
	return (cl_object)obj;
#endif
}

cl_object
ecl_alloc_instance(cl_index slots)
{
	cl_object i;
	i = ecl_alloc_object(t_instance);
	i->instance.slots = (cl_object *)ecl_alloc(sizeof(cl_object) * slots);
	i->instance.length = slots;
        i->instance.entry = FEnot_funcallable_vararg;
        i->instance.sig = ECL_UNBOUND;
	return i;
}

void *
ecl_alloc_uncollectable(size_t size)
{
	const cl_env_ptr the_env = ecl_process_env();
	void *output;
	ecl_disable_interrupts_env(the_env);
	output = GC_MALLOC_UNCOLLECTABLE(size);
	ecl_enable_interrupts_env(the_env);
	return output;
}

void
ecl_free_uncollectable(void *pointer)
{
	const cl_env_ptr the_env = ecl_process_env();
	ecl_disable_interrupts_env(the_env);
	GC_FREE(pointer);
	ecl_enable_interrupts_env(the_env);
}

void *
ecl_alloc_unprotected(cl_index n)
{
	return GC_MALLOC_IGNORE_OFF_PAGE(n);
}

void *
ecl_alloc_atomic_unprotected(cl_index n)
{
	return GC_MALLOC_ATOMIC_IGNORE_OFF_PAGE(n);
}

void *
ecl_alloc(cl_index n)
{
	const cl_env_ptr the_env = ecl_process_env();
	void *output;
	ecl_disable_interrupts_env(the_env);
	output = ecl_alloc_unprotected(n);
	ecl_enable_interrupts_env(the_env);
	return output;
}

void *
ecl_alloc_atomic(cl_index n)
{
	const cl_env_ptr the_env = ecl_process_env();
	void *output;
	ecl_disable_interrupts_env(the_env);
	output = ecl_alloc_atomic_unprotected(n);
	ecl_enable_interrupts_env(the_env);
	return output;
}

void
ecl_dealloc(void *ptr)
{
	const cl_env_ptr the_env = ecl_process_env();
	ecl_disable_interrupts_env(the_env);
	GC_FREE(ptr);
	ecl_enable_interrupts_env(the_env);
}

static int alloc_initialized = FALSE;

extern void (*GC_push_other_roots)();
extern void (*GC_start_call_back)();
static void (*old_GC_push_other_roots)();
static void stacks_scanner();

void
init_alloc(void)
{
	int i;
	if (alloc_initialized) return;
	alloc_initialized = TRUE;
	/*
	 * Garbage collector restrictions: we set up the garbage collector
	 * library to work as follows
	 *
	 * 1) The garbage collector shall not scan shared libraries
	 *    explicitely.
	 * 2) We only detect objects that are referenced by a pointer to
	 *    the begining or to the first byte.
	 * 3) Out of the incremental garbage collector, we only use the
	 *    generational component.
	 */
	GC_no_dls = 1;
	GC_all_interior_pointers = 0;
	GC_time_limit = GC_TIME_UNLIMITED;
	GC_init();
	if (ecl_get_option(ECL_OPT_INCREMENTAL_GC)) {
		GC_enable_incremental();
	}
	GC_register_displacement(1);
#if 0
	GC_init_explicit_typing();
#endif
	GC_clear_roots();
	GC_disable();
	GC_set_max_heap_size(cl_core.max_heap_size = ecl_get_option(ECL_OPT_HEAP_SIZE));
        /* Save some memory for the case we get tight. */
	if (cl_core.max_heap_size == 0) {
		cl_index size = ecl_get_option(ECL_OPT_HEAP_SAFETY_AREA);
		cl_core.safety_region = ecl_alloc_atomic_unprotected(size);
	} else if (cl_core.safety_region) {
		cl_core.safety_region = 0;
	}

#define init_tm(x,y,z) type_size[x] = (z)
	for (i = 0; i < t_end; i++) {
		type_size[i] = 0;
	}
	init_tm(t_singlefloat, "SINGLE-FLOAT", /* 8 */
		sizeof(struct ecl_singlefloat));
	init_tm(t_list, "CONS", sizeof(struct ecl_cons)); /* 12 */
	init_tm(t_doublefloat, "DOUBLE-FLOAT", /* 16 */
		sizeof(struct ecl_doublefloat));
	init_tm(t_bytecodes, "BYTECODES", sizeof(struct ecl_bytecodes));
	init_tm(t_bclosure, "BCLOSURE", sizeof(struct ecl_bclosure));
	init_tm(t_base_string, "BASE-STRING", sizeof(struct ecl_base_string)); /* 20 */
#ifdef ECL_UNICODE
	init_tm(t_string, "STRING", sizeof(struct ecl_string));
#endif
	init_tm(t_array, "ARRAY", sizeof(struct ecl_array)); /* 24 */
	init_tm(t_pathname, "PATHNAME", sizeof(struct ecl_pathname)); /* 28 */
	init_tm(t_symbol, "SYMBOL", sizeof(struct ecl_symbol)); /* 32 */
	init_tm(t_package, "PACKAGE", sizeof(struct ecl_package)); /* 36 */
	init_tm(t_codeblock, "CODEBLOCK", sizeof(struct ecl_codeblock));
	init_tm(t_bignum, "BIGNUM", sizeof(struct ecl_bignum));
	init_tm(t_ratio, "RATIO", sizeof(struct ecl_ratio));
	init_tm(t_complex, "COMPLEX", sizeof(struct ecl_complex));
	init_tm(t_hashtable, "HASH-TABLE", sizeof(struct ecl_hashtable));
	init_tm(t_vector, "VECTOR", sizeof(struct ecl_vector));
	init_tm(t_bitvector, "BIT-VECTOR", sizeof(struct ecl_vector));
	init_tm(t_stream, "STREAM", sizeof(struct ecl_stream));
	init_tm(t_random, "RANDOM-STATE", sizeof(struct ecl_random));
	init_tm(t_readtable, "READTABLE", sizeof(struct ecl_readtable));
	init_tm(t_cfun, "CFUN", sizeof(struct ecl_cfun));
	init_tm(t_cfunfixed, "CFUN", sizeof(struct ecl_cfunfixed));
	init_tm(t_cclosure, "CCLOSURE", sizeof(struct ecl_cclosure));
#ifndef CLOS
	init_tm(t_structure, "STRUCTURE", sizeof(struct ecl_structure));
#else
	init_tm(t_instance, "INSTANCE", sizeof(struct ecl_instance));
#endif /* CLOS */
	init_tm(t_foreign, "FOREIGN", sizeof(struct ecl_foreign));
#ifdef ECL_THREADS
	init_tm(t_process, "PROCESS", sizeof(struct ecl_process));
	init_tm(t_lock, "LOCK", sizeof(struct ecl_lock));
	init_tm(t_condition_variable, "CONDITION-VARIABLE",
                sizeof(struct ecl_condition_variable));
#endif
#ifdef ECL_SEMAPHORES
	init_tm(t_semaphores, "SEMAPHORES", sizeof(struct ecl_semaphores));
#endif
#ifdef ECL_LONG_FLOAT
	init_tm(t_longfloat, "LONG-FLOAT", sizeof(struct ecl_long_float));
#endif

	old_GC_push_other_roots = GC_push_other_roots;
	GC_push_other_roots = stacks_scanner;
	GC_start_call_back = (void (*)())finalize_queued;
	GC_java_finalization = 1;
        GC_oom_fn = out_of_memory;
        GC_set_warn_proc(no_warnings);
	GC_enable();
}

/**********************************************************
 *		FINALIZATION				  *
 **********************************************************/

static void
standard_finalizer(cl_object o)
{
	switch (o->d.t) {
#ifdef ENABLE_DLOPEN
	case t_codeblock:
		ecl_library_close(o);
		break;
#endif
	case t_stream:
		cl_close(1, o);
		break;
	case t_weak_pointer:
		GC_unregister_disappearing_link(&(o->weak.value));
		break;
#ifdef ECL_THREADS
	case t_lock: {
		const cl_env_ptr the_env = ecl_process_env();
		ecl_disable_interrupts_env(the_env);
#if defined(_MSC_VER) || defined(mingw32)
		CloseHandle(o->lock.mutex);
#else
		pthread_mutex_destroy(&o->lock.mutex);
#endif
		ecl_enable_interrupts_env(the_env);
		break;
	}
	case t_condition_variable: {
		const cl_env_ptr the_env = ecl_process_env();
		ecl_disable_interrupts_env(the_env);
#if defined(_MSC_VER) || defined(mingw32)
		CloseHandle(o->condition_variable.cv);
#else
		pthread_cond_destroy(&o->condition_variable.cv);
#endif
		ecl_enable_interrupts_env(the_env);
		break;
	}
#endif
#ifdef ECL_SEMAPHORES
	case t_semaphore: {
                mp_semaphore_close(o);
		break;
	}
#endif
	default:;
	}
}

static void
group_finalizer(cl_object l, cl_object no_data)
{
	CL_NEWENV_BEGIN {
		while (CONSP(l)) {
			cl_object record = ECL_CONS_CAR(l);
			cl_object o = ECL_CONS_CAR(record);
			cl_object procedure = ECL_CONS_CDR(record);
			l = ECL_CONS_CDR(l);
			if (procedure != Ct) {
				funcall(2, procedure, o);
			}
			standard_finalizer(o);
		}
	} CL_NEWENV_END;
}

static void
queueing_finalizer(cl_object o, cl_object finalizer)
{
	if (finalizer != Cnil && finalizer != NULL) {
		/* Only nonstandard finalizers are queued */
		if (finalizer == Ct) {
			CL_NEWENV_BEGIN {
				standard_finalizer(o);
			} CL_NEWENV_END;
		} else {
			/* Note the way we do this: finalizers might
			   get executed as a consequence of these calls. */
			volatile cl_object aux = ACONS(o, finalizer, Cnil);
			cl_object l = cl_core.to_be_finalized;
			if (Null(l)) {
				const cl_env_ptr the_env = ecl_process_env();
				GC_finalization_proc ofn;
				void *odata;
				cl_core.to_be_finalized = aux;
				ecl_disable_interrupts_env(the_env);
				GC_register_finalizer_no_order(aux, (GC_finalization_proc*)group_finalizer, NULL, &ofn, &odata);
				ecl_enable_interrupts_env(the_env);
			} else {
				ECL_RPLACD(l, aux);
			}
		}
	}
}

cl_object
si_get_finalizer(cl_object o)
{
	const cl_env_ptr the_env = ecl_process_env();
	cl_object output;
	GC_finalization_proc ofn;
	void *odata;
	ecl_disable_interrupts_env(the_env);
	GC_register_finalizer_no_order(o, (GC_finalization_proc)0, 0, &ofn, &odata);
	if (ofn == 0) {
		output = Cnil;
	} else if (ofn == (GC_finalization_proc)queueing_finalizer) {
		output = (cl_object)odata;
	} else {
		output = Cnil;
	}
	GC_register_finalizer_no_order(o, ofn, odata, &ofn, &odata);
	ecl_enable_interrupts_env(the_env);
	@(return output)
}

void
ecl_set_finalizer_unprotected(cl_object o, cl_object finalizer)
{
	GC_finalization_proc ofn;
	void *odata;
	if (finalizer == Cnil) {
		GC_register_finalizer_no_order(o, (GC_finalization_proc)0,
					       0, &ofn, &odata);
	} else {
		GC_finalization_proc newfn;
		newfn = (GC_finalization_proc)queueing_finalizer;
		GC_register_finalizer_no_order(o, newfn, finalizer,
					       &ofn, &odata);
	}
}

cl_object
si_set_finalizer(cl_object o, cl_object finalizer)
{
	const cl_env_ptr the_env = ecl_process_env();
	ecl_disable_interrupts_env(the_env);
        ecl_set_finalizer_unprotected(o, finalizer);
	ecl_enable_interrupts_env(the_env);
	@(return)
}

cl_object
si_gc_stats(cl_object enable)
{
	const cl_env_ptr the_env = ecl_process_env();
	cl_object old_status = cl_core.gc_stats? Ct : Cnil;
	cl_core.gc_stats = (enable != Cnil);
	if (cl_core.bytes_consed == Cnil) {
#ifndef WITH_GMP
		cl_core.bytes_consed = MAKE_FIXNUM(0);
		cl_core.gc_counter = MAKE_FIXNUM(0);
#else
		cl_core.bytes_consed = ecl_alloc_object(t_bignum);
		mpz_init2(cl_core.bytes_consed->big.big_num, 128);
		cl_core.gc_counter = ecl_alloc_object(t_bignum);
		mpz_init2(cl_core.gc_counter->big.big_num, 128);
#endif
	}
	@(return
	  _ecl_big_register_normalize(cl_core.bytes_consed)
	  _ecl_big_register_normalize(cl_core.gc_counter)
	  old_status)
}

/*
 * This procedure is invoked after garbage collection. It invokes
 * finalizers for all objects that are to be reclaimed by the
 * colector. Note that we cannot cons because this procedure is
 * invoked with the garbage collection lock on.
 */
static void
finalize_queued()
{
        cl_core.to_be_finalized = Cnil;
	if (cl_core.gc_stats) {
#ifdef WITH_GMP
		/* Sorry, no gc stats if you do not use bignums */
#if GBC_BOEHM == 0
		mpz_add_ui(cl_core.bytes_consed->big.big_num,
			   cl_core.bytes_consed->big.big_num,
			   GC_get_bytes_since_gc() * sizeof(cl_index));
#else
		/* This is not accurate and may wrap around. We try
		   to detect this assuming that an overflow in an
		   unsigned integer will produce an smaller
		   integer.*/
		static cl_index bytes = 0;
		cl_index new_bytes = GC_get_total_bytes();
		if (bytes > new_bytes) {
			cl_index wrapped;
			wrapped = ~((cl_index)0) - bytes;
			mpz_add_ui(cl_core.bytes_consed->big.big_num,
				   cl_core.bytes_consed->big.big_num,
				   wrapped);
			bytes = new_bytes;
		}
		mpz_add_ui(cl_core.bytes_consed->big.big_num,
			   cl_core.bytes_consed->big.big_num,
			   new_bytes - bytes);
#endif
		mpz_add_ui(cl_core.gc_counter->big.big_num,
			   cl_core.gc_counter->big.big_num,
			   1);
#endif
	}
}


/**********************************************************
 *		GARBAGE COLLECTOR			  *
 **********************************************************/

static void
ecl_mark_env(struct cl_env_struct *env)
{
#if 1
	if (env->stack) {
		GC_push_conditional((void *)env->stack, (void *)env->stack_top, 1);
		GC_set_mark_bit((void *)env->stack);
	}
	if (env->frs_top) {
		GC_push_conditional((void *)env->frs_org, (void *)(env->frs_top+1), 1);
		GC_set_mark_bit((void *)env->frs_org);
	}
	if (env->bds_top) {
		GC_push_conditional((void *)env->bds_org, (void *)(env->bds_top+1), 1);
		GC_set_mark_bit((void *)env->bds_org);
	}
#endif
	/*memset(env->values[env->nvalues], 0, (64-env->nvalues)*sizeof(cl_object));*/
#if defined(ECL_THREADS) && !defined(ECL_USE_MPROTECT) && !defined(ECL_USE_GUARD_PAGE)
	/* When using threads, "env" is a pointer to memory allocated by ECL. */
	GC_push_conditional((void *)env, (void *)(env + 1), 1);
	GC_set_mark_bit((void *)env);
#else
	/* When not using threads, "env" is mmaped or statically allocated. */
	GC_push_all((void *)env, (void *)(env + 1));
#endif
}

static void
stacks_scanner()
{
	cl_object l;
	l = cl_core.libraries;
	if (l) {
		for (; l != Cnil; l = ECL_CONS_CDR(l)) {
			cl_object dll = ECL_CONS_CAR(l);
			if (dll->cblock.locked) {
				GC_push_conditional((void *)dll, (void *)(&dll->cblock + 1), 1);
				GC_set_mark_bit((void *)dll);
			}
		}
	}
	GC_push_all((void *)(&cl_core), (void *)(&cl_core + 1));
	GC_push_all((void *)cl_symbols, (void *)(cl_symbols + cl_num_symbols_in_core));
#ifdef ECL_THREADS
	l = cl_core.processes;
	if (l == OBJNULL) {
		ecl_mark_env(&cl_env);
	} else {
		l = cl_core.processes;
		loop_for_on_unsafe(l) {
			cl_object process = ECL_CONS_CAR(l);
			struct cl_env_struct *env = process->process.env;
			ecl_mark_env(env);
		} end_loop_for_on;
	}
#else
	ecl_mark_env(&cl_env);
#endif
	if (old_GC_push_other_roots)
		(*old_GC_push_other_roots)();
}

/**********************************************************
 *		GARBAGE COLLECTION			  *
 **********************************************************/

void
ecl_register_root(cl_object *p)
{
	const cl_env_ptr the_env = ecl_process_env();
	ecl_disable_interrupts_env(the_env);
	GC_add_roots((char*)p, (char*)(p+1));
	ecl_enable_interrupts_env(the_env);
}

cl_object
si_gc(cl_object area)
{
	const cl_env_ptr the_env = ecl_process_env();
	ecl_disable_interrupts_env(the_env);
	GC_gcollect();
	ecl_enable_interrupts_env(the_env);
	@(return)
}

cl_object
si_gc_dump()
{
	const cl_env_ptr the_env = ecl_process_env();
	ecl_disable_interrupts_env(the_env);
	GC_dump();
	ecl_enable_interrupts_env(the_env);
	@(return)
}

/**********************************************************************
 * WEAK POINTERS
 */

static cl_object
ecl_alloc_weak_pointer(cl_object o)
{
	const cl_env_ptr the_env = ecl_process_env();
	struct ecl_weak_pointer *obj;
	ecl_disable_interrupts_env(the_env);
	obj = GC_MALLOC_ATOMIC(sizeof(struct ecl_weak_pointer));
	ecl_enable_interrupts_env(the_env);
	obj->t = t_weak_pointer;
	obj->value = o;
	GC_general_register_disappearing_link(&(obj->value), (void*)o);
	return (cl_object)obj;
}

cl_object
si_make_weak_pointer(cl_object o)
{
	cl_object pointer = ecl_alloc_weak_pointer(o);
	si_set_finalizer(o, pointer);
	@(return pointer);
}

static cl_object
ecl_weak_pointer_value(cl_object o)
{
	return o->weak.value;
}

cl_object
si_weak_pointer_value(cl_object o)
{
	cl_object value;
	if (type_of(o) != t_weak_pointer)
		FEwrong_type_argument(@'ext::weak-pointer', o);
	value = (cl_object)GC_call_with_alloc_lock((GC_fn_type)ecl_weak_pointer_value, o);
	@(return (value? value : Cnil));
}

#endif /* GBC_BOEHM */
