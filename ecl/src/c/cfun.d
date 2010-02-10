/* -*- mode: c; c-basic-offset: 8 -*- */
/*
    cfun.c -- Compiled functions.
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
#include <string.h>	/* for memmove() */

#include "cfun_dispatch.d"

cl_object
ecl_make_cfun(cl_objectfn_fixed c_function, cl_object name, cl_object cblock, int narg)
{
	cl_object cf;

	cf = ecl_alloc_object(t_cfunfixed);
	cf->cfunfixed.entry = dispatch_table[narg];
	cf->cfunfixed.entry_fixed = c_function;
	cf->cfunfixed.name = name;
	cf->cfunfixed.block = cblock;
        cf->cfunfixed.file = Cnil;
        cf->cfunfixed.file_position = MAKE_FIXNUM(-1);
	cf->cfunfixed.narg = narg;
	if (narg < 0 || narg > C_ARGUMENTS_LIMIT)
	    FEprogram_error("ecl_make_cfun: function requires too many arguments.",0);
	return cf;
}

cl_object
ecl_make_cfun_va(cl_objectfn c_function, cl_object name, cl_object cblock)
{
	cl_object cf;

	cf = ecl_alloc_object(t_cfun);
	cf->cfun.entry = c_function;
	cf->cfun.name = name;
	cf->cfun.block = cblock;
	cf->cfun.narg = -1;
        cf->cfun.file = Cnil;
        cf->cfun.file_position = MAKE_FIXNUM(-1);
	return cf;
}

cl_object
ecl_make_cclosure_va(cl_objectfn c_function, cl_object env, cl_object block)
{
	cl_object cc;

	cc = ecl_alloc_object(t_cclosure);
	cc->cclosure.entry = c_function;
	cc->cclosure.env = env;
	cc->cclosure.block = block;
        cc->cclosure.file = Cnil;
        cc->cclosure.file_position = MAKE_FIXNUM(-1);
	return cc;
}

void
ecl_def_c_function(cl_object sym, cl_objectfn_fixed c_function, int narg)
{
	si_fset(2, sym,
		ecl_make_cfun(c_function, sym, ecl_symbol_value(@'si::*cblock*'), narg));
}

void
ecl_def_c_macro(cl_object sym, cl_objectfn_fixed c_function, int narg)
{
	si_fset(3, sym,
		ecl_make_cfun(c_function, sym, ecl_symbol_value(@'si::*cblock*'), 2),
		Ct);
}

void
ecl_def_c_macro_va(cl_object sym, cl_objectfn c_function)
{
	si_fset(3, sym,
		ecl_make_cfun_va(c_function, sym, ecl_symbol_value(@'si::*cblock*')),
		Ct);
}

void
ecl_def_c_function_va(cl_object sym, cl_objectfn c_function)
{
	si_fset(2, sym,
		ecl_make_cfun_va(c_function, sym, ecl_symbol_value(@'si::*cblock*')));
}

cl_object
si_compiled_function_name(cl_object fun)
{
	cl_env_ptr the_env = ecl_process_env();
	cl_object output;

	switch(type_of(fun)) {
	case t_bclosure:
		fun = fun->bclosure.code;
	case t_bytecodes:
		output = fun->bytecodes.name; break;
	case t_cfun:
	case t_cfunfixed:
		output = fun->cfun.name; break;
	case t_cclosure:
		output = Cnil; break;
	default:
		FEinvalid_function(fun);
	}
	@(return output)
}

cl_object
cl_function_lambda_expression(cl_object fun)
{
	cl_env_ptr the_env = ecl_process_env();
	cl_object output, name = Cnil, lex = Cnil;

	switch(type_of(fun)) {
	case t_bclosure:
		lex = fun->bclosure.lex;
		fun = fun->bclosure.code;
	case t_bytecodes:
		name = fun->bytecodes.name;
		output = fun->bytecodes.definition;
		if (name == Cnil)
		    output = cl_cons(@'lambda', output);
		else if (name != @'si::bytecodes')
		    output = @list*(3, @'ext::lambda-block', name, output);
		break;
	case t_cfun:
	case t_cfunfixed:
		name = fun->cfun.name;
		lex = Cnil;
		output = Cnil;
		break;
	case t_cclosure:
		name = Cnil;
		lex = Ct;
		output = Cnil;
		break;
#ifdef CLOS
	case t_instance:
		if (fun->instance.isgf) {
			name = Cnil;
			lex = Cnil;
			output = Cnil;
			break;
		}
#endif
	default:
		FEinvalid_function(fun);
	}
	@(return output lex name)
}

cl_object
si_compiled_function_block(cl_object fun)
{
       cl_object output;

       switch(type_of(fun)) {
       case t_cfun:
	       output = fun->cfun.block; break;
       case t_cfunfixed:
	       output = fun->cfunfixed.block; break;
       case t_cclosure:
	       output = fun->cclosure.block; break;
       default:
	       FEerror("~S is not a C compiled function.", 1, fun);
       }
       @(return output)
}

cl_object
si_compiled_function_file(cl_object b)
{
	cl_env_ptr the_env = ecl_process_env();
 BEGIN:
        switch (type_of(b)) {
        case t_bclosure:
                b = b->bclosure.code;
                goto BEGIN;
        case t_bytecodes:
		@(return b->bytecodes.file b->bytecodes.file_position);
        case t_cfun:
		@(return b->cfun.file b->cfun.file_position);
        case t_cfunfixed:
		@(return b->cfunfixed.file b->cfunfixed.file_position);
        case t_cclosure:
		@(return b->cclosure.file b->cclosure.file_position);
        default:
		@(return Cnil Cnil);
	}
}

cl_object
ecl_set_function_source_file_info(cl_object b, cl_object source, cl_object position)
{
	cl_env_ptr the_env = ecl_process_env();
 BEGIN:
        switch (type_of(b)) {
        case t_bclosure:
                b = b->bclosure.code;
                goto BEGIN;
        case t_bytecodes:
                b->bytecodes.file = source;
                b->bytecodes.file_position = position;
                break;
        case t_cfun:
                b->cfun.file = source;
                b->cfun.file_position = position;
                break;
        case t_cfunfixed:
                b->cfunfixed.file = source;
                b->cfunfixed.file_position = position;
                break;
        case t_cclosure:
                b->cclosure.file = source;
                b->cclosure.file_position = position;
                break;
        default:
                FEerror("~S is not a compiled function.", 1, b);
	}
}

void
ecl_cmp_defmacro(cl_object fun)
{
	si_fset(3, fun->cfun.name, fun, Ct);
}

void
ecl_cmp_defun(cl_object fun)
{
	si_fset(2, fun->cfun.name, fun);
}
