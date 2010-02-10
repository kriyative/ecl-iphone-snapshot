/* -*- mode: c; c-basic-offset: 8 -*- */
/*
    sequence.d -- Sequence routines.
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
#include <limits.h>
#include <ecl/ecl-inl.h>

cl_object
cl_elt(cl_object x, cl_object i)
{
	@(return ecl_elt(x, fixint(i)))
}

cl_object
ecl_elt(cl_object seq, cl_fixnum index)
{
	cl_fixnum i;
	cl_object l;

	if (index < 0)
		goto E;
	switch (type_of(seq)) {
	case t_list:
		for (i = index, l = seq;  i > 0;  --i) {
                        if (!LISTP(l)) goto E0;
                        if (Null(l)) goto E;
                        l = ECL_CONS_CDR(l);
                }
                if (!LISTP(l)) goto E0;
                if (Null(l)) goto E;
		return ECL_CONS_CAR(l);

#ifdef ECL_UNICODE
	case t_string:
#endif
	case t_vector:
	case t_bitvector:
	case t_base_string:
                if (index >= seq->vector.fillp) goto E;
		return ecl_aref_unsafe(seq, index);
	default:
        E0:
		FEtype_error_sequence(seq);
	}
E:
	FEtype_error_index(seq, MAKE_FIXNUM(index));
}

cl_object
si_elt_set(cl_object seq, cl_object index, cl_object val)
{
	@(return ecl_elt_set(seq, fixint(index), val))
}

cl_object
ecl_elt_set(cl_object seq, cl_fixnum index, cl_object val)
{
	cl_fixnum i;
	cl_object l;

	if (index < 0)
		goto E;
	switch (type_of(seq)) {
	case t_list:
		for (i = index, l = seq;  i > 0;  --i) {
                        if (!LISTP(l)) goto E0;
                        if (Null(l)) goto E;
                        l = ECL_CONS_CDR(l);
                }
                if (!LISTP(l)) goto E0;
                if (Null(l)) goto E;
		ECL_RPLACA(l, val);
		return val;

#ifdef ECL_UNICODE
	case t_string:
#endif
	case t_vector:
	case t_bitvector:
	case t_base_string:
                if (index >= seq->vector.fillp) goto E;
		return ecl_aset_unsafe(seq, index, val);
	default:
        E0:
		FEtype_error_sequence(seq);
	}
E:
	FEtype_error_index(seq, MAKE_FIXNUM(index));
}

@(defun subseq (sequence start &optional end &aux x)
	cl_fixnum s, e;
	cl_fixnum i;
@
	s = fixnnint(start);
	if (Null(end))
		e = -1;
	else
		e = fixnnint(end);
	switch (type_of(sequence)) {
	case t_list:
		if (Null(sequence)) {
			if (s > 0)
				goto ILLEGAL_START_END;
			if (e > 0)
				goto ILLEGAL_START_END;
			@(return Cnil)
		}
		if (e >= 0)
			if ((e -= s) < 0)
				goto ILLEGAL_START_END;
		while (s-- > 0) {
			if (ATOM(sequence))
				goto ILLEGAL_START_END;
			sequence = CDR(sequence);
		}
		if (e < 0)
			return cl_copy_list(sequence);
		{ cl_object *z = &x;
		  for (i = 0;  i < e;  i++) {
		    if (ATOM(sequence))
		      goto ILLEGAL_START_END;
		    z = &ECL_CONS_CDR(*z = ecl_list1(CAR(sequence)));
		    sequence = CDR(sequence);
		  }
		}
		@(return x)

#ifdef ECL_UNICODE
	case t_string:
#endif
	case t_vector:
	case t_bitvector:
	case t_base_string:
		if (s > sequence->vector.fillp)
			goto ILLEGAL_START_END;
		if (e < 0)
			e = sequence->vector.fillp;
		else if (e < s || e > sequence->vector.fillp)
			goto ILLEGAL_START_END;
		x = ecl_alloc_simple_vector(e - s, ecl_array_elttype(sequence));
		ecl_copy_subarray(x, 0, sequence, s, e-s);
		@(return x)

	default:
		FEtype_error_sequence(sequence);
	}

ILLEGAL_START_END:
	FEerror("~S and ~S are illegal as :START and :END~%\
for the sequence ~S.", 3, start, end, sequence);
@)

cl_object
cl_copy_seq(cl_object x)
{
	return @subseq(2, x, MAKE_FIXNUM(0));
}

cl_object
cl_length(cl_object x)
{
	@(return MAKE_FIXNUM(ecl_length(x)))
}

cl_fixnum
ecl_length(cl_object x)
{
	cl_fixnum i;

	switch (type_of(x)) {
	case t_list:
		/* INV: A list's length always fits in a fixnum */
		i = 0;
		loop_for_in(x) {
			i++;
		} end_loop_for_in;
		return(i);

#ifdef ECL_UNICODE
	case t_string:
#endif
	case t_vector:
	case t_base_string:
	case t_bitvector:
		return(x->vector.fillp);

	default:
		FEtype_error_sequence(x);
	}
}

cl_object
cl_reverse(cl_object seq)
{
	cl_object output, x;

	switch (type_of(seq)) {
	case t_list: {
		for (x = seq, output = Cnil; !Null(x); x = ECL_CONS_CDR(x)) {
                        if (!LISTP(x)) goto E;
			output = CONS(ECL_CONS_CAR(x), output);
                }
		break;
	}
#ifdef ECL_UNICODE
	case t_string:
#endif
	case t_vector:
	case t_bitvector:
	case t_base_string:
		output = ecl_alloc_simple_vector(seq->vector.fillp, ecl_array_elttype(seq));
		ecl_copy_subarray(output, 0, seq, 0, seq->vector.fillp);
		ecl_reverse_subarray(output, 0, seq->vector.fillp);
		break;
	default:
        E:
		FEtype_error_sequence(seq);
	}
	@(return output)
}

cl_object
cl_nreverse(cl_object seq)
{
	switch (type_of(seq)) {
	case t_list: {
		cl_object x, y, z;
                for (x = seq, y = Cnil; !Null(x); ) {
                        if (!LISTP(x)) FEtype_error_list(x);
                        z = x;
                        x = ECL_CONS_CDR(x);
                        if (x == seq) FEcircular_list(seq);
                        ECL_RPLACD(z, y);
                        y = z;
                }
		seq = y;
		break;
	}
#ifdef ECL_UNICODE
	case t_string:
#endif
	case t_vector:
	case t_base_string:
	case t_bitvector:
		ecl_reverse_subarray(seq, 0, seq->vector.fillp);
		break;
	default:
		FEtype_error_sequence(seq);
	}
	@(return seq)
}
