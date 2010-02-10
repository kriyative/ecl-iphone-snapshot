/* -*- mode: c; c-basic-offset: 8 -*- */
#include <ecl/ecl.h>
#include <ctype.h>
#include <limits.h>
#include <ecl/internal.h>

#define CL_PACKAGE 0
#define SI_PACKAGE 4
#define EXT_PACKAGE SI_PACKAGE
#define GRAY_PACKAGE 32
#define KEYWORD_PACKAGE 8
#define MP_PACKAGE 12
#define CLOS_PACKAGE 16
#define ORDINARY_SYMBOL 0
#define CONSTANT_SYMBOL 1
#define SPECIAL_SYMBOL 2
#define FORM_SYMBOL 3

#define CL_ORDINARY	CL_PACKAGE | ORDINARY_SYMBOL
#define CL_SPECIAL	CL_PACKAGE | SPECIAL_SYMBOL
#define CL_CONSTANT	CL_PACKAGE | CONSTANT_SYMBOL
#define CL_FORM		CL_PACKAGE | ORDINARY_SYMBOL | FORM_SYMBOL
#define SI_ORDINARY	SI_PACKAGE | ORDINARY_SYMBOL
#define SI_SPECIAL	SI_PACKAGE | SPECIAL_SYMBOL
#define SI_CONSTANT	SI_PACKAGE | CONSTANT_SYMBOL
#define EXT_ORDINARY	EXT_PACKAGE | ORDINARY_SYMBOL
#define EXT_SPECIAL	EXT_PACKAGE | SPECIAL_SYMBOL
#define EXT_CONSTANT	EXT_PACKAGE | CONSTANT_SYMBOL
#define EXT_FORM	EXT_PACKAGE | ORDINARY_SYMBOL | FORM_SYMBOL
#define MP_ORDINARY	MP_PACKAGE | ORDINARY_SYMBOL
#define MP_SPECIAL	MP_PACKAGE | SPECIAL_SYMBOL
#define MP_CONSTANT	MP_PACKAGE | CONSTANT_SYMBOL
#define CLOS_ORDINARY	CLOS_PACKAGE | ORDINARY_SYMBOL
#define CLOS_SPECIAL	CLOS_PACKAGE | SPECIAL_SYMBOL
#define KEYWORD		KEYWORD_PACKAGE | CONSTANT_SYMBOL
#define GRAY_ORDINARY	GRAY_PACKAGE | ORDINARY_SYMBOL

#include "symbols_list.h"

cl_index cl_num_symbols_in_core = 0;

static unsigned char *
mangle_name(cl_object output, unsigned char *source, int l)
{
	unsigned char c;

	while (l--) {
		c = *(source++);
		if (ecl_alphanumericp(c)) {
			c = ecl_char_downcase(c);
		} else if (c == '-' || c == '_') {
			c = '_';
		} else if (c == '&') {
			c = 'A';
		} else if (c == '*') {
			c = 'X';
		} else if (c == '+') {
			c = 'P';
		} else if (c == '<') {
			c = 'L';
		} else if (c == '>') {
			c = 'G';
		} else if (c == '=') {
			c = 'E';
		} else if (c == '/') {
			c = 'N';
		} else if (c == ':') {
			c = 'X';
		} else {
			return NULL;
		}
		output->base_string.self[output->base_string.fillp++] = c;
	}
	return &output->base_string.self[output->base_string.fillp];
}

@(defun si::mangle-name (symbol &optional as_function)
	cl_index l;
	unsigned char c, *source, *dest;
	cl_object output;
	cl_object package;
	cl_object found = Cnil;
	cl_object maxarg = MAKE_FIXNUM(CALL_ARGUMENTS_LIMIT);
	cl_object minarg = MAKE_FIXNUM(0);
	bool is_symbol;
	cl_object name;
@
	name = ecl_symbol_name(symbol);
	is_symbol = Null(as_function);
	if (is_symbol) {
		cl_fixnum p;
		if (symbol == Cnil)
			@(return Ct make_constant_base_string("Cnil"))
		else if (symbol == Ct)
			@(return Ct make_constant_base_string("Ct"))
		p  = (cl_symbol_initializer*)symbol - cl_symbols;
		if (p >= 0 && p <= cl_num_symbols_in_core) {
			found = Ct;
			output = cl_format(4, Cnil,
					   make_constant_base_string("ECL_SYM(~S,~D)"),
					   name, MAKE_FIXNUM(p));
			@(return found output maxarg)
		}
	} else if (!Null(symbol)) {
		cl_object fun = symbol->symbol.gfdef;
		cl_type t = (fun == OBJNULL)? t_other : type_of(fun);
		if ((t == t_cfun || t == t_cfunfixed) && fun->cfun.block == OBJNULL) {
			for (l = 0; l <= cl_num_symbols_in_core; l++) {
				cl_object s = (cl_object)(cl_symbols + l);
				if (fun == SYM_FUN(s)) {
					symbol = s;
					found = Ct;
					if (fun->cfun.narg >= 0) {
					    minarg =
					    maxarg = MAKE_FIXNUM(fun->cfun.narg);
					}
					break;
				}
			}
		}
	}
	package = ecl_symbol_package(symbol);
	if (Null(package))
		;
	else if (package == cl_core.lisp_package)
		package = make_constant_base_string("cl");
	else if (package == cl_core.system_package)
		package = make_constant_base_string("si");
	else if (package == cl_core.keyword_package)
		package = Cnil;
	else
		package = package->pack.name;
	symbol = ecl_symbol_name(symbol);
	l      = symbol->base_string.fillp;
	source = symbol->base_string.self;
	output = ecl_alloc_simple_base_string(ecl_length(package) + l + 1);
	if (is_symbol && source[0] == '*') {
		if (l > 2 && source[l-1] == '*') l--;
		c = 'V';
		l--;
		source++;
	} else if (is_symbol && l > 2 && source[0] == '+' && source[l-1] == '+') {
		c = 'C';
		l-= 2;
		source++;
	} else if (!is_symbol) {
		c = '_';
	} else if (package == cl_core.keyword_package) {
		c = 'K';
	} else {
		c = 'S';
	}
	output->base_string.fillp = 0;
	if (!Null(package))
		if (!mangle_name(output, package->base_string.self, package->base_string.fillp))
			@(return Cnil Cnil maxarg)
	output->base_string.self[output->base_string.fillp++] = c;
	if (!(dest = mangle_name(output, source, l)))
		@(return Cnil Cnil maxarg)
	if (dest[-1] == '_')
		dest[-1] = 'M';
	*(dest++) = '\0';
	@(return found output minarg maxarg)
@)

static void
make_this_symbol(int i, cl_object s, int code, const char *name,
		 cl_objectfn fun, int narg, cl_object value)
{
	enum ecl_stype stp;
	cl_object package;
	bool form = 0;

	switch (code & 3) {
	case ORDINARY_SYMBOL: stp = stp_ordinary; break;
	case SPECIAL_SYMBOL: stp = stp_special; break;
	case CONSTANT_SYMBOL: stp = stp_constant; break;
	case FORM_SYMBOL: form = 1; stp = stp_ordinary;
	}
	switch (code & ~(int)3) {
	case CL_PACKAGE: package = cl_core.lisp_package; break;
	case SI_PACKAGE: package = cl_core.system_package; break;
	case KEYWORD_PACKAGE: package = cl_core.keyword_package; break;
	case MP_PACKAGE: package = cl_core.mp_package; break;
#ifdef CLOS
	case CLOS_PACKAGE: package = cl_core.clos_package; break;
#endif
#ifdef ECL_CLOS_STREAMS
	case GRAY_PACKAGE: package = cl_core.gray_package; break;
#endif
	default: printf("%d\n", code & ~(int)3); ecl_internal_error("Unknown package code in init_all_symbols()");
	}
	s->symbol.t = t_symbol;
	s->symbol.dynamic = 0;
	ECL_SET(s, OBJNULL);
	SYM_FUN(s) = Cnil;
	s->symbol.plist = Cnil;
	s->symbol.hpack = Cnil;
	s->symbol.stype = stp;
	s->symbol.hpack = package;
	s->symbol.name = make_constant_base_string(name);
	if (package == cl_core.keyword_package) {
		package->pack.external =
                        ecl_sethash(s->symbol.name, package->pack.external, s);
		ECL_SET(s, s);
	} else {
		int intern_flag;
		ECL_SET(s, value);
		if (ecl_find_symbol(s->symbol.name, package, &intern_flag) != Cnil
		    && intern_flag == INHERITED) {
			ecl_shadowing_import(s, package);
		} else {
			cl_import2(s, package);
		}
		cl_export2(s, package);
	}
	if (form) {
		s->symbol.stype |= stp_special_form;
	} else if (fun) {
		cl_object f;
		if (narg >= 0) {
			f = ecl_make_cfun(fun, s, NULL, narg);
		} else {
			f = ecl_make_cfun_va(fun, s, NULL);
		}
		SYM_FUN(s) = f;
	}
	cl_num_symbols_in_core = i + 1;
}

void
init_all_symbols(void)
{
	int i, code, narg;
	const char *name;
	cl_object s, value;
	cl_objectfn fun;

	/* We skip NIL and T */
	for (i = 2; cl_symbols[i].init.name != NULL; i++) {
		s = (cl_object)(cl_symbols + i);
		code = cl_symbols[i].init.type;
		name = cl_symbols[i].init.name;
		fun = (cl_objectfn)cl_symbols[i].init.fun;
		narg = cl_symbols[i].init.narg;
		value = cl_symbols[i].init.value;
		make_this_symbol(i, s, code, name, fun, narg, value);
	}
}
