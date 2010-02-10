/* -*- mode: c; c-basic-offset: 8 -*- */
/*
    macros.c -- Macros.
*/
/*
    Copyright (c) 1984, Taiichi Yuasa and Masami Hagiya.
    Copyright (c) 1990, Giuseppe Attardi.
    Copyright (c) 2001, Juan Jose Garcia Ripoll.

    ECL is free software; you can redistribute it and/or
    modify it under the terms of the GNU Library General Public
    License as published by the Free Software Foundation; either
    version 2 of the License, or (at your option) any later version.

    See file '../Copyright' for full details.
*/

#include <ecl/ecl.h>
#include <ecl/internal.h>

/******************************* ------- ******************************/
/*
 * The are two kinds of lisp environments. One of them is by the interpreter
 * when executing bytecodes and it contains local variable and function
 * definitions.
 *
 * The other environment is shared by the bytecodes compiler and by the C
 * compiler and it contains information for the compiler, including local
 * variable definitions, and local function and macro definitions. The
 * structure is as follows:
 *
 *	env -> ( var-list . fun-list )
 *	fun-list -> ( { definition | atomic-marker }* )
 *	definition -> ( macro-name SI::MACRO { extra-data }* )
 *		    | ( function-name FUNCTION { extra-data }* )
 *		    | ( a-symbol anything { extra-data }* )
 *	atomic-marker -> CB | LB
 *
 * The main difference between the bytecode and C compilers is on the extra
 * information. On the other hand, both environments are similar enough that
 * the functions MACROEXPAND-1, MACROEXPAND and MACRO-FUNCTION can find the
 * required information.
 */

static cl_object
search_symbol_macro(cl_object name, cl_object env)
{
	for (env = CAR(env); env != Cnil; env = CDR(env)) {
		cl_object record = CAR(env);
		if (CONSP(record) && CAR(record) == name) {
			if (CADR(record) == @'si::symbol-macro')
				return CADDR(record);
			return Cnil;
		}
	}
	return si_get_sysprop(name, @'si::symbol-macro');
}

static cl_object
search_macro_function(cl_object name, cl_object env)
{
	int type = ecl_symbol_type(name);
	if (env != Cnil) {
		/* When the environment has been produced by the
		   compiler, there might be atoms/symbols signalling
		   closure and block boundaries. */
		while (!Null(env = CDR(env))) {
			cl_object record = CAR(env);
			if (CONSP(record) && CAR(record) == name) {
				cl_object tag = CADR(record);
				if (tag == @'si::macro')
					return CADDR(record);
				if (tag == @'function')
					return Cnil;
				break;
			}
		}
	}
	if (type & stp_macro) {
		return SYM_FUN(name);
	} else {
		return Cnil;
	}
}

@(defun macro_function (sym &optional env)
@
	@(return (search_macro_function(sym, env)))
@)

/*
	Analyze a form and expand it once if it is a macro form.
	VALUES(0) contains either the expansion or the original form.
	VALUES(1) is true when there was a macroexpansion.
*/

@(defun macroexpand_1 (form &optional (env Cnil))
	cl_object exp_fun = Cnil;
@
	if (ATOM(form)) {
		if (SYMBOLP(form))
			exp_fun = search_symbol_macro(form, env);
	} else {
		cl_object head = CAR(form);
		if (SYMBOLP(head))
			exp_fun = search_macro_function(head, env);
	}
	if (!Null(exp_fun)) {
		cl_object hook = ecl_symbol_value(@'*macroexpand-hook*');
		if (hook == @'funcall')
			form = funcall(3, exp_fun, form, env);
		else
			form = funcall(4, hook, exp_fun, form, env);
	}
	@(return form exp_fun)
@)

/*
	Expands a form as many times as possible and returns the
	finally expanded form.
*/
@(defun macroexpand (form &optional env)
	cl_object done, old_form;
@
	done = Cnil;
	do {
		form = cl_macroexpand_1(2, old_form = form, env);
		if (VALUES(1) == Cnil) {
			break;
		} else if (old_form == form) {
			FEerror("Infinite loop when expanding macro form ~A", 1, old_form);
		} else {
			done = Ct;
		}
	} while (1);
	@(return form done)
@)

static cl_object
or_macro(cl_object whole, cl_object env)
{
	cl_object output = Cnil;
	whole = CDR(whole);
	if (Null(whole))	/* (OR) => NIL */
		@(return Cnil);
	while (!Null(CDR(whole))) {
		output = CONS(CONS(CAR(whole), Cnil), output);
		whole = CDR(whole);
	}
	if (Null(output))	/* (OR form1) => form1 */
		@(return CAR(whole));
	/* (OR form1 ... formn forml) => (COND (form1) ... (formn) (t forml)) */
	output = CONS(cl_list(2, Ct, CAR(whole)), output);
	@(return CONS(@'cond', cl_nreverse(output)))
}

static cl_object
expand_and(cl_object whole)
{
	if (Null(whole))
		return Ct;
	if (Null(CDR(whole)))
		return CAR(whole);
	return cl_list(3, @'if', CAR(whole), expand_and(CDR(whole)));
}

static cl_object
and_macro(cl_object whole, cl_object env)
{
	@(return expand_and(CDR(whole)))
}

static cl_object
when_macro(cl_object whole, cl_object env)
{
	cl_object args = CDR(whole);
	if (ecl_endp(args))
		FEprogram_error("Syntax error: ~S.", 1, whole);
	return cl_list(3, @'if', CAR(args), CONS(@'progn', CDR(args)));
}

void
init_macros(void)
{
	ECL_SET(@'*macroexpand-hook*', @'funcall');
	ecl_def_c_macro(@'or', or_macro, 2);
	ecl_def_c_macro(@'and', and_macro, 2);
	ecl_def_c_macro(@'when', when_macro, 2);
}
