/* -*- mode: c; c-basic-offset: 8 -*- */
/*
    disassembler.c -- Byte compiler and function evaluator
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
#include <ecl/ecl-inl.h>
#include <ecl/bytecodes.h>

static cl_opcode *disassemble(cl_object bytecodes, cl_opcode *vector);

static cl_opcode *base = NULL;

static void
print_noarg(const char *s) {
	ecl_princ_str(s, Cnil);
}

static void
print_oparg(const char *s, cl_fixnum n) {
	ecl_princ_str(s, Cnil);
	ecl_princ(MAKE_FIXNUM(n), Cnil);
}

static void
print_arg(const char *s, cl_object x) {
	ecl_princ_str(s, Cnil);
	ecl_princ(x, Cnil);
}

static void
print_oparg_arg(const char *s, cl_fixnum n, cl_object x) {
	ecl_princ_str(s, Cnil);
	ecl_princ(MAKE_FIXNUM(n), Cnil);
	ecl_princ_str(",", Cnil);
	ecl_princ(x, Cnil);
}

static void
disassemble_lambda(cl_object bytecodes) {
	const cl_env_ptr env = ecl_process_env();
	cl_object *data;
	cl_opcode *vector;

	ecl_bds_bind(env, @'*print-pretty*', Cnil);

	/* Print required arguments */
	data = bytecodes->bytecodes.data;

	/* Name of LAMBDA */
	print_arg("\nName:\t\t", bytecodes->bytecodes.name);
	if (bytecodes->bytecodes.name == OBJNULL ||
	    bytecodes->bytecodes.name == @'si::bytecodes') {
		print_noarg("\nEvaluated form:");
		goto NO_ARGS;
	}

	/* Print aux arguments */
	print_arg("\nDocumentation:\t", *(data++));
	print_arg("\nDeclarations:\t", *(data++));

 NO_ARGS:
	base = vector = (cl_opcode *)bytecodes->bytecodes.code;
	disassemble(bytecodes, vector);

	ecl_bds_unwind1(env);
}

/* -------------------- DISASSEMBLER CORE -------------------- */

/* OP_FLET	nfun{arg}, fun1{object}
   ...

	Executes the enclosed code in a lexical enviroment extended with
	the functions "fun1" ... "funn".
*/
static cl_opcode *
disassemble_flet(cl_object bytecodes, cl_opcode *vector) {
	cl_index nfun, first;
	cl_object *data;
	GET_OPARG(nfun, vector);
	GET_OPARG(first, vector);
	data = bytecodes->bytecodes.data + first;
	print_noarg("FLET");
	while (nfun--) {
		cl_object fun = *(data++);
		print_arg("\n\tFLET\t", fun->bytecodes.name);
	}
	return vector;
}

/* OP_LABELS	nfun{arg}, fun1{object}
   ...

	Executes the enclosed code in a lexical enviroment extended with
	the functions "fun1" ... "funn".
*/
static cl_opcode *
disassemble_labels(cl_object bytecodes, cl_opcode *vector) {
	cl_index nfun, first;
	cl_object *data;
	GET_OPARG(nfun, vector);
	GET_OPARG(first, vector);
	data = bytecodes->bytecodes.data + first;
	print_noarg("LABELS");
	while (nfun--) {
		cl_object fun = *(data++);
		print_arg("\n\tLABELS\t", fun->bytecodes.name);
	}
	return vector;
}

/* OP_PROGV	bindings{list}
   ...
   OP_EXIT
	Execute the code enclosed with the special variables in BINDINGS
	set to the values in the list which was passed in VALUES(0).
*/
static cl_opcode *
disassemble_progv(cl_object bytecodes, cl_opcode *vector) {
	print_noarg("PROGV");
	vector = disassemble(bytecodes, vector);
	print_noarg("\t\t; progv");
	return vector;
}

/* OP_TAGBODY	n{arg}
   label1
   ...
   labeln
label1:
   ...
labeln:
   ...
   OP_EXIT

	High level construct for the TAGBODY form.
*/
static cl_opcode *
disassemble_tagbody(cl_object bytecodes, cl_opcode *vector) {
	cl_index i, ntags;
	cl_opcode *destination;
	GET_OPARG(ntags, vector);
	print_noarg("TAGBODY");
	for (i=0; i<ntags; i++) {
		GET_LABEL(destination, vector);
		ecl_princ_str("\n\tTAG\t", Ct);
		ecl_princ(MAKE_FIXNUM(i), Ct);
		ecl_princ_str(" @@ ", Ct);
		ecl_princ(MAKE_FIXNUM(destination - base), Ct);
	}
	vector = disassemble(bytecodes, vector);
	print_noarg("\t\t; tagbody");

	return vector;
}

static cl_opcode *
disassemble(cl_object bytecodes, cl_opcode *vector) {
	const char *string;
	cl_object o;
	cl_fixnum n, m;
	cl_object line_format;
	cl_object *data = bytecodes->bytecodes.data;
	cl_object line_no;

	if (cl_fboundp(@'si::formatter-aux') != Cnil)
		line_format = make_constant_base_string("~%~4d\t");
	else
		line_format = Cnil;
 BEGIN:
	if (1) {
		line_no = MAKE_FIXNUM(vector-base);
	} else {
		line_no = @'*';
	}
	if (line_format != Cnil) {
		cl_format(3, Ct, line_format, line_no);
	} else {
		ecl_princ_char('\n', Ct);
		ecl_princ(line_no, Ct);
		ecl_princ_char('\t', Ct);
	}
	switch (GET_OPCODE(vector)) {

	/* OP_NOP
		Sets VALUES(0) = NIL and NVALUES = 1
	*/
	case OP_NOP:		string = "NOP";	goto NOARG;

	case OP_INT:		string = "QUOTE\t";
				GET_OPARG(n, vector);
				goto OPARG;

	case OP_PINT:		string = "PUSH\t";
				GET_OPARG(n, vector);
				goto OPARG;

	/* OP_QUOTE
		Sets VALUES(0) to an immediate value.
	*/
	case OP_QUOTE:		string = "QUOTE\t";
				GET_DATA(o, vector, data);
				goto ARG;

	/* OP_VAR	n{arg}
		Sets NVALUES=1 and VALUES(0) to the value of the n-th local.
	*/
	case OP_VAR:		string = "VAR\t";
				GET_OPARG(n, vector);
				goto OPARG;

	/* OP_VARS	var{symbol}
		Sets NVALUES=1 and VALUES(0) to the value of the symbol VAR.
		VAR should be either a special variable or a constant.
	*/
	case OP_VARS:		string = "VARS\t";
				GET_DATA(o, vector, data);
				goto ARG;

	/* OP_PUSH
		Pushes the object in VALUES(0).
	*/
	case OP_PUSH:		string = "PUSH\tVALUES(0)";
				goto NOARG;

	case OP_VALUEREG0:	string = "SET\tVALUES(0),REG0";
				goto NOARG;

	/* OP_PUSHV	n{arg}
		Pushes the value of the n-th local onto the stack.
	*/
	case OP_PUSHV:		string = "PUSHV\t";
				GET_OPARG(n, vector);
				goto OPARG;

	/* OP_PUSHVS	var{symbol}
		Pushes the value of the symbol VAR onto the stack.
		VAR should be either a special variable or a constant.
	*/
	case OP_PUSHVS:		string = "PUSHVS\t";
				GET_DATA(o, vector, data);
				goto ARG;

	/* OP_PUSHQ	value{object}
		Pushes "value" onto the stack.
	*/
	case OP_PUSHQ:		string = "PUSH\t'";
				GET_DATA(o, vector, data);
				goto ARG;

	/* OP_PUSHVALUES
		Pushes the values output by the last form, plus the number
		of values.
	*/
	case OP_PUSHVALUES:	string = "PUSH\tVALUES";
				goto NOARG;
	/* OP_PUSHMOREVALUES
		Adds more values to the ones pushed by OP_PUSHVALUES.
	*/
	case OP_PUSHMOREVALUES:	string = "PUSH\tMORE VALUES";
				goto NOARG;
	/* OP_POP
		Pops a single value pushed by a OP_PUSH[V[S]] operator.
	*/
	case OP_POP:		string = "POP";
				goto NOARG;
	/* OP_POP1
		Pops a single value pushed by a OP_PUSH[V[S]] operator.
	*/
	case OP_POP1:		string = "POP1";
				goto NOARG;
	/* OP_POPVALUES
		Pops all values pushed by a OP_PUSHVALUES operator.
	*/
	case OP_POPVALUES:	string = "POP\tVALUES";
				goto NOARG;

	case OP_BLOCK:		string = "BLOCK\t";
				GET_DATA(o, vector, data);
				goto ARG;
	case OP_CATCH:		string = "CATCH\tREG0";
				goto NOARG;
	case OP_DO:		string = "BLOCK\t";
				o = Cnil;
				goto ARG;
	case OP_FRAME:		string = "FRAME\t";
				goto JMP;

	/* OP_CALL	n{arg}
		Calls the function in VALUES(0) with N arguments which
		have been deposited in the stack. The output values
		are left in VALUES(...)
	*/
	case OP_CALL:		string = "CALL\t";
				GET_OPARG(n, vector);
				goto OPARG;

	/* OP_CALLG	n{arg}, name{arg}
		Calls the function NAME with N arguments which have been
		deposited in the stack. The output values are left in VALUES.
	*/
	case OP_CALLG:		string = "CALLG\t";
				GET_OPARG(n, vector);
				GET_DATA(o, vector, data);
				goto OPARG_ARG;

	/* OP_FCALL	n{arg}
		Calls the function in the stack with N arguments which
		have been also deposited in the stack. The output values
		are left in VALUES(...)
	*/
	case OP_STEPCALL:
	case OP_FCALL:		string = "FCALL\t";
				GET_OPARG(n, vector);
				goto OPARG;

	/* OP_MCALL
		Similar to FCALL, but gets the number of arguments from
		the stack (They all have been deposited by OP_PUSHVALUES)
	*/
	case OP_MCALL:		string = "MCALL";
				goto NOARG;

	/* OP_POPREQ
		Extracts next required argument.
	*/
	case OP_POPREQ:		string = "POP\tREQ";
				goto NOARG;
	/* OP_NOMORE
		Ensure there are no more arguments.
	*/
	case OP_NOMORE:		string = "NOMORE";
				goto NOARG;
	/* OP_POPOPT
		Extracts next optional argument.
	*/
	case OP_POPOPT:		string = "POP\tOPT";
				goto NOARG;
	/* OP_POPREST
		Extracts list of remaining arguments.
	*/
	case OP_POPREST:	string = "POP\tREST";
				goto NOARG;
        /* OP_PUSHKEYS
        	Parses the keyword arguments
        */
        case OP_PUSHKEYS:	string = "PUSH\tKEYS ";
				GET_DATA(o, vector, data);
                		goto ARG;

	/* OP_EXIT
		Marks the end of a high level construct
	*/
	case OP_EXIT:		print_noarg("EXIT");
				return vector;
	/* OP_EXIT_FRAME
		Marks the end of a high level construct (BLOCK, CATCH...)
	*/
	case OP_EXIT_FRAME:	string = "EXIT\tFRAME";
				goto NOARG;
	/* OP_EXIT_TAGBODY
		Marks the end of a high level construct (TAGBODY)
	*/
	case OP_EXIT_TAGBODY:	print_noarg("EXIT\tTAGBODY");
				return vector;

	case OP_FLET:		vector = disassemble_flet(bytecodes, vector);
				break;
	case OP_LABELS:		vector = disassemble_labels(bytecodes, vector);
				break;

	/* OP_LFUNCTION	name{symbol}
		Extracts the function associated to a symbol. The function
		may be defined in the global environment or in the local
		environment. This last value takes precedence.
	*/
	case OP_LFUNCTION:	string = "LOCFUNC\t";
				GET_OPARG(n, vector);
				goto OPARG;

	/* OP_FUNCTION	name{symbol}
		Extracts the function associated to a symbol. The function
		may be defined in the global environment or in the local
		environment. This last value takes precedence.
	*/
	case OP_FUNCTION:	string = "SYMFUNC\t";
				GET_DATA(o, vector, data);
				goto ARG;

	/* OP_CLOSE	name{arg}
		Extracts the function associated to a symbol. The function
		may be defined in the global environment or in the local
		environment. This last value takes precedence.
	*/
	case OP_CLOSE:		string = "CLOSE\t";
				GET_DATA(o, vector, data);
				goto ARG;

	/* OP_GO	n{arg}
	   OP_QUOTE	tag-name{symbol}
		Jumps to the tag which is defined at the n-th position in
		the lexical environment. TAG-NAME is kept for debugging
		purposes.
	*/
	case OP_GO:		string = "GO\t";
				GET_OPARG(n, vector);
				GET_DATA(o, vector, data);
				goto OPARG_ARG;

	/* OP_RETURN	n{arg}
		Returns from the block whose record in the lexical environment
		occuppies the n-th position.
	*/
	case OP_RETURN:		string = "RETFROM";
				GET_OPARG(n, vector);
				goto OPARG;

	/* OP_THROW
		Jumps to an enclosing CATCH form whose tag matches the one
		of the THROW. The tag is taken from the stack, while the
		output values are left in VALUES(...).
	*/
	case OP_THROW:		string = "THROW";
				goto NOARG;

	/* OP_JMP	label{arg}
	   OP_JNIL	label{arg}
	   OP_JT	label{arg}
	   OP_JEQ	label{arg}, value{object}
	   OP_JNEQ	label{arg}, value{object}
		Direct or conditional jumps. The conditional jumps are made
		comparing with the value of VALUES(0).
	*/
	case OP_JMP:		string = "JMP\t";
				goto JMP;
	case OP_JNIL:		string = "JNIL\t";
				goto JMP;
	case OP_JT:		string = "JT\t";
	JMP: {			GET_OPARG(m, vector);
				n = vector + m - OPARG_SIZE - base;
				goto OPARG;
	}
	case OP_JEQL:		string = "JEQL\t";
				goto JEQL;
	case OP_JNEQL:		string = "JNEQL\t";
	JEQL: {			GET_DATA(o, vector, data);
				GET_OPARG(m, vector);
				n = vector + m - OPARG_SIZE - base;
				goto OPARG_ARG;
	}
	case OP_NOT:		string = "NOT";
				goto NOARG;

	/* OP_UNBIND	n{arg}
		Undo "n" bindings of lexical variables.
	*/
	case OP_UNBIND:		string = "UNBIND\t";
				GET_OPARG(n, vector);
				goto OPARG;
	/* OP_UNBINDS	n{arg}
		Undo "n" bindings of special variables.
	*/
	case OP_UNBINDS:	string = "UNBINDS\t";
				GET_OPARG(n, vector);
				goto OPARG;
	/* OP_BIND	name{symbol}
	   OP_PBIND	name{symbol}
	   OP_BINDS	name{symbol}
	   OP_PBINDS	name{symbol}
		Binds a lexical or special variable to the either the
		value of VALUES(0), to the first value of the stack, or
		to the n-th value of VALUES(...).
	*/
	case OP_BIND:		string = "BIND\t";
				GET_DATA(o, vector, data);
				goto ARG;
	case OP_PBIND:		string = "PBIND\t";
				GET_DATA(o, vector, data);
				goto ARG;
	case OP_VBIND:		string = "VBIND\t";
				GET_OPARG(n, vector);
				GET_DATA(o, vector, data);
				goto OPARG_ARG;
	case OP_BINDS:		string = "BINDS\t";
				GET_DATA(o, vector, data);
				goto ARG;
	case OP_PBINDS:		string = "PBINDS\t";
				GET_DATA(o, vector, data);
				goto ARG;
	case OP_VBINDS:		string = "VBINDS\t";
				GET_OPARG(n, vector);
				GET_DATA(o, vector, data);
				goto OPARG_ARG;
	/* OP_SETQ	n{arg}
	   OP_PSETQ	n{arg}
	   OP_SETQS	var-name{symbol}
	   OP_PSETQS	var-name{symbol}
		Sets either the n-th local or a special variable VAR-NAME,
		to either the value in VALUES(0) (OP_SETQ[S]) or to the 
		first value on the stack (OP_PSETQ[S]).
	*/
	case OP_SETQ:		string = "SETQ\t";
				GET_OPARG(n, vector);
				goto OPARG;
	case OP_PSETQ:		string = "PSETQ\t";
				GET_OPARG(n, vector);
				goto OPARG;
	case OP_VSETQ:		string = "VSETQ\t";
				GET_OPARG(m, vector);
				o = MAKE_FIXNUM(m);
				GET_OPARG(n, vector);
				goto OPARG_ARG;
	case OP_SETQS:		string = "SETQS\t";
				GET_DATA(o, vector, data);
				goto ARG;
	case OP_PSETQS:		string = "PSETQS\t";
				GET_DATA(o, vector, data);
				goto ARG;
	case OP_VSETQS:		string = "VSETQS\t";
				GET_DATA(o, vector, data);
				GET_OPARG(n, vector);
				goto OPARG_ARG;

	case OP_PROGV:		vector = disassemble_progv(bytecodes, vector);
				break;

	/* OP_VALUES	n{arg}
		Pop N values from the stack and store them in VALUES(...)
	*/
	case OP_VALUES:		string = "VALUES\t";
				GET_OPARG(n, vector);
				goto OPARG;
	/* OP_NTHVAL
		Set VALUES(0) to the N-th value of the VALUES(...) list.
		The index N-th is extracted from the top of the stack.
	*/
	case OP_NTHVAL:		string = "NTHVAL\t";
				goto NOARG;
	case OP_TAGBODY:	vector = disassemble_tagbody(bytecodes, vector);
				break;
	case OP_PROTECT:	string = "PROTECT\t";
				goto JMP;
	case OP_PROTECT_NORMAL:	string = "PROTECT\tNORMAL";
				goto NOARG;
	case OP_PROTECT_EXIT:	string = "PROTECT\tEXIT";
				goto NOARG;
	case OP_NIL:		string = "QUOTE\tNIL";
				goto NOARG;
	case OP_PUSHNIL:	string = "PUSH\t'NIL";
		    		goto NOARG;
	case OP_STEPIN:		string = "STEP\tIN,";
				GET_DATA(o, vector, data);
				goto ARG;
	case OP_STEPOUT:	string = "STEP\tOUT";
				goto NOARG;

	case OP_CONS:		string = "CONS"; goto NOARG;
	case OP_ENDP:		string = "ENDP\tREG0"; goto NOARG;
	case OP_CAR:		string = "CAR\tREG0"; goto NOARG;
	case OP_CDR:		string = "CDR\tREG0"; goto NOARG;
	case OP_LIST:		string = "LIST\t";
				GET_OPARG(n, vector);
				goto OPARG;
	case OP_LISTA:		string = "LIST*\t";
				GET_OPARG(n, vector);
				goto OPARG;
	case OP_CALLG1:		string = "CALLG1\t";
				GET_DATA(o, vector, data);
				goto ARG;
	case OP_CALLG2:		string = "CALLG2\t";
				GET_DATA(o, vector, data);
				goto ARG;

	default:
		FEerror("Unknown code ~S", 1, MAKE_FIXNUM(*(vector-1)));
		return vector;
	NOARG:			print_noarg(string);
				break;
	ARG:			print_noarg(string);
				@prin1(1, o);
				break;
	OPARG:			print_oparg(string, n);
				break;
	OPARG_ARG:		print_oparg_arg(string, n, o);
				break;
	}
	goto BEGIN;
}

cl_object
si_bc_disassemble(cl_object v)
{
	if (type_of(v) == t_bclosure) {
		v = v->bclosure.code;
	}
	if (type_of(v) == t_bytecodes) {
		disassemble_lambda(v);
		@(return v)
	}
	@(return Cnil)
}

cl_object
si_bc_split(cl_object b)
{
	const cl_env_ptr the_env = ecl_process_env();
	cl_object vector;
	cl_object data;
	cl_object lex = Cnil;

	if (type_of(b) == t_bclosure) {
		b = b->bclosure.code;
		lex = b->bclosure.lex;
	}
	if (type_of(b) != t_bytecodes)
		@(return Cnil Cnil)
	vector = ecl_alloc_simple_vector(b->bytecodes.code_size, aet_b8);
	vector->vector.self.b8 = (uint8_t*)b->bytecodes.code;
	data = ecl_alloc_simple_vector(b->bytecodes.data_size, aet_object);
	data->vector.self.t = b->bytecodes.data;
	@(return lex vector data)
}
