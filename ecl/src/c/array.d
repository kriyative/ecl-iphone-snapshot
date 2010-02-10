/* -*- mode: c; c-basic-offset: 8 -*- */
/*
    array.c --  Array routines
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

#include <limits.h>
#include <string.h>
#include <ecl/ecl.h>
#include <ecl/internal.h>

static const cl_index ecl_aet_size[] = {
  sizeof(cl_object),          /* aet_object */
  sizeof(float),              /* aet_sf */
  sizeof(double),             /* aet_df */
  0,                          /* aet_bit: cannot be handled with this code */
  sizeof(cl_fixnum),          /* aet_fix */
  sizeof(cl_index),           /* aet_index */
  sizeof(uint8_t),            /* aet_b8 */
  sizeof(int8_t),             /* aet_i8 */
#ifdef ecl_uint16_t
  sizeof(ecl_uint16_t),
  sizeof(ecl_int16_t),
#endif
#ifdef ecl_uint32_t
  sizeof(ecl_uint32_t),
  sizeof(ecl_int32_t),
#endif
#ifdef ecl_uint64_t
  sizeof(ecl_uint64_t),
  sizeof(ecl_int64_t),
#endif
#ifdef ECL_UNICODE
  sizeof(ecl_character),      /* aet_ch */
#endif
  sizeof(unsigned char)       /* aet_bc */
};

static const cl_object ecl_aet_name[] = {
        Ct,                   /* aet_object */
        @'single-float',      /* aet_sf */
        @'double-float',      /* aet_df */
        @'bit',               /* aet_bit: cannot be handled with this code */
        @'ext::cl-fixnum',    /* aet_fix */
        @'ext::cl-index',     /* aet_index */
        @'ext::byte8',        /* aet_b8 */
        @'ext::integer8',     /* aet_i8 */
#ifdef ecl_uint16_t
        @'ext::byte16',
        @'ext::integer16',
#endif
#ifdef ecl_uint32_t
        @'ext::byte32',
        @'ext::integer32',
#endif
#ifdef ecl_uint64_t
        @'ext::byte64',
        @'ext::integer64',
#endif
#ifdef ECL_UNICODE
        @'character',         /* aet_ch */
#endif
        @'base-char'          /* aet_bc */
};

static void displace (cl_object from, cl_object to, cl_object offset);
static void check_displaced (cl_object dlist, cl_object orig, cl_index newdim);

static void
FEbad_aet()
{
	FEerror(
"A routine from ECL got an object with a bad array element type.\n"
"If you are running a standard copy of ECL, please report this bug.\n"
"If you are embedding ECL into an application, please ensure you\n"
"passed the right value to the array creation routines.\n",0);
}

static cl_index
out_of_bounds_error(cl_index ndx, cl_object x)
{
	cl_object type = cl_list(3, @'integer', MAKE_FIXNUM(0),
                                 MAKE_FIXNUM(x->array.dim));
        FEwrong_type_argument(ecl_make_integer(ndx), type);
}

void
FEwrong_dimensions(cl_object a, cl_index rank)
{
        cl_object list = cl_make_list(rank, @':initial-element', @'*');
        cl_object type = cl_list(3, @'array', @'*', list);
        FEwrong_type_argument(type, a);
}

void
FEwrong_index(cl_object a, cl_index ndx, cl_index upper)
{
        const char *message =
                "~D is not a valid index into object ~A.~%"
                "It should be non-negative and < ~D.";
	cl_object type = cl_list(3, @'integer', MAKE_FIXNUM(0),
                                 ecl_make_integer(upper));
        cl_error(5, @'simple-type-error',
                 @':format-control',
                 make_constant_base_string(message),
                 @':format-arguments',
                 cl_list(3, ecl_make_integer(ndx), a, ecl_make_integer(upper)));
}

cl_index
ecl_to_index(cl_object n)
{
	switch (type_of(n)) {
	case t_fixnum: {
		cl_fixnum out = fix(n);
		if (out < 0 || out >= ADIMLIM)
			FEtype_error_index(Cnil, n);
		return out;
	}
	case t_bignum:
		FEtype_error_index(Cnil, n);
	default:
		FEtype_error_integer(n);
	}
}

cl_object
cl_row_major_aref(cl_object x, cl_object indx)
{
	cl_index j = fixnnint(indx);
	@(return ecl_aref(x, j))
}

cl_object
si_row_major_aset(cl_object x, cl_object indx, cl_object val)
{
	cl_index j = fixnnint(indx);
	@(return ecl_aset(x, j, val))
}

@(defun aref (x &rest indx)
@ {
	cl_index i, j;
	cl_index r = narg - 1;
  AGAIN:
	switch (type_of(x)) {
	case t_array:
		if (r != x->array.rank)
			FEerror("Wrong number of indices.", 0);
		for (i = j = 0;  i < r;  i++) {
			cl_index s =
			  ecl_fixnum_in_range(@'aref',"index",cl_va_arg(indx),
					      0, (cl_fixnum)x->array.dims[i]-1);
			j = j*(x->array.dims[i]) + s;
		}
		break;
	case t_vector:
#ifdef ECL_UNICODE
	case t_string:
#endif
	case t_base_string:
	case t_bitvector:
		if (r != 1)
			FEerror("Wrong number of indices.", 0);
		j = ecl_fixnum_in_range(@'aref',"index",cl_va_arg(indx),
					0, (cl_fixnum)x->vector.dim-1);
		break;
	default:
		x = ecl_type_error(@'aref',"argument",x,@'array');
		goto AGAIN;
	}
	@(return ecl_aref_unsafe(x, j));
} @)

cl_object
ecl_aref_unsafe(cl_object x, cl_index index)
{
	switch (x->array.elttype) {
	case aet_object:
		return x->array.self.t[index];
	case aet_bc:
		return CODE_CHAR(x->base_string.self[index]);
#ifdef ECL_UNICODE
	case aet_ch:
                return CODE_CHAR(x->string.self[index]);
#endif
	case aet_bit:
		index += x->vector.offset;
		if (x->vector.self.bit[index/CHAR_BIT] & (0200>>index%CHAR_BIT))
			return(MAKE_FIXNUM(1));
		else
			return(MAKE_FIXNUM(0));
	case aet_fix:
		return ecl_make_integer(x->array.self.fix[index]);
	case aet_index:
		return ecl_make_unsigned_integer(x->array.self.index[index]);
	case aet_sf:
		return(ecl_make_singlefloat(x->array.self.sf[index]));
	case aet_df:
		return(ecl_make_doublefloat(x->array.self.df[index]));
	case aet_b8:
		return ecl_make_uint8_t(x->array.self.b8[index]);
	case aet_i8:
		return ecl_make_int8_t(x->array.self.i8[index]);
#ifdef ecl_uint16_t
	case aet_b16:
		return ecl_make_uint16_t(x->array.self.b16[index]);
	case aet_i16:
		return ecl_make_int16_t(x->array.self.i16[index]);
#endif
#ifdef ecl_uint32_t
	case aet_b32:
		return ecl_make_uint32_t(x->array.self.b32[index]);
	case aet_i32:
		return ecl_make_int32_t(x->array.self.i32[index]);
#endif
#ifdef ecl_uint64_t
	case aet_b64:
		return ecl_make_uint64_t(x->array.self.b64[index]);
	case aet_i64:
		return ecl_make_int64_t(x->array.self.i64[index]);
#endif
	default:
		FEbad_aet();
	}
}

cl_object
ecl_aref(cl_object x, cl_index index)
{
        if (ECL_ARRAYP(x)) {
                if (index < x->array.dim) {
                        return ecl_aref_unsafe(x, index);
                }
		out_of_bounds_error(index, x);
        }
        FEtype_error_array(x);
}

cl_object
ecl_aref1(cl_object x, cl_index index)
{
        if (ECL_VECTORP(x)) {
                if (index < x->array.dim) {
                        return ecl_aref_unsafe(x, index);
                }
		out_of_bounds_error(index, x);
        }
        FEtype_error_array(x);
}

/*
	Internal function for setting array elements:

		(si:aset value array dim0 ... dimN)
*/
@(defun si::aset (v x &rest dims)
@ {
	cl_index i, j;
	cl_index r = narg - 2;
  AGAIN:
	switch (type_of(x)) {
	case t_array:
		if (r != x->array.rank)
			FEerror("Wrong number of indices.", 0);
		for (i = j = 0;  i < r;  i++) {
			cl_index s =
			  ecl_fixnum_in_range(@'si::aset',"index",cl_va_arg(dims),
					      0, (cl_fixnum)x->array.dims[i]-1);
			j = j*(x->array.dims[i]) + s;
		}
		break;
	case t_vector:
#ifdef ECL_UNICODE
	case t_string:
#endif
	case t_base_string:
	case t_bitvector:
		if (r != 1)
			FEerror("Wrong number of indices.", 0);
		j = ecl_fixnum_in_range(@'si::aset',"index",cl_va_arg(dims),
					0, (cl_fixnum)x->vector.dim - 1);
		break;
	default:
		x = ecl_type_error(@'si::aset',"destination",v,@'array');
		goto AGAIN;
	}
	@(return ecl_aset_unsafe(x, j, v))
} @)

cl_object
ecl_aset_unsafe(cl_object x, cl_index index, cl_object value)
{
	switch (x->array.elttype) {
	case aet_object:
		x->array.self.t[index] = value;
		break;
	case aet_bc:
		/* INV: ecl_char_code() checks the type of `value' */
		x->base_string.self[index] = ecl_char_code(value);
		break;
#ifdef ECL_UNICODE
	case aet_ch:
		x->string.self[index] = ecl_char_code(value);
		break;
#endif
	case aet_bit: {
		cl_fixnum i = ecl_fixnum_in_range(Cnil,"ASET value",value,0,1);
		index += x->vector.offset;
		if (i == 0)
			x->vector.self.bit[index/CHAR_BIT] &= ~(0200>>index%CHAR_BIT);
		else
			x->vector.self.bit[index/CHAR_BIT] |= 0200>>index%CHAR_BIT;
		break;
	}
	case aet_fix:
		x->array.self.fix[index] = fixint(value);
		break;
	case aet_index:
		x->array.self.index[index] = fixnnint(value);
		break;
	case aet_sf:
		x->array.self.sf[index] = ecl_to_float(value);
		break;
	case aet_df:
		x->array.self.df[index] = ecl_to_double(value);
		break;
	case aet_b8:
		x->array.self.b8[index] = ecl_to_uint8_t(value);
		break;
	case aet_i8:
		x->array.self.i8[index] = ecl_to_int8_t(value);
		break;
#ifdef ecl_uint16_t
	case aet_b16:
		x->array.self.b16[index] = ecl_to_uint16_t(value);
		break;
	case aet_i16:
		x->array.self.i16[index] = ecl_to_int16_t(value);
		break;
#endif
#ifdef ecl_uint32_t
	case aet_b32:
		x->array.self.b32[index] = ecl_to_uint32_t(value);
		break;
	case aet_i32:
		x->array.self.i32[index] = ecl_to_int32_t(value);
		break;
#endif
#ifdef ecl_uint64_t
	case aet_b64:
		x->array.self.b64[index] = ecl_to_uint64_t(value);
		break;
	case aet_i64:
		x->array.self.i64[index] = ecl_to_int64_t(value);
		break;
#endif
	}
	return(value);
}

cl_object
ecl_aset(cl_object x, cl_index index, cl_object value)
{
        if (ECL_ARRAYP(x)) {
                if (index < x->array.dim)
                        return ecl_aset_unsafe(x, index, value);
		out_of_bounds_error(index, x);
        }
        FEtype_error_array(x);
}

cl_object
ecl_aset1(cl_object x, cl_index index, cl_object value)
{
        if (ECL_VECTORP(x)) {
                if (index < x->array.dim)
                        return ecl_aset_unsafe(x, index, value);
		out_of_bounds_error(index, x);
        }
        FEtype_error_array(x);
}

/*
	Internal function for making arrays of more than one dimension:

		(si:make-pure-array dimension-list element-type adjustable
			            displaced-to displaced-index-offset)
*/
cl_object
si_make_pure_array(cl_object etype, cl_object dims, cl_object adj,
		   cl_object fillp, cl_object displ, cl_object disploff)
{
	cl_index r, s, i, j;
	cl_object x;
	if (FIXNUMP(dims)) {
		return si_make_vector(etype, dims, adj, fillp, displ, disploff);
	}
	r = ecl_length(dims);
	if (r >= ARANKLIM) {
		FEerror("The array rank, ~R, is too large.", 1, MAKE_FIXNUM(r));
	} else if (r == 1) {
		return si_make_vector(etype, ECL_CONS_CAR(dims), adj, fillp,
				      displ, disploff);
	} else if (!Null(fillp)) {
		FEerror(":FILL-POINTER may not be specified for an array of rank ~D",
			1, MAKE_FIXNUM(r));
	}
	x = ecl_alloc_object(t_array);
	x->array.displaced = Cnil;
	x->array.self.t = NULL;		/* for GC sake */
	x->array.rank = r;
	x->array.elttype = (short)ecl_symbol_to_elttype(etype);
	x->array.flags = 0; /* no fill pointer, no adjustable */
	x->array.dims = (cl_index *)ecl_alloc_atomic_align(sizeof(cl_index)*r, sizeof(cl_index));
	for (i = 0, s = 1;  i < r;  i++, dims = ECL_CONS_CDR(dims)) {
		j = ecl_fixnum_in_range(@'make-array', "dimension",
					ECL_CONS_CAR(dims), 0, ADIMLIM);
		s *= (x->array.dims[i] = j);
		if (s > ATOTLIM)
			FEerror("The array total size, ~D, is too large.", 1, MAKE_FIXNUM(s));
	}
	x->array.dim = s;
        if (adj != Cnil) {
                x->array.flags |= ECL_FLAG_ADJUSTABLE;
        }
	if (Null(displ))
		ecl_array_allocself(x);
	else
		displace(x, displ, disploff);
	@(return x);
}

/*
	Internal function for making vectors:

		(si:make-vector element-type dimension adjustable fill-pointer
				displaced-to displaced-index-offset)
*/
cl_object
si_make_vector(cl_object etype, cl_object dim, cl_object adj,
	       cl_object fillp, cl_object displ, cl_object disploff)
{
	cl_index d, f;
	cl_object x;
	cl_elttype aet;
 AGAIN:
	aet = ecl_symbol_to_elttype(etype);
	d = ecl_fixnum_in_range(@'make-array',"dimension",dim,0,ADIMLIM);
	if (aet == aet_bc) {
		x = ecl_alloc_object(t_base_string);
                x->base_string.elttype = (short)aet;
	} else if (aet == aet_bit) {
		x = ecl_alloc_object(t_bitvector);
                x->vector.elttype = (short)aet;
#ifdef ECL_UNICODE
	} else if (aet == aet_ch) {
		x = ecl_alloc_object(t_string);
                x->string.elttype = (short)aet;
#endif
	} else {
		x = ecl_alloc_object(t_vector);
		x->vector.elttype = (short)aet;
	}
	x->vector.self.t = NULL;		/* for GC sake */
	x->vector.displaced = Cnil;
	x->vector.dim = d;
        x->vector.flags = 0;
        if (adj != Cnil) {
                x->vector.flags |= ECL_FLAG_ADJUSTABLE;
        }
	if (Null(fillp)) {
		f = d;
	} else if (fillp == Ct) {
		x->vector.flags |= ECL_FLAG_HAS_FILL_POINTER;
		f = d;
	} else if (FIXNUMP(fillp) && ((f = fix(fillp)) <= d) && (f >= 0)) {
		x->vector.flags |= ECL_FLAG_HAS_FILL_POINTER;
	} else {
		fillp = ecl_type_error(@'make-array',"fill pointer",fillp,
				       cl_list(3,@'or',cl_list(3,@'member',Cnil,Ct),
					       cl_list(3,@'integer',MAKE_FIXNUM(0),
						       dim)));
		goto AGAIN;
	}
	x->vector.fillp = f;

	if (Null(displ))
		ecl_array_allocself(x);
	else
		displace(x, displ, disploff);
	@(return x)
}

cl_object *
alloc_pointerfull_memory(cl_index l)
{
        cl_object *p = ecl_alloc_align(sizeof(cl_object) * l, sizeof(cl_object));
        cl_index i;
        for (i = 0; l--;)
                p[i++] = Cnil;
        return p;
}

void
ecl_array_allocself(cl_object x)
{
        cl_elttype t = x->array.elttype;
	cl_index i, d = x->array.dim;
	switch (t) {
	/* assign self field only after it has been filled, for GC sake  */
	case aet_object:
		x->array.self.t = alloc_pointerfull_memory(d);
		return;
#ifdef ECL_UNICODE
	case aet_ch: {
		ecl_character *elts;
                d *= sizeof(ecl_character);
		elts = (ecl_character *)ecl_alloc_atomic_align(d, sizeof(ecl_character));
		x->string.self = elts;
		return;
        }
#endif
        case aet_bit:
                d = (d + (CHAR_BIT-1)) / CHAR_BIT;
                x->vector.self.bit = (byte *)ecl_alloc_atomic(d);
                x->vector.offset = 0;
                break;
        default: {
                cl_index elt_size = ecl_aet_size[t];
                d *= elt_size;
                x->vector.self.bc = (ecl_base_char *)ecl_alloc_atomic_align(d, elt_size);
        }
        }
}

cl_object
ecl_alloc_simple_vector(cl_index l, cl_elttype aet)
{
	cl_object x;

	switch (aet) {
	case aet_bc:
                x = ecl_alloc_compact_object(t_base_string, l+1);
                x->base_string.self = ECL_COMPACT_OBJECT_EXTRA(x);
                memset(x->base_string.self, 0, l+1);
                break;
#ifdef ECL_UNICODE
	case aet_ch:
                {
                cl_index bytes = sizeof(ecl_character) * l;
                x = ecl_alloc_compact_object(t_string, bytes);
                x->string.self = ECL_COMPACT_OBJECT_EXTRA(x);
                }
                break;
#endif
	case aet_bit:
                {
                cl_index bytes = (l + (CHAR_BIT-1))/CHAR_BIT;
                x = ecl_alloc_compact_object(t_bitvector, bytes);
                x->vector.self.bit = ECL_COMPACT_OBJECT_EXTRA(x);
		x->vector.offset = 0;
                }
		break;
        case aet_object:
                {
		x = ecl_alloc_object(t_vector);
                x->vector.self.t = alloc_pointerfull_memory(l);
                }
                break;
	default:
		x = ecl_alloc_compact_object(t_vector, l * ecl_aet_size[aet]);
                x->vector.self.bc = ECL_COMPACT_OBJECT_EXTRA(x);
	}
        x->base_string.elttype = aet;
        x->base_string.flags = 0; /* no fill pointer, not adjustable */
        x->base_string.displaced = Cnil;
        x->base_string.dim = x->base_string.fillp = l;
	return x;
}

cl_elttype
ecl_symbol_to_elttype(cl_object x)
{
 BEGIN:
	if (x == @'base-char')
		return(aet_bc);
#ifdef ECL_UNICODE
	if (x == @'character')
		return(aet_ch);
#endif
	else if (x == @'bit')
		return(aet_bit);
	else if (x == @'ext::cl-fixnum')
		return(aet_fix);
	else if (x == @'ext::cl-index')
		return(aet_index);
	else if (x == @'single-float' || x == @'short-float')
		return(aet_sf);
	else if (x == @'double-float')
		return(aet_df);
	else if (x == @'long-float') {
#ifdef ECL_LONG_FLOAT
		return(aet_object);
#else
		return(aet_df);
#endif
	} else if (x == @'ext::byte8')
		return(aet_b8);
	else if (x == @'ext::integer8')
		return(aet_i8);
#ifdef ecl_uint16_t
	else if (x == @'ext::byte16')
		return(aet_b16);
	else if (x == @'ext::integer16')
		return(aet_i16);
#endif
#ifdef ecl_uint32_t
	else if (x == @'ext::byte32')
		return(aet_b32);
	else if (x == @'ext::integer32')
		return(aet_i32);
#endif
#ifdef ecl_uint64_t
	else if (x == @'ext::byte64')
		return(aet_b64);
	else if (x == @'ext::integer64')
		return(aet_i64);
#endif
	else if (x == @'t')
		return(aet_object);
	else if (x == Cnil) {
		FEerror("ECL does not support arrays with element type NIL", 0);
	}
	x = cl_upgraded_array_element_type(1, x);
	goto BEGIN;
}

cl_object
ecl_elttype_to_symbol(cl_elttype aet)
{
        return ecl_aet_name[aet];
}

static void *
address_inc(void *address, cl_fixnum inc, cl_elttype elt_type)
{
	union ecl_array_data aux;
	aux.t = address;
	switch (elt_type) {
	case aet_object:
		return aux.t + inc;
	case aet_fix:
		return aux.fix + inc;
	case aet_index:
		return aux.fix + inc;
	case aet_sf:
		return aux.sf + inc;
	case aet_bc:
		return aux.bc + inc;
#ifdef ECL_UNICODE
	case aet_ch:
                return aux.c + inc;
#endif
	case aet_df:
		return aux.df + inc;
	case aet_b8:
	case aet_i8:
		return aux.b8 + inc;
#ifdef ecl_uint16_t
	case aet_b16:
	case aet_i16:
		return aux.b16 + inc;
#endif
#ifdef ecl_uint32_t
	case aet_b32:
	case aet_i32:
		return aux.b32 + inc;
#endif
#ifdef ecl_uint64_t
	case aet_b64:
	case aet_i64:
		return aux.b64 + inc;
#endif
	default:
		FEbad_aet();
	}
}

static void *
array_address(cl_object x, cl_index inc)
{
	return address_inc(x->array.self.t, inc, x->array.elttype);
}

cl_object
cl_array_element_type(cl_object a)
{
	@(return ecl_elttype_to_symbol(ecl_array_elttype(a)))
}

/*
	Displace(from, to, offset) displaces the from-array
	to the to-array (the original array) by the specified offset.
	It changes the a_displaced field of both arrays.
	The field is a cons; the car of the from-array points to
	the to-array and the cdr of the to-array is a list of arrays
	displaced to the to-array, so the from-array is pushed to the
	cdr of the to-array's array.displaced.
*/
static void
displace(cl_object from, cl_object to, cl_object offset)
{
	cl_index j;
	void *base;
	cl_elttype totype, fromtype;
	fromtype = from->array.elttype;
	if (type_of(to) == t_foreign) {
		if (fromtype == aet_bit || fromtype == aet_object) {
			FEerror("Cannot displace arrays with element type T or BIT onto foreign data",0);
		}
		base = to->foreign.data;
		j = ecl_fixnum_in_range(@'adjust-array',"array displacement", offset,
					0, MOST_POSITIVE_FIXNUM);
		from->array.displaced = to;
	} else {
		totype = to->array.elttype;
		if (totype != fromtype)
			FEerror("Cannot displace the array,~%\
because the element types don't match.", 0);
		if (from->array.dim > to->array.dim)
			FEerror("Cannot displace the array,~%\
because the total size of the to-array is too small.", 0);
		j = ecl_fixnum_in_range(@'adjust-array',"array displacement",offset,
					0, to->array.dim - from->array.dim);
		from->array.displaced = ecl_list1(to);
		if (Null(to->array.displaced))
			to->array.displaced = ecl_list1(Cnil);
		ECL_RPLACD(to->array.displaced, CONS(from, CDR(to->array.displaced)));
		if (fromtype == aet_bit) {
			j += to->vector.offset;
			from->vector.offset = j%CHAR_BIT;
			from->vector.self.bit = to->vector.self.bit + j/CHAR_BIT;
			return;
		}
		base = to->array.self.t;
	}
	from->array.self.t = address_inc(base, j, fromtype);
}

cl_object
si_array_raw_data(cl_object x)
{
        cl_elttype et = ecl_array_elttype(x);
        cl_index total_size = x->vector.dim * ecl_aet_size[et];
        cl_object output, to_array;
        uint8_t *data;
        if (et == aet_object) {
                FEerror("EXT:ARRAY-RAW-DATA can not get data "
                        "from an array with element type T.", 0);
        }
        data = x->vector.self.b8;
        to_array = x->array.displaced;
        if (to_array == Cnil || ((to_array = ECL_CONS_CAR(to_array)) == Cnil)) {
                output = ecl_alloc_object(t_vector);
                output->vector.elttype = aet_b8;
                output->vector.self.b8 = data;
                output->vector.dim = output->vector.fillp = total_size;
                output->vector.flags = 0; /* no fill pointer, not adjustable */
                output->vector.displaced = Cnil;
        } else {
                cl_index displ = data - to_array->vector.self.b8;
                output = si_make_vector(@'ext::byte8',
                                        MAKE_FIXNUM(total_size),
                                        Cnil,
                                        Cnil,
                                        si_array_raw_data(to_array),
                                        MAKE_FIXNUM(displ));
        }
        @(return output)
}

cl_elttype
ecl_array_elttype(cl_object x)
{
        if (!ECL_ARRAYP(x))
                FEwrong_type_argument(@'array', x);
        return x->array.elttype;
}

cl_object
cl_array_rank(cl_object a)
{
	assert_type_array(a);
	@(return ((type_of(a) == t_array) ? MAKE_FIXNUM(a->array.rank)
					  : MAKE_FIXNUM(1)))
}

cl_object
cl_array_dimension(cl_object a, cl_object index)
{
	@(return MAKE_FIXNUM(ecl_array_dimension(a, fixnnint(index))))
}

cl_index
ecl_array_dimension(cl_object a, cl_index index)
{
	switch (type_of(a)) {
	case t_array: {
                if (index > a->array.rank) FEwrong_dimensions(a, index+1);
		return a->array.dims[index];
	}
#ifdef ECL_UNICODE
	case t_string:
#endif
	case t_base_string:
	case t_vector:
	case t_bitvector:
                if (index) FEwrong_dimensions(a, index+1);
		return a->vector.dim;
	default:
		FEtype_error_array(a);
	}
}

cl_object
cl_array_total_size(cl_object a)
{
	assert_type_array(a);
	@(return MAKE_FIXNUM(a->array.dim))
}

cl_object
cl_adjustable_array_p(cl_object a)
{
	assert_type_array(a);
	@(return (ECL_ADJUSTABLE_ARRAY_P(a) ? Ct : Cnil))
}

/*
	Internal function for checking if an array is displaced.
*/
cl_object
cl_array_displacement(cl_object a)
{
	const cl_env_ptr the_env = ecl_process_env();
	cl_object to_array;
	cl_index offset;

	assert_type_array(a);
	to_array = a->array.displaced;
	if (Null(to_array)) {
		offset = 0;
	} else if (Null(to_array = CAR(a->array.displaced))) {
		offset = 0;
	} else {
		switch (a->array.elttype) {
		case aet_object:
			offset = a->array.self.t - to_array->array.self.t;
			break;
		case aet_bc:
			offset = a->array.self.bc - to_array->array.self.bc;
			break;
#ifdef ECL_UNICODE
		case aet_ch:
			offset = a->array.self.c - to_array->array.self.c;
			break;
#endif
		case aet_bit:
			offset = a->array.self.bit - to_array->array.self.bit;
			offset = offset * CHAR_BIT + a->array.offset
				- to_array->array.offset;
			break;
		case aet_fix:
			offset = a->array.self.fix - to_array->array.self.fix;
			break;
		case aet_index:
			offset = a->array.self.fix - to_array->array.self.fix;
			break;
		case aet_sf:
			offset = a->array.self.sf - to_array->array.self.sf;
			break;
		case aet_df:
			offset = a->array.self.df - to_array->array.self.df;
			break;
		case aet_b8:
		case aet_i8:
			offset = a->array.self.b8 - to_array->array.self.b8;
			break;
#ifdef ecl_uint16_t
		case aet_b16:
		case aet_i16:
			offset = a->array.self.b16 - to_array->array.self.b16;
			break;
#endif
#ifdef ecl_uint32_t
		case aet_b32:
		case aet_i32:
			offset = a->array.self.b32 - to_array->array.self.b32;
			break;
#endif
#ifdef ecl_uint64_t
		case aet_b64:
		case aet_i64:
			offset = a->array.self.b64 - to_array->array.self.b64;
			break;
#endif
		default:
			FEbad_aet();
		}
	}
	@(return to_array MAKE_FIXNUM(offset));
}

cl_object
cl_svref(cl_object x, cl_object index)
{
	const cl_env_ptr the_env = ecl_process_env();
	cl_index i;

	while (type_of(x) != t_vector ||
	       (x->vector.flags & (ECL_FLAG_ADJUSTABLE | ECL_FLAG_HAS_FILL_POINTER)) ||
	       CAR(x->vector.displaced) != Cnil ||
	       (cl_elttype)x->vector.elttype != aet_object)
	{
		x = ecl_type_error(@'svref',"argument",x,@'simple-vector');
	}
	i = ecl_fixnum_in_range(@'svref',"index",index,0,(cl_fixnum)x->vector.dim-1);
	@(return x->vector.self.t[i])
}

cl_object
si_svset(cl_object x, cl_object index, cl_object v)
{
	const cl_env_ptr the_env = ecl_process_env();
	cl_index i;

	while (type_of(x) != t_vector ||
	       (x->vector.flags & (ECL_FLAG_ADJUSTABLE | ECL_FLAG_HAS_FILL_POINTER)) ||
	       CAR(x->vector.displaced) != Cnil ||
	       (cl_elttype)x->vector.elttype != aet_object)
	{
		x = ecl_type_error(@'si::svset',"argument",x,@'simple-vector');
	}
	i = ecl_fixnum_in_range(@'svref',"index",index,0,(cl_fixnum)x->vector.dim-1);
	@(return (x->vector.self.t[i] = v))
}

cl_object
cl_array_has_fill_pointer_p(cl_object a)
{
	const cl_env_ptr the_env = ecl_process_env();
	cl_object r;
 AGAIN:
	switch (type_of(a)) {
	case t_array:
		r = Cnil; break;
	case t_vector:
	case t_bitvector:
#ifdef ECL_UNICODE
	case t_string:
#endif
	case t_base_string:
		r = ECL_ARRAY_HAS_FILL_POINTER_P(a)? Ct : Cnil;
		break;
	default:
		a = ecl_type_error(@'array-has-fill-pointer-p',"argument",
				   a, @'array');
		goto AGAIN;
	}
	@(return r)
}

cl_object
cl_fill_pointer(cl_object a)
{
	const cl_env_ptr the_env = ecl_process_env();
	assert_type_vector(a);
	if (!ECL_ARRAY_HAS_FILL_POINTER_P(a)) {
		a = ecl_type_error(@'fill-pointer', "argument",
				   a, ecl_read_from_cstring("(AND VECTOR (SATISFIES ARRAY-HAS-FILL-POINTER-P))"));
	}
	@(return MAKE_FIXNUM(a->vector.fillp))
}

/*
	Internal function for setting fill pointer.
*/
cl_object
si_fill_pointer_set(cl_object a, cl_object fp)
{
	const cl_env_ptr the_env = ecl_process_env();
	assert_type_vector(a);
	if (ECL_ARRAY_HAS_FILL_POINTER_P(a)) {
		a->vector.fillp = 
			ecl_fixnum_in_range(@'adjust-array',"fill pointer",fp,
					    0,a->vector.dim);
	} else {
		FEerror("The vector ~S has no fill pointer.", 1, a);
	}
	@(return fp)
}

/*
	Internal function for replacing the contents of arrays:

		(si:replace-array old-array new-array).

	Used in ADJUST-ARRAY.
*/
cl_object
si_replace_array(cl_object olda, cl_object newa)
{
	const cl_env_ptr the_env = ecl_process_env();
	cl_object dlist;
	if (type_of(olda) != type_of(newa)
	    || (type_of(olda) == t_array && olda->array.rank != newa->array.rank))
		goto CANNOT;
	if (!ECL_ADJUSTABLE_ARRAY_P(olda)) {
		/* When an array is not adjustable, we simply output the new array */
		olda = newa;
		goto OUTPUT;
	}
	for (dlist = CDR(olda->array.displaced); dlist != Cnil; dlist = CDR(dlist)) {
		cl_object other_array = CAR(dlist);
		cl_object offset;
		cl_array_displacement(other_array);
		offset = VALUES(1);
		displace(other_array, newa, offset);
	}
	switch (type_of(olda)) {
	case t_array:
	case t_vector:
	case t_bitvector:
		olda->array = newa->array;
		break;
#ifdef ECL_UNICODE
	case t_string:
#endif
	case t_base_string:
		olda->base_string = newa->base_string;
		break;
	default:
	CANNOT:
		FEerror("Cannot replace the array ~S by the array ~S.",
			2, olda, newa);
	}
 OUTPUT:
	@(return olda)
}

void
ecl_copy_subarray(cl_object dest, cl_index i0, cl_object orig,
		  cl_index i1, cl_index l)
{
	cl_elttype t = ecl_array_elttype(dest);
	if (i0 + l > dest->array.dim) {
		l = dest->array.dim - i0;
	}
	if (i1 + l > orig->array.dim) {
		l = orig->array.dim - i1;
	}
	if (t != ecl_array_elttype(orig) || t == aet_bit) {
		while (l--) {
			ecl_aset_unsafe(dest, i0++, ecl_aref_unsafe(orig, i1++));
		}
	} else if (t >= 0 && t <= aet_last_type) {
		cl_index elt_size = ecl_aet_size[t];
		memcpy(dest->array.self.bc + i0 * elt_size,
		       orig->array.self.bc + i1 * elt_size,
		       l * elt_size);
	} else {
		FEbad_aet();
	}
}

void
ecl_reverse_subarray(cl_object x, cl_index i0, cl_index i1)
{
	cl_elttype t = ecl_array_elttype(x);
	cl_index i, j;
	if (x->array.dim == 0) {
		return;
	}
	if (i1 >= x->array.dim) {
		i1 = x->array.dim;
	}
	switch (t) {
	case aet_object:
	case aet_fix:
	case aet_index:
		for (i = i0, j = i1-1;  i < j;  i++, --j) {
			cl_object y = x->vector.self.t[i];
			x->vector.self.t[i] = x->vector.self.t[j];
			x->vector.self.t[j] = y;
		}
		break;
	case aet_sf:
		for (i = i0, j = i1-1;  i < j;  i++, --j) {
			float y = x->array.self.sf[i];
			x->array.self.sf[i] = x->array.self.sf[j];
			x->array.self.sf[j] = y;
		}
		break;
	case aet_df:
		for (i = i0, j = i1-1;  i < j;  i++, --j) {
			double y = x->array.self.df[i];
			x->array.self.df[i] = x->array.self.df[j];
			x->array.self.df[j] = y;
		}
		break;
	case aet_bc:
		for (i = i0, j = i1-1;  i < j;  i++, --j) {
			ecl_base_char y = x->array.self.bc[i];
			x->array.self.bc[i] = x->array.self.bc[j];
                        x->array.self.bc[j] = y;
		}
		break;
	case aet_b8:
        case aet_i8:
		for (i = i0, j = i1-1;  i < j;  i++, --j) {
			ecl_uint8_t y = x->array.self.b8[i];
			x->array.self.b8[i] = x->array.self.b8[j];
			x->array.self.b8[j] = y;
		}
		break;
#ifdef ecl_uint16_t
	case aet_b16:
        case aet_i16:
		for (i = i0, j = i1-1;  i < j;  i++, --j) {
			ecl_uint16_t y = x->array.self.b16[i];
			x->array.self.b16[i] = x->array.self.b16[j];
			x->array.self.b16[j] = y;
		}
		break;
#endif
#ifdef ecl_uint32_t
	case aet_b32:
        case aet_i32:
		for (i = i0, j = i1-1;  i < j;  i++, --j) {
			ecl_uint32_t y = x->array.self.b32[i];
			x->array.self.b32[i] = x->array.self.b32[j];
			x->array.self.b32[j] = y;
		}
		break;
#endif
#ifdef ecl_uint64_t
	case aet_b64:
        case aet_i64:
		for (i = i0, j = i1-1;  i < j;  i++, --j) {
			ecl_uint64_t y = x->array.self.b64[i];
			x->array.self.b64[i] = x->array.self.b64[j];
			x->array.self.b64[j] = y;
		}
		break;
#endif
#ifdef ECL_UNICODE
	case aet_ch:
		for (i = i0, j = i1-1;  i < j;  i++, --j) {
			ecl_character y = x->array.self.c[i];
			x->array.self.c[i] = x->array.self.c[j];
                        x->array.self.c[j] = y;
		}
		break;
#endif
	case aet_bit:
		for (i = i0 + x->vector.offset,
		     j = i1 + x->vector.offset - 1;
		     i < j;
		     i++, --j) {
			int k = x->array.self.bit[i/CHAR_BIT]&(0200>>i%CHAR_BIT);
			if (x->array.self.bit[j/CHAR_BIT]&(0200>>j%CHAR_BIT))
				x->array.self.bit[i/CHAR_BIT]
				|= 0200>>i%CHAR_BIT;
			else
				x->array.self.bit[i/CHAR_BIT]
				&= ~(0200>>i%CHAR_BIT);
			if (k)
				x->array.self.bit[j/CHAR_BIT]
				|= 0200>>j%CHAR_BIT;
			else
				x->array.self.bit[j/CHAR_BIT]
				&= ~(0200>>j%CHAR_BIT);
		}
		break;
	default:
		FEbad_aet();
	}
}

cl_object
si_fill_array_with_elt(cl_object x, cl_object elt, cl_object start, cl_object end)
{
	cl_elttype t = ecl_array_elttype(x);
        cl_index first = fixnnint(start);
        cl_index last = Null(end)? x->array.dim : fixnnint(end);
        if (first >= last) {
                goto END;
        }
	switch (t) {
	case aet_object: {
                cl_object *p = x->vector.self.t + first;
		for (first = last - first; first; --first, ++p) { *p = elt; }
		break;
        }
	case aet_bc: {
                ecl_base_char e = ecl_char_code(elt);
                ecl_base_char *p = x->vector.self.bc + first;
		for (first = last - first; first; --first, ++p) { *p = e; }
		break;
        }
#ifdef ECL_UNICODE
	case aet_ch: {
                ecl_character e = ecl_char_code(elt);
                ecl_character *p = x->vector.self.c + first;
		for (first = last - first; first; --first, ++p) { *p = e; }
		break;
        }
#endif
	case aet_fix: {
                cl_fixnum e = fixint(elt);
                cl_fixnum *p = x->vector.self.fix + first;
		for (first = last - first; first; --first, ++p) { *p = e; }
		break;
        }
	case aet_index: {
                cl_index e = fixnnint(elt);
                cl_index *p = x->vector.self.index + first;
		for (first = last - first; first; --first, ++p) { *p = e; }
		break;
        }
	case aet_sf: {
                float e = ecl_to_float(elt);
                float *p = x->vector.self.sf + first;
		for (first = last - first; first; --first, ++p) { *p = e; }
		break;
        }
	case aet_df: {
                double e = ecl_to_double(elt);
                double *p = x->vector.self.df + first;
		for (first = last - first; first; --first, ++p) { *p = e; }
		break;
        }
	case aet_b8: {
                uint8_t e = ecl_to_uint8_t(elt);
                uint8_t *p = x->vector.self.b8 + first;
		for (first = last - first; first; --first, ++p) { *p = e; }
		break;
        }
	case aet_i8: {
                int8_t e = ecl_to_int8_t(elt);
                int8_t *p = x->vector.self.i8 + first;
		for (first = last - first; first; --first, ++p) { *p = e; }
		break;
        }
#ifdef ecl_uint16_t
	case aet_b16: {
                ecl_uint16_t e = ecl_to_uint16_t(elt);
                ecl_uint16_t *p = x->vector.self.b16 + first;
		for (first = last - first; first; --first, ++p) { *p = e; }
		break;
        }
	case aet_i16: {
                ecl_int16_t e = ecl_to_int16_t(elt);
                ecl_int16_t *p = x->vector.self.i16 + first;
		for (first = last - first; first; --first, ++p) { *p = e; }
		break;
        }
#endif
#ifdef ecl_uint32_t
	case aet_b32: {
                ecl_uint32_t e = ecl_to_uint32_t(elt);
                ecl_uint32_t *p = x->vector.self.b32 + first;
		for (first = last - first; first; --first, ++p) { *p = e; }
		break;
        }
	case aet_i32: {
                ecl_int32_t e = ecl_to_int32_t(elt);
                ecl_int32_t *p = x->vector.self.i32 + first;
		for (first = last - first; first; --first, ++p) { *p = e; }
		break;
        }
#endif
#ifdef ecl_uint64_t
	case aet_b64: {
                ecl_uint64_t e = ecl_to_uint64_t(elt);
                ecl_uint64_t *p = x->vector.self.b64 + first;
		for (first = last - first; first; --first, ++p) { *p = e; }
		break;
        }
	case aet_i64: {
                ecl_int64_t e = ecl_to_int64_t(elt);
                ecl_int64_t *p = x->vector.self.i64 + first;
		for (first = last - first; first; --first, ++p) { *p = e; }
		break;
        }
#endif
	case aet_bit: {
                int i = ecl_fixnum_in_range(@'si::aset',"bit",elt,0,1);
		for (last -= first, first += x->vector.offset; last; --last, ++first) {
                        int mask = 0200>>first%CHAR_BIT;
                        if (i == 0)
                                x->vector.self.bit[first/CHAR_BIT] &= ~mask;
                        else
                                x->vector.self.bit[first/CHAR_BIT] |= mask;
		}
		break;
        }
	default:
		FEbad_aet();
	}
 END:
        @(return x)
}
