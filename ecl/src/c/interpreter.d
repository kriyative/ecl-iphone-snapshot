/* -*- mode: c; c-basic-offset: 8 -*- */
/*
    interpreter.c -- Bytecode interpreter.
*/
/*
    Copyright (c) 2001, Juan Jose Garcia Ripoll.

    ECL is free software; you can redistribute it and/or
    modify it under the terms of the GNU Library General Public
    License as published by the Free Software Foundation; either
    version 2 of the License, or (at your option) any later version.

    See file '../Copyright' for full details.
*/

#include <ecl/ecl.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <ecl/ecl-inl.h>
#include <ecl/bytecodes.h>
#include <ecl/internal.h>

/* -------------------- INTERPRETER STACK -------------------- */

cl_object *
ecl_stack_set_size(cl_env_ptr env, cl_index tentative_new_size)
{
	cl_index top = env->stack_top - env->stack;
	cl_object *new_stack, *old_stack;
	cl_index safety_area = ecl_get_option(ECL_OPT_LISP_STACK_SAFETY_AREA);
	cl_index new_size = tentative_new_size + 2*safety_area;

        /* Round to page size */
        new_size = (new_size + (LISP_PAGESIZE-1))/LISP_PAGESIZE * new_size;

	if (top > new_size) {
		FEerror("Internal error: cannot shrink stack below stack top.",0);
        }

	old_stack = env->stack;
	new_stack = (cl_object *)ecl_alloc_atomic(new_size * sizeof(cl_object));

	ecl_disable_interrupts_env(env);
	memcpy(new_stack, old_stack, env->stack_size * sizeof(cl_object));
	env->stack_size = new_size;
	env->stack = new_stack;
	env->stack_top = env->stack + top;
	env->stack_limit = env->stack + (new_size - 2*safety_area);
	ecl_enable_interrupts_env(env);

	/* A stack always has at least one element. This is assumed by cl__va_start
	 * and friends, which take a sp=0 to have no arguments.
	 */
	if (top == 0) {
                *(env->stack_top++) = MAKE_FIXNUM(0);
        }
        return env->stack_top;
}

void
FEstack_underflow(void)
{
        FEerror("Internal error: stack underflow.",0);
}

void
FEstack_advance(void)
{
        FEerror("Internal error: stack advance beyond current point.",0);
}

cl_object *
ecl_stack_grow(cl_env_ptr env)
{
	return ecl_stack_set_size(env, env->stack_size + env->stack_size / 2);
}

cl_index
ecl_stack_push_values(cl_env_ptr env) {
        cl_index i = env->nvalues;
        cl_object *b = env->stack_top;
        cl_object *p = b + i;
        if (p >= env->stack_limit) {
                b = ecl_stack_grow(env);
                p = b + i;
        }
        env->stack_top = p;
        memcpy(b, env->values, i * sizeof(cl_object));
	return i;
}

void
ecl_stack_pop_values(cl_env_ptr env, cl_index n) {
        cl_object *p = env->stack_top - n;
        if (p < env->stack)
                FEstack_underflow();
        env->nvalues = n;
        env->stack_top = p;
        memcpy(env->values, p, n * sizeof(cl_object));
}

cl_object
ecl_stack_frame_open(cl_env_ptr env, cl_object f, cl_index size)
{
	cl_object *base = env->stack_top;
	if (size) {
		if ((env->stack_limit - base) < size) {
			base = ecl_stack_set_size(env, env->stack_size + size);
		}
	}
	f->frame.t = t_frame;
	f->frame.stack = env->stack;
	f->frame.base = base;
        f->frame.size = size;
	f->frame.env = env;
	env->stack_top = (base + size);
	return f;
}

void
ecl_stack_frame_push(cl_object f, cl_object o)
{
	cl_env_ptr env = f->frame.env;
	cl_object *top = env->stack_top;
	if (top >= env->stack_limit) {
		top = ecl_stack_grow(env);
	}
	*top = o;
	env->stack_top = ++top;
        f->frame.base = top - (++(f->frame.size));
        f->frame.stack = env->stack;
}

void
ecl_stack_frame_push_values(cl_object f)
{
	cl_env_ptr env = f->frame.env;
	ecl_stack_push_values(env);
        f->frame.base = env->stack_top - (f->frame.size += env->nvalues); 
	f->frame.stack = env->stack;
}

cl_object
ecl_stack_frame_pop_values(cl_object f)
{
        cl_env_ptr env = f->frame.env;
	cl_index n = f->frame.size % ECL_MULTIPLE_VALUES_LIMIT;
        cl_object o;
        env->nvalues = n;
        env->values[0] = o = Cnil;
	while (n--) {
                env->values[n] = o = f->frame.base[n];
	}
	return o;
}

void
ecl_stack_frame_close(cl_object f)
{
	if (f->frame.stack) {
		ECL_STACK_SET_INDEX(f->frame.env, f->frame.base - f->frame.stack);
	}
}

/* ------------------------------ LEXICAL ENV. ------------------------------ */

#define bind_var(env, var, val)		CONS(CONS(var, val), (env))
#define bind_function(env, name, fun) 	CONS(fun, (env))
#define bind_frame(env, id, name)	CONS(CONS(id, name), (env))

static cl_object
ecl_lex_env_get_record(register cl_object env, register int s)
{
	do {
		if (s-- == 0) return ECL_CONS_CAR(env);
		env = ECL_CONS_CDR(env);
	} while(1);
}

#define ecl_lex_env_get_var(env,x) ECL_CONS_CDR(ecl_lex_env_get_record(env,x))
#define ecl_lex_env_set_var(env,x,v) ECL_RPLACD(ecl_lex_env_get_record(env,x),(v))
#define ecl_lex_env_get_fun(env,x) ecl_lex_env_get_record(env,x)
#define ecl_lex_env_get_tag(env,x) ECL_CONS_CAR(ecl_lex_env_get_record(env,x))

/* -------------------- AIDS TO THE INTERPRETER -------------------- */

cl_object
_ecl_bytecodes_dispatch_vararg(cl_narg narg, ...)
{
        cl_object output;
        ECL_STACK_FRAME_VARARGS_BEGIN(narg, narg, frame);
        output = ecl_interpret(frame, Cnil, frame->frame.env->function);
        ECL_STACK_FRAME_VARARGS_END(frame);
        return output;
}

cl_object
_ecl_bclosure_dispatch_vararg(cl_narg narg, ...)
{
        cl_object output;
        ECL_STACK_FRAME_VARARGS_BEGIN(narg, narg, frame) {
                cl_object fun = frame->frame.env->function;
                output = ecl_interpret(frame, fun->bclosure.lex, fun->bclosure.code);
        } ECL_STACK_FRAME_VARARGS_END(frame);
        return output;
}

static cl_object
close_around(cl_object fun, cl_object lex) {
	cl_object v = ecl_alloc_object(t_bclosure);
	v->bclosure.code = fun;
	v->bclosure.lex = lex;
        v->bclosure.entry = _ecl_bclosure_dispatch_vararg;
	return v;
}

#define SETUP_ENV(the_env) { ihs.lex_env = lex_env; }

/*
 * INTERPRET-FUNCALL is one of the few ways to "exit" the interpreted
 * environment and get into the C/lisp world. Since almost all data
 * from the interpreter is kept in local variables, and frame stacks,
 * binding stacks, etc, are already handled by the C core, only the
 * lexical environment needs to be saved.
 */

#define INTERPRET_FUNCALL(reg0, the_env, frame, narg, fun) {            \
        cl_index __n = narg;                                            \
        SETUP_ENV(the_env);                                             \
        frame.stack = the_env->stack;                                   \
        frame.base = the_env->stack_top - (frame.size = __n);           \
        reg0 = ecl_apply_from_stack_frame((cl_object)&frame, fun);      \
        the_env->stack_top -= __n; }

/* -------------------- THE INTERPRETER -------------------- */

cl_object
ecl_interpret(cl_object frame, cl_object env, cl_object bytecodes)
{
	ECL_OFFSET_TABLE
        const cl_env_ptr the_env = frame->frame.env;
        volatile cl_index frame_index = 0;
	cl_opcode *vector = (cl_opcode*)bytecodes->bytecodes.code;
	cl_object *data = bytecodes->bytecodes.data;
	cl_object reg0, reg1, lex_env = env;
	cl_index narg;
	struct ecl_stack_frame frame_aux;
	volatile struct ihs_frame ihs;

        /* INV: bytecodes is of type t_bytecodes */

	ecl_cs_check(the_env, ihs);
	ecl_ihs_push(the_env, &ihs, bytecodes, lex_env);
	frame_aux.t = t_frame;
	frame_aux.stack = frame_aux.base = 0;
        frame_aux.size = 0;
        frame_aux.env = the_env;
 BEGIN:
	BEGIN_SWITCH {
	CASE(OP_NOP); {
		reg0 = Cnil;
		the_env->nvalues = 0;
		THREAD_NEXT;
	}
	/* OP_QUOTE
		Sets REG0 to an immediate value.
	*/
	CASE(OP_QUOTE); {
		GET_DATA(reg0, vector, data);
		THREAD_NEXT;
	}
	/* OP_VAR	n{arg}, var{symbol}
		Sets REG0 to the value of the n-th local.
		VAR is the name of the variable for readability purposes.
	*/
	CASE(OP_VAR); {
		int lex_env_index;
		GET_OPARG(lex_env_index, vector);
		reg0 = ecl_lex_env_get_var(lex_env, lex_env_index);
		THREAD_NEXT;
	}

	/* OP_VARS	var{symbol}
		Sets REG0 to the value of the symbol VAR.
		VAR should be either a special variable or a constant.
	*/
	CASE(OP_VARS); {
		cl_object var_name;
		GET_DATA(var_name, vector, data);
		reg0 = ECL_SYM_VAL(the_env, var_name);
		if (reg0 == OBJNULL)
			FEunbound_variable(var_name);
		THREAD_NEXT;
	}

	/* OP_CONS, OP_CAR, OP_CDR, etc
		Inlined forms for some functions which act on reg0 and stack.
	*/

	CASE(OP_CONS); {
		cl_object car = ECL_STACK_POP_UNSAFE(the_env);
		reg0 = CONS(car, reg0);
		THREAD_NEXT;
	}

	CASE(OP_CAR); {
		if (!LISTP(reg0)) FEtype_error_cons(reg0);
		reg0 = CAR(reg0);
		THREAD_NEXT;
	}

	CASE(OP_CDR); {
		if (!LISTP(reg0)) FEtype_error_cons(reg0);
		reg0 = CDR(reg0);
		THREAD_NEXT;
	}

	CASE(OP_LIST);
		reg0 = ecl_list1(reg0);

	CASE(OP_LISTA);	{
		cl_index n;
		GET_OPARG(n, vector);
		while (--n) {
			reg0 = CONS(ECL_STACK_POP_UNSAFE(the_env), reg0);
		}
		THREAD_NEXT;
	}

	CASE(OP_INT); {
		cl_fixnum n;
		GET_OPARG(n, vector);
		reg0 = MAKE_FIXNUM(n);
		THREAD_NEXT;
	}

	CASE(OP_PINT); {
		cl_fixnum n;
		GET_OPARG(n, vector);
		ECL_STACK_PUSH(the_env, MAKE_FIXNUM(n));
		THREAD_NEXT;
	}

	/* OP_PUSH
		Pushes the object in VALUES(0).
	*/
	CASE(OP_PUSH); {
		ECL_STACK_PUSH(the_env, reg0);
		THREAD_NEXT;
	}
	/* OP_PUSHV	n{arg}
		Pushes the value of the n-th local onto the stack.
	*/
	CASE(OP_PUSHV); {
		int lex_env_index;
		GET_OPARG(lex_env_index, vector);
		ECL_STACK_PUSH(the_env, ecl_lex_env_get_var(lex_env, lex_env_index));
		THREAD_NEXT;
	}

	/* OP_PUSHVS	var{symbol}
		Pushes the value of the symbol VAR onto the stack.
		VAR should be either a special variable or a constant.
	*/
	CASE(OP_PUSHVS); {
		cl_object var_name, value;
		GET_DATA(var_name, vector, data);
		value = ECL_SYM_VAL(the_env, var_name);
		if (value == OBJNULL) FEunbound_variable(var_name);
		ECL_STACK_PUSH(the_env, value);
		THREAD_NEXT;
	}

	/* OP_PUSHQ	value{object}
		Pushes "value" onto the stack.
	*/
	CASE(OP_PUSHQ); {
		cl_object aux;
		GET_DATA(aux, vector, data);
		ECL_STACK_PUSH(the_env, aux);
		THREAD_NEXT;
	}

	CASE(OP_CALLG1); {
		cl_object s;
		cl_objectfn_fixed f;
		GET_DATA(s, vector, data);
		f = SYM_FUN(s)->cfunfixed.entry_fixed;
		SETUP_ENV(the_env);
		reg0 = f(reg0);
		THREAD_NEXT;
	}

	CASE(OP_CALLG2); {
		cl_object s;
		cl_objectfn_fixed f;
		GET_DATA(s, vector, data);
		f = SYM_FUN(s)->cfunfixed.entry_fixed;
		SETUP_ENV(the_env);
		reg0 = f(ECL_STACK_POP_UNSAFE(the_env), reg0);
		THREAD_NEXT;
	}

	/* OP_CALL	n{arg}
		Calls the function in REG0 with N arguments which
		have been deposited in the stack. The first output value
		is pushed on the stack.
	*/
	CASE(OP_CALL); {
		GET_OPARG(narg, vector);
		goto DO_CALL;
	}

	/* OP_CALLG	n{arg}, name{arg}
		Calls the function NAME with N arguments which have been
		deposited in the stack. The first output value is pushed on
		the stack.
	*/
	CASE(OP_CALLG); {
		GET_OPARG(narg, vector);
		GET_DATA(reg0, vector, data);
		goto DO_CALL;
	}

	/* OP_FCALL	n{arg}
		Calls a function in the stack with N arguments which
		have been also deposited in the stack. The output values
		are left in VALUES(...)
	*/
	CASE(OP_FCALL); {
		GET_OPARG(narg, vector);
		reg0 = ECL_STACK_REF(the_env,-narg-1);
		goto DO_CALL;
	}

	/* OP_MCALL
		Similar to FCALL, but gets the number of arguments from
		the stack (They all have been deposited by OP_PUSHVALUES)
	*/
	CASE(OP_MCALL); {
		narg = fix(ECL_STACK_POP_UNSAFE(the_env));
		reg0 = ECL_STACK_REF(the_env,-narg-1);
		goto DO_CALL;
	}

	DO_CALL: {
		cl_object x = reg0;
		cl_object frame = (cl_object)&frame_aux;
		frame_aux.size = narg;
		frame_aux.base = the_env->stack_top - narg;
		SETUP_ENV(the_env);
	AGAIN:
		if (reg0 == OBJNULL || reg0 == Cnil) {
			FEundefined_function(x);
		}
		switch (type_of(reg0)) {
		case t_cfunfixed:
			if (narg != (cl_index)reg0->cfunfixed.narg)
				FEwrong_num_arguments(reg0);
			reg0 = APPLY_fixed(narg, reg0->cfunfixed.entry_fixed,
                                           frame_aux.base);
			break;
		case t_cfun:
			reg0 = APPLY(narg, reg0->cfun.entry, frame_aux.base);
			break;
		case t_cclosure:
			the_env->function = reg0;
			reg0 = APPLY(narg, reg0->cclosure.entry, frame_aux.base);
			break;
#ifdef CLOS
		case t_instance:
			switch (reg0->instance.isgf) {
			case ECL_STANDARD_DISPATCH:
				reg0 = _ecl_standard_dispatch(frame, reg0);
				break;
			case ECL_USER_DISPATCH:
				reg0 = reg0->instance.slots[reg0->instance.length - 1];
				goto AGAIN;
			default:
				FEinvalid_function(reg0);
			}
			break;
#endif
		case t_symbol:
			if (reg0->symbol.stype & stp_macro)
				FEundefined_function(x);
			reg0 = SYM_FUN(reg0);
			goto AGAIN;
		case t_bytecodes:
			reg0 = ecl_interpret(frame, Cnil, reg0);
			break;
		case t_bclosure:
			reg0 = ecl_interpret(frame, reg0->bclosure.lex, reg0->bclosure.code);
			break;
		default:
			FEinvalid_function(reg0);
		}
		ECL_STACK_POP_N_UNSAFE(the_env, narg);
		THREAD_NEXT;
	}

	/* OP_POP
		Pops a singe value pushed by a OP_PUSH* operator.
	*/
	CASE(OP_POP); {
		reg0 = ECL_STACK_POP_UNSAFE(the_env);
		THREAD_NEXT;
	}
	/* OP_POP1
		Pops a singe value pushed by a OP_PUSH* operator, ignoring it.
	*/
	CASE(OP_POP1); {
		ECL_STACK_POP_UNSAFE(the_env);
		THREAD_NEXT;
	}
	/* OP_POPREQ
		Checks the arguments list. If there are remaining arguments,
                REG0 = T and the value is on the stack, otherwise REG0 = NIL.
	*/
	CASE(OP_POPREQ); {
		if (frame_index >= frame->frame.size) {
                        FEwrong_num_arguments(bytecodes->bytecodes.name);
                }
                reg0 = frame->frame.base[frame_index++];
                THREAD_NEXT;
	}
	/* OP_POPOPT
		Checks the arguments list. If there are remaining arguments,
                REG0 = T and the value is on the stack, otherwise REG0 = NIL.
	*/
	CASE(OP_POPOPT); {
		if (frame_index >= frame->frame.size) {
                        reg0 = Cnil;
                } else {
                        ECL_STACK_PUSH(the_env,frame->frame.base[frame_index++]);
                        reg0 = Ct;
                }
                THREAD_NEXT;
	}
        /* OP_NOMORE
		No more arguments.
        */
        CASE(OP_NOMORE); {
                if (frame_index < frame->frame.size)
                        FEprogram_error("Too many arguments passed to "
                                        "function ~A~&Argument list: ~S",
                                        2, bytecodes, cl_apply(2, @'list', frame));
                THREAD_NEXT;
        }
	/* OP_POPREST
		Makes a list out of the remaining arguments.
	*/
        CASE(OP_POPREST); {
                cl_object *first = frame->frame.base + frame_index;
                cl_object *last = frame->frame.base + frame->frame.size;
                for (reg0 = Cnil; last > first; ) {
                        reg0 = CONS(*(--last), reg0);
                }
                THREAD_NEXT;
        }
	/* OP_PUSHKEYS {names-list}
		Checks the stack frame for keyword arguments.
	*/
	CASE(OP_PUSHKEYS); {
                cl_object keys_list, aok, *first, *last;
                cl_index count;
                GET_DATA(keys_list, vector, data);
                first = frame->frame.base + frame_index;
                count = frame->frame.size - frame_index;
                last = first + count;
                if (count & 1) {
                        FEprogram_error("Function ~A called with odd number "
                                        "of keyword arguments.",
                                        1, bytecodes);
                }
                aok = ECL_CONS_CAR(keys_list);
                for (; (keys_list = ECL_CONS_CDR(keys_list), !Null(keys_list)); ) {
                        cl_object name = ECL_CONS_CAR(keys_list);
                        cl_object flag = Cnil;
                        cl_object value = Cnil;
                        cl_object *p = first;
                        for (; p != last; ++p) {
                                if (*(p++) == name) {
                                        count -= 2;
                                        if (flag == Cnil) {
                                                flag = Ct;
                                                value = *p;
                                        }
                                }
                        }
                        if (flag != Cnil) ECL_STACK_PUSH(the_env, value);
                        ECL_STACK_PUSH(the_env, flag);
                }
                if (count) {
                        if (Null(aok)) {
                                int aok = 0, mask = 1;
                                cl_object *p = first;
                                for (; p != last; ++p) {
                                        if (*(p++) == @':allow-other-keys') {
                                                if (!Null(*p)) aok |= mask;
                                                mask <<= 1;
                                                count -= 2;
                                        }
                                }
                                if (count && (aok & 1) == 0) {
                                        FEprogram_error("Unknown keyword argument "
                                                        "passed to function ~S.~&"
                                                        "Argument list: ~S",
                                                        2, bytecodes,
                                                        cl_apply(2, @'list', frame));
                                }
                        }
                }
                THREAD_NEXT;
        }
	/* OP_EXIT
		Marks the end of a high level construct (BLOCK, CATCH...)
		or a function.
	*/
	CASE(OP_EXIT); {
		ecl_ihs_pop(the_env);
		return reg0;
	}
	/* OP_FLET	nfun{arg}, fun1{object}
	   ...
	   OP_UNBIND nfun
	   
	   Executes the enclosed code in a lexical enviroment extended with
	   the functions "fun1" ... "funn". Note that we only record the
	   index of the first function: the others are after this one.
	*/
	CASE(OP_FLET); {
		cl_index nfun, first;
		cl_object old_lex, *fun;
		GET_OPARG(nfun, vector);
		GET_OPARG(first, vector);
		fun = data + first;
		/* Copy the environment so that functions get it without references
		   to themselves, and then add new closures to the environment. */
		old_lex = lex_env;
		while (nfun--) {
			cl_object f = close_around(*(fun++), old_lex);
			lex_env = bind_function(lex_env, f->bytecodes.name, f);
		}
		THREAD_NEXT;
	}
	/* OP_LABELS	nfun{arg}
	   fun1{object}
	   ...
	   funn{object}
	   ...
	   OP_UNBIND n

	   Executes the enclosed code in a lexical enviroment extended with
	   the functions "fun1" ... "funn".
	*/
	CASE(OP_LABELS); {
		cl_index i, nfun, first;
		cl_object *fun, l, new_lex;
		GET_OPARG(nfun, vector);
		GET_OPARG(first, vector);
		fun = data + first;
		/* Build up a new environment with all functions */
		for (new_lex = lex_env, i = nfun; i; i--) {
			cl_object f = *(fun++);
			new_lex = bind_function(new_lex, f->bytecodes.name, f);
		}
		/* Update the closures so that all functions can call each other */
		;
		for (l = new_lex, i = nfun; i; i--) {
			ECL_RPLACA(l, close_around(ECL_CONS_CAR(l), new_lex));
			l = ECL_CONS_CDR(l);
		}
		lex_env = new_lex;
		THREAD_NEXT;
	}
	/* OP_LFUNCTION	n{arg}, function-name{symbol}
		Calls the local or global function with N arguments
		which have been deposited in the stack.
	*/
	CASE(OP_LFUNCTION); {
		int lex_env_index;
		GET_OPARG(lex_env_index, vector);
		reg0 = ecl_lex_env_get_fun(lex_env, lex_env_index);
		THREAD_NEXT;
	}

	/* OP_FUNCTION	name{symbol}
		Extracts the function associated to a symbol. The function
		may be defined in the global environment or in the local
		environment. This last value takes precedence.
	*/
	CASE(OP_FUNCTION); {
		GET_DATA(reg0, vector, data);
		reg0 = ecl_fdefinition(reg0);
		THREAD_NEXT;
	}

	/* OP_CLOSE	name{symbol}
		Extracts the function associated to a symbol. The function
		may be defined in the global environment or in the local
		environment. This last value takes precedence.
	*/
	CASE(OP_CLOSE); {
		GET_DATA(reg0, vector, data);
		reg0 = close_around(reg0, lex_env);
		THREAD_NEXT;
	}
	/* OP_GO	n{arg}, tag-ndx{arg}
		Jumps to the tag which is defined for the tagbody
		frame registered at the n-th position in the lexical
		environment. TAG-NDX is the number of tag in the list.
	*/
	CASE(OP_GO); {
		cl_index lex_env_index;
		cl_fixnum tag_ndx;
		GET_OPARG(lex_env_index, vector);
		GET_OPARG(tag_ndx, vector);
		cl_go(ecl_lex_env_get_tag(lex_env, lex_env_index),
		      MAKE_FIXNUM(tag_ndx));
		THREAD_NEXT;
	}
	/* OP_RETURN	n{arg}
		Returns from the block whose record in the lexical environment
		occuppies the n-th position.
	*/
	CASE(OP_RETURN); {
		int lex_env_index;
		cl_object block_record;
		GET_OPARG(lex_env_index, vector);
		/* record = (id . name) */
		block_record = ecl_lex_env_get_record(lex_env, lex_env_index);
		the_env->values[0] = reg0;
		cl_return_from(ECL_CONS_CAR(block_record),
			       ECL_CONS_CDR(block_record));
		THREAD_NEXT;
	}
	/* OP_THROW
		Jumps to an enclosing CATCH form whose tag matches the one
		of the THROW. The tag is taken from the stack, while the
		output values are left in VALUES(...).
	*/
	CASE(OP_THROW); {
		cl_object tag_name = ECL_STACK_POP_UNSAFE(the_env);
		the_env->values[0] = reg0;
		cl_throw(tag_name);
		THREAD_NEXT;
	}
	/* OP_JMP	label{arg}
	   OP_JNIL	label{arg}
	   OP_JT	label{arg}
	   OP_JEQ	value{object}, label{arg}
	   OP_JNEQ	value{object}, label{arg}
		Direct or conditional jumps. The conditional jumps are made
		comparing with the value of REG0.
	*/
	CASE(OP_JMP); {
		cl_oparg jump;
		GET_OPARG(jump, vector);
		vector += jump - OPARG_SIZE;
		THREAD_NEXT;
	}
	CASE(OP_JNIL); {
		cl_oparg jump;
		GET_OPARG(jump, vector);
		if (Null(reg0))
			vector += jump - OPARG_SIZE;
		THREAD_NEXT;
	}
	CASE(OP_JT); {
		cl_oparg jump;
		GET_OPARG(jump, vector);
		if (!Null(reg0))
			vector += jump - OPARG_SIZE;
		THREAD_NEXT;
	}
	CASE(OP_JEQL); {
		cl_oparg value, jump;
		GET_OPARG(value, vector);
		GET_OPARG(jump, vector);
		if (ecl_eql(reg0, data[value]))
			vector += jump - OPARG_SIZE;
		THREAD_NEXT;
	}
	CASE(OP_JNEQL); {
		cl_oparg value, jump;
		GET_OPARG(value, vector);
		GET_OPARG(jump, vector);
		if (!ecl_eql(reg0, data[value]))
			vector += jump - OPARG_SIZE;
		THREAD_NEXT;
	}

	CASE(OP_ENDP);
		if (!LISTP(reg0)) FEtype_error_list(reg0);

	CASE(OP_NOT); {
		reg0 = (reg0 == Cnil)? Ct : Cnil;
		THREAD_NEXT;
	}

	/* OP_UNBIND	n{arg}
		Undo "n" local bindings.
	*/
	CASE(OP_UNBIND); {
		cl_oparg n;
		GET_OPARG(n, vector);
		while (n--)
			lex_env = ECL_CONS_CDR(lex_env);
		THREAD_NEXT;
	}
	/* OP_UNBINDS	n{arg}
		Undo "n" bindings of special variables.
	*/
	CASE(OP_UNBINDS); {
		cl_oparg n;
		GET_OPARG(n, vector);
		ecl_bds_unwind_n(the_env, n);
		THREAD_NEXT;
	}
	/* OP_BIND	name{symbol}
	   OP_PBIND	name{symbol}
	   OP_VBIND	nvalue{arg}, name{symbol}
	   OP_BINDS	name{symbol}
	   OP_PBINDS	name{symbol}
	   OP_VBINDS	nvalue{arg}, name{symbol}
		Binds a lexical or special variable to the the
		value of REG0, the first value of the stack (PBIND) or
		to a given value in the values array.
	*/
	CASE(OP_BIND); {
		cl_object var_name;
		GET_DATA(var_name, vector, data);
		lex_env = bind_var(lex_env, var_name, reg0);
		THREAD_NEXT;
	}
	CASE(OP_PBIND); {
		cl_object var_name;
		GET_DATA(var_name, vector, data);
		lex_env = bind_var(lex_env, var_name, ECL_STACK_POP_UNSAFE(the_env));
		THREAD_NEXT;
	}
	CASE(OP_VBIND); {
		cl_index n;
		cl_object var_name;
		GET_OPARG(n, vector);
		GET_DATA(var_name, vector, data);
		lex_env = bind_var(lex_env, var_name,
				   (n < the_env->nvalues) ? the_env->values[n] : Cnil);
		THREAD_NEXT;
	}
	CASE(OP_BINDS); {
		cl_object var_name;
		GET_DATA(var_name, vector, data);
		ecl_bds_bind(the_env, var_name, reg0);
		THREAD_NEXT;
	}
	CASE(OP_PBINDS); {
		cl_object var_name;
		GET_DATA(var_name, vector, data);
		ecl_bds_bind(the_env, var_name, ECL_STACK_POP_UNSAFE(the_env));
		THREAD_NEXT;
	}
	CASE(OP_VBINDS); {
		cl_index n;
		cl_object var_name;
		GET_OPARG(n, vector);
		GET_DATA(var_name, vector, data);
		ecl_bds_bind(the_env, var_name,
			     (n < the_env->nvalues) ? the_env->values[n] : Cnil);
		THREAD_NEXT;
	}
	/* OP_SETQ	n{arg}
	   OP_PSETQ	n{arg}
	   OP_SETQS	var-name{symbol}
	   OP_PSETQS	var-name{symbol}
	   OP_VSETQ	n{arg}, nvalue{arg}
	   OP_VSETQS	var-name{symbol}, nvalue{arg}
		Sets either the n-th local or a special variable VAR-NAME,
		to either the value in REG0 (OP_SETQ[S]) or to the 
		first value on the stack (OP_PSETQ[S]), or to a given
		value from the multiple values array (OP_VSETQ[S]). Note
		that NVALUE > 0 strictly.
	*/
	CASE(OP_SETQ); {
		int lex_env_index;
		GET_OPARG(lex_env_index, vector);
		ecl_lex_env_set_var(lex_env, lex_env_index, reg0);
		THREAD_NEXT;
	}
	CASE(OP_SETQS); {
		cl_object var;
		GET_DATA(var, vector, data);
		/* INV: Not NIL, and of type t_symbol */
		if (var->symbol.stype & stp_constant)
			FEassignment_to_constant(var);
		ECL_SETQ(the_env, var, reg0);
		THREAD_NEXT;
	}
	CASE(OP_PSETQ); {
		int lex_env_index;
		GET_OPARG(lex_env_index, vector);
		ecl_lex_env_set_var(lex_env, lex_env_index, ECL_STACK_POP_UNSAFE(the_env));
		THREAD_NEXT;
	}
	CASE(OP_PSETQS); {
		cl_object var;
		GET_DATA(var, vector, data);
		/* INV: Not NIL, and of type t_symbol */
		ECL_SETQ(the_env, var, ECL_STACK_POP_UNSAFE(the_env));
		THREAD_NEXT;
	}
	CASE(OP_VSETQ); {
		cl_index lex_env_index;
		cl_oparg index;
		GET_OPARG(lex_env_index, vector);
		GET_OPARG(index, vector);
		ecl_lex_env_set_var(lex_env, lex_env_index,
				    (index >= the_env->nvalues)? Cnil : the_env->values[index]);
		THREAD_NEXT;
	}
	CASE(OP_VSETQS); {
		cl_object var, v;
		cl_oparg index;
		GET_DATA(var, vector, data);
		GET_OPARG(index, vector);
		v = (index >= the_env->nvalues)? Cnil : the_env->values[index];
		ECL_SETQ(the_env, var, v);
		THREAD_NEXT;
	}
			
	/* OP_BLOCK	constant
	   OP_DO
	   OP_CATCH

	   OP_FRAME	label{arg}
	      ...
	   OP_EXIT_FRAME
	 label:
	 */

	CASE(OP_BLOCK); {
		GET_DATA(reg0, vector, data);
		reg1 = MAKE_FIXNUM(the_env->frame_id++);
		lex_env = bind_frame(lex_env, reg1, reg0);
		THREAD_NEXT;
	}
	CASE(OP_DO); {
		reg0 = Cnil;
		reg1 = MAKE_FIXNUM(the_env->frame_id++);
		lex_env = bind_frame(lex_env, reg1, reg0);
		THREAD_NEXT;
	}
	CASE(OP_CATCH); {
		reg1 = reg0;
		lex_env = bind_frame(lex_env, reg1, reg0);
		THREAD_NEXT;
	}
	CASE(OP_FRAME); {
		cl_opcode *exit;
		GET_LABEL(exit, vector);
		ECL_STACK_PUSH(the_env, lex_env);
		ECL_STACK_PUSH(the_env, (cl_object)exit);
		if (ecl_frs_push(the_env,reg1) == 0) {
			THREAD_NEXT;
		} else {
			reg0 = the_env->values[0];
			vector = (cl_opcode *)ECL_STACK_REF(the_env,-1); /* FIXME! */
			lex_env = ECL_STACK_REF(the_env,-2);
			goto DO_EXIT_FRAME;
		}
	}
	/* OP_FRAMEID	0
	   OP_TAGBODY	n{arg}
	     label1
	     ...
	     labeln
	   label1:
	     ...
	   labeln:
	     ...
	   OP_EXIT_TAGBODY

	   High level construct for the TAGBODY form.
	*/
	CASE(OP_TAGBODY); {
		int n;
		GET_OPARG(n, vector);
		ECL_STACK_PUSH(the_env, lex_env);
		ECL_STACK_PUSH(the_env, (cl_object)vector); /* FIXME! */
		vector += n * OPARG_SIZE;
		if (ecl_frs_push(the_env,reg1) != 0) {
			/* Wait here for gotos. Each goto sets
			   VALUES(0) to an integer which ranges from 0
			   to ntags-1, depending on the tag. These
			   numbers are indices into the jump table and
			   are computed at compile time. */
			cl_opcode *table = (cl_opcode *)ECL_STACK_REF(the_env,-1);
			lex_env = ECL_STACK_REF(the_env,-2);
			table = table + fix(the_env->values[0]) * OPARG_SIZE;
			vector = table + *(cl_oparg *)table;
		}
		THREAD_NEXT;
	}
	CASE(OP_EXIT_TAGBODY); {
		reg0 = Cnil;
	}
	CASE(OP_EXIT_FRAME); {
	DO_EXIT_FRAME:
		ecl_frs_pop(the_env);
		ECL_STACK_POP_N_UNSAFE(the_env, 2);
		lex_env = ECL_CONS_CDR(lex_env);
		THREAD_NEXT;
	}
	CASE(OP_NIL); {
		reg0 = Cnil;
		THREAD_NEXT;
	}
	CASE(OP_PUSHNIL); {
		ECL_STACK_PUSH(the_env, Cnil);
		THREAD_NEXT;
	}
	CASE(OP_VALUEREG0); {
		the_env->nvalues = 1;
		THREAD_NEXT;
	}

	/* OP_PUSHVALUES
		Pushes the values output by the last form, plus the number
		of values.
	*/
	PUSH_VALUES:
	CASE(OP_PUSHVALUES); {
		cl_index i = the_env->nvalues;
		ECL_STACK_PUSH_N(the_env, i+1);
		the_env->values[0] = reg0;
		memcpy(&ECL_STACK_REF(the_env, -(i+1)), the_env->values, i * sizeof(cl_object));
		ECL_STACK_REF(the_env, -1) = MAKE_FIXNUM(the_env->nvalues);
		THREAD_NEXT;
	}
	/* OP_PUSHMOREVALUES
		Adds more values to the ones pushed by OP_PUSHVALUES.
	*/
	CASE(OP_PUSHMOREVALUES); {
		cl_index n = fix(ECL_STACK_REF(the_env,-1));
		cl_index i = the_env->nvalues;
		ECL_STACK_PUSH_N(the_env, i);
		the_env->values[0] = reg0;
		memcpy(&ECL_STACK_REF(the_env, -(i+1)), the_env->values, i * sizeof(cl_object));
		ECL_STACK_REF(the_env, -1) = MAKE_FIXNUM(n + i);
		THREAD_NEXT;
	}
	/* OP_POPVALUES
		Pops all values pushed by a OP_PUSHVALUES operator.
	*/
	CASE(OP_POPVALUES); {
		cl_object *dest = the_env->values;
		int n = the_env->nvalues = fix(ECL_STACK_POP_UNSAFE(the_env));
		if (n == 0) {
			*dest = reg0 = Cnil;
			THREAD_NEXT;
		} else if (n == 1) {
			*dest = reg0 = ECL_STACK_POP_UNSAFE(the_env);
			THREAD_NEXT;
		} else {
			ECL_STACK_POP_N_UNSAFE(the_env,n);
			memcpy(dest, &ECL_STACK_REF(the_env,0), n * sizeof(cl_object));
			reg0 = *dest;
			THREAD_NEXT;
		}
	}
	/* OP_VALUES	n{arg}
		Pop N values from the stack and store them in VALUES(...)
		Note that N is strictly > 0.
	*/
	CASE(OP_VALUES); {
		cl_fixnum n;
		GET_OPARG(n, vector);
		the_env->nvalues = n;
		ECL_STACK_POP_N_UNSAFE(the_env, n);
		memcpy(the_env->values, &ECL_STACK_REF(the_env, 0), n * sizeof(cl_object));
		reg0 = the_env->values[0];
		THREAD_NEXT;
	}
	/* OP_NTHVAL
		Set VALUES(0) to the N-th value of the VALUES(...) list.
		The index N-th is extracted from the top of the stack.
	*/
	CASE(OP_NTHVAL); {
		cl_fixnum n = fix(ECL_STACK_POP_UNSAFE(the_env));
		if (n < 0) {
			FEerror("Wrong index passed to NTH-VAL", 1, MAKE_FIXNUM(n));
		} else if ((cl_index)n >= the_env->nvalues) {
			reg0 = Cnil;
		} else if (n) {
			reg0 = the_env->values[n];
		}
		THREAD_NEXT;
	}
	/* OP_PROTECT	label
	     ...	; code to be protected and whose value is output
	   OP_PROTECT_NORMAL
	   label:
	     ...	; code executed at exit
	   OP_PROTECT_EXIT

	  High level construct for UNWIND-PROTECT. The first piece of code is
	  executed and its output value is saved. Then the second piece of code
	  is executed and the output values restored. The second piece of code
	  is always executed, even if a THROW, RETURN or GO happen within the
	  first piece of code.
	*/
	CASE(OP_PROTECT); {
		cl_opcode *exit;
		GET_LABEL(exit, vector);
		ECL_STACK_PUSH(the_env, lex_env);
		ECL_STACK_PUSH(the_env, (cl_object)exit);
		if (ecl_frs_push(the_env,ECL_PROTECT_TAG) != 0) {
			ecl_frs_pop(the_env);
			vector = (cl_opcode *)ECL_STACK_POP_UNSAFE(the_env);
			lex_env = ECL_STACK_POP_UNSAFE(the_env);
			reg0 = the_env->values[0];
			ECL_STACK_PUSH(the_env, MAKE_FIXNUM(the_env->nlj_fr - the_env->frs_top));
			goto PUSH_VALUES;
		}
		THREAD_NEXT;
	}
	CASE(OP_PROTECT_NORMAL); {
		ecl_bds_unwind(the_env, the_env->frs_top->frs_bds_top_index);
		ecl_frs_pop(the_env);
		ECL_STACK_POP_UNSAFE(the_env);
		lex_env = ECL_STACK_POP_UNSAFE(the_env);
		ECL_STACK_PUSH(the_env, MAKE_FIXNUM(1));
		goto PUSH_VALUES;
	}
	CASE(OP_PROTECT_EXIT); {
		volatile cl_fixnum n = the_env->nvalues = fix(ECL_STACK_POP_UNSAFE(the_env));
		while (n--)
			the_env->values[n] = ECL_STACK_POP_UNSAFE(the_env);
		reg0 = the_env->values[0];
		n = fix(ECL_STACK_POP_UNSAFE(the_env));
		if (n <= 0)
			ecl_unwind(the_env, the_env->frs_top + n);
		THREAD_NEXT;
	}

	/* OP_PROGV	bindings{list}
	   ...
	   OP_EXIT
	   Execute the code enclosed with the special variables in BINDINGS
	   set to the values in the list which was passed in VALUES(0).
	*/
	CASE(OP_PROGV); {
		cl_object values = reg0;
		cl_object vars = ECL_STACK_POP_UNSAFE(the_env);
		cl_index n = ecl_progv(the_env, vars, values);
		ECL_STACK_PUSH(the_env, MAKE_FIXNUM(n));
		THREAD_NEXT;
	}
	CASE(OP_EXIT_PROGV); {
		cl_index n = fix(ECL_STACK_POP_UNSAFE(the_env));
		ecl_bds_unwind(the_env, n);
		THREAD_NEXT;
	}

	CASE(OP_STEPIN); {
		cl_object form;
		cl_object a = ECL_SYM_VAL(the_env, @'si::*step-action*');
		cl_index n;
		GET_DATA(form, vector, data);
		SETUP_ENV(the_env);
		the_env->values[0] = reg0;
		n = ecl_stack_push_values(the_env);
		if (a == Ct) {
			/* We are stepping in, but must first ask the user
			 * what to do. */
			ECL_SETQ(the_env, @'si::*step-level*',
				 cl_1P(ECL_SYM_VAL(the_env, @'si::*step-level*')));
			ECL_STACK_PUSH(the_env, form);
			INTERPRET_FUNCALL(form, the_env, frame_aux, 1, @'si::stepper');
		} else if (a != Cnil) {
			/* The user told us to step over. *step-level* contains
			 * an integer number that, when it becomes 0, means
			 * that we have finished stepping over. */
			ECL_SETQ(the_env, @'si::*step-action*', cl_1P(a));
		} else {
			/* We are not inside a STEP form. This should
			 * actually never happen. */
		}
		ecl_stack_pop_values(the_env, n);
		reg0 = the_env->values[0];
		THREAD_NEXT;
	}
	CASE(OP_STEPCALL); {
		/* We are going to call a function. However, we would
		 * like to step _in_ the function. STEPPER takes care of
		 * that. */
		cl_fixnum n;
		GET_OPARG(n, vector);
		SETUP_ENV(the_env);
		if (ECL_SYM_VAL(the_env, @'si::*step-action*') == Ct) {
			ECL_STACK_PUSH(the_env, reg0);
			INTERPRET_FUNCALL(reg0, the_env, frame_aux, 1, @'si::stepper');
		}
		INTERPRET_FUNCALL(reg0, the_env, frame_aux, n, reg0);
	}
	CASE(OP_STEPOUT); {
		cl_object a = ECL_SYM_VAL(the_env, @'si::*step-action*');
		cl_index n;
		SETUP_ENV(the_env);
		the_env->values[0] = reg0;
		n = ecl_stack_push_values(the_env);
		if (a == Ct) {
			/* We exit one stepping level */
			ECL_SETQ(the_env, @'si::*step-level*',
				 cl_1M(ECL_SYM_VAL(the_env, @'si::*step-level*')));
		} else if (a == MAKE_FIXNUM(0)) {
			/* We are back to the level in which the user
			 * selected to step over. */
			ECL_SETQ(the_env, @'si::*step-action*', Ct);
		} else if (a != Cnil) {
			ECL_SETQ(the_env, @'si::*step-action*', cl_1M(a));
		} else {
			/* Not stepping, nothing to be done. */
		}
		ecl_stack_pop_values(the_env, n);
		reg0 = the_env->values[0];
		THREAD_NEXT;
	}
	}
}

@(defun si::interpreter_stack ()
@
	@(return Cnil)
@)
