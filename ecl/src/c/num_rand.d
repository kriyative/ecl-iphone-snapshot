/* -*- mode: c; c-basic-offset: 8 -*- */
/*
    num_rand.c  -- Random numbers.
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
#include <time.h>
#include <stdio.h>
#include <stdlib.h>

#if 0

/*
 * Crappy random number generator
 */

cl_object
init_random_state()
{
	return (cl_object)time(0);
}

static double
generate_double(cl_object rs)
{
	rs->random.value
	= rs->random.value
	+ (rs->random.value<<2)
	+ (rs->random.value<<17)
	+ (rs->random.value<<27);
	rs->random.value = rs->random.value & 0xffffffff;
	return (double)(rs->random.value>>1) / (4294967296.0/2.0);
}

#else

/*
 * Mersenne-Twister random number generator
 */

/* Period parameters */  
#define MT_N 624
#define MT_M 397
#define MATRIX_A 0x9908b0dfUL   /* constant vector a */
#define UPPER_MASK 0x80000000UL /* most significant w-r bits */
#define LOWER_MASK 0x7fffffffUL /* least significant r bits */

#define ulong unsigned long

cl_object
init_random_state()
{
	cl_index bytes = sizeof(ulong) * (MT_N + 1);
	cl_object a = ecl_alloc_simple_base_string(bytes);
	ulong *mt = (ulong*)a->base_string.self;
	int j;
#if !defined(_MSC_VER) && !defined(mingw32)
	FILE *fp = fopen("/dev/urandom","r");
	if (fp) {
		fread(mt, sizeof(*mt), MT_N, fp);
		for (j=0; j < MT_N; j++){
			mt[j] &= 0xffffffffUL;
		}
		fclose(fp);
	} else
#endif	
	{
		/* cant get urandom, use crappy source */
		mt[0] = (rand() + time(0)) & 0xffffffffUL;
		for (j=1; j < MT_N; j++){
			mt[j] = (1812433253UL * (mt[j-1] ^ (mt[j-1] >> 30)) + j);
			mt[j] &= 0xffffffffUL;
		}
	}
	mt[MT_N] = MT_N+1;
	return a;
}

ulong
generate_int32(cl_object state)
{
	static ulong mag01[2]={0x0UL, MATRIX_A};
	ulong y;
	ulong *mt = (ulong*)state->base_string.self;
	if (mt[MT_N] >= MT_N){
		/* refresh data */
		int kk;
		for (kk=0; kk < (MT_N - MT_M); kk++) {
			y = (mt[kk] & UPPER_MASK) | (mt[kk+1] & LOWER_MASK);
			mt[kk] = mt[kk + MT_M] ^ (y >> 1) ^ mag01[y & 0x1UL];
		}
		for (; kk < (MT_N - 1); kk++) {
			y = (mt[kk] & UPPER_MASK) | (mt[kk+1] & LOWER_MASK);
			mt[kk] = mt[kk+(MT_M-MT_N)] ^ (y >> 1) ^ mag01[y & 0x1UL];
		}
		y = (mt[MT_N-1] & UPPER_MASK) | (mt[0] & LOWER_MASK);
		mt[MT_N-1] = mt[MT_M-1] ^ (y >> 1) ^ mag01[y & 0x1UL];
 		mt[MT_N] = 0;
	}
	/* get random 32 bit num */
	y = mt[mt[MT_N]++];
	/* Tempering */
	y ^= (y >> 11);
	y ^= (y << 7) & 0x9d2c5680UL;
	y ^= (y << 15) & 0xefc60000UL;
	y ^= (y >> 18);
	return y;
}

static double
generate_double(cl_object state)
{
	return generate_int32(state) * (1.0 / 4294967296.0);
}

#endif

#ifdef WITH_GMP
static mp_limb_t
generate_limb(cl_object state)
{
#if GMP_LIMB_BITS <= 32
        return generate_int32(state);
#else
# if GMP_LIMB_BITS <= 64
        mp_limb_t high = generate_int32(state);
        return (high << 32) | generate_int32(state);
# else
#  if GMP_LIMB_BITS <= 128
        mp_limb_t word0 = generate_int32(state);
        mp_limb_t word1 = generate_int32(state);
        mp_limb_t word2 = generate_int32(state);
        mp_limb_t word3 = generate_int32(state);
        return (word3 << 96) | (word3 << 64) | (word1 << 32) || word0;
#  endif
# endif
#endif
}
#endif

static cl_object
random_integer(cl_object limit, cl_object state)
{
#ifdef WITH_GMP
        cl_index bit_length = ecl_integer_length(limit);
        cl_object buffer;
        if (bit_length <= FIXNUM_BITS)
                bit_length = FIXNUM_BITS;
        buffer = ecl_ash(MAKE_FIXNUM(1), bit_length);
        for (bit_length = mpz_size(buffer->big.big_num); bit_length; ) {
                buffer->big.big_limbs[--bit_length] =
                        generate_limb(state);
        }
        return cl_mod(buffer, limit);
#else
        return ecl_floor1(ecl_times(x, cl_rational(ecl_make_doublefloat(d))));
#endif
}

static cl_object
rando(cl_object x, cl_object rs)
{
	cl_object z;
 AGAIN:
	if (!ecl_plusp(x)) {
		goto ERROR;
	}
	switch (type_of(x)) {
	case t_fixnum:
#if FIXNUM_BITS <= 32
                z = MAKE_FIXNUM(generate_int32(rs->random.value) % fix(x));
                break;
#endif
	case t_bignum:
		z = random_integer(x, rs->random.value);
		break;
#ifdef ECL_SHORT_FLOAT
	case t_shortfloat:
		z = make_shortfloat(ecl_short_float(x) *
                                    (float)generate_double(rs->random.value));
		break;
#endif
	case t_singlefloat:
		z = ecl_make_singlefloat(sf(x) *
                                         (float)generate_double(rs->random.value));
		break;
	case t_doublefloat:
		z = ecl_make_doublefloat(df(x) *
                                         generate_double(rs->random.value));
		break;
#ifdef ECL_LONG_FLOAT
	case t_longfloat:
		z = ecl_make_longfloat(ecl_long_float(x) *
                                       (long double)generate_double(rs->random.value));
		break;
#endif
	default:
	ERROR:
		x = ecl_type_error(@'random',"limit",x,
				   ecl_read_from_cstring("(OR (INTEGER (0) *) (FLOAT (0) *))"));
		goto AGAIN;
	}
	return z;
}

cl_object
ecl_make_random_state(cl_object rs)
{
        cl_object z = ecl_alloc_object(t_random);
	if (rs == Ct) {
		z->random.value = init_random_state();
	} else {
		if (Null(rs)) {
			rs = ecl_symbol_value(@'*random-state*');
		}
		if (type_of(rs) != t_random) {
			FEwrong_type_argument(@'random-state', rs);
		}
		z->random.value = cl_copy_seq(rs->random.value);
	}
	return(z);
}

@(defun random (x &optional (rs ecl_symbol_value(@'*random-state*')))
@
	rs = ecl_check_cl_type(@'random', rs, t_random);
	@(return rando(x, rs));
@)

@(defun make_random_state (&optional (rs Cnil))
@
	@(return ecl_make_random_state(rs))
@)

cl_object
cl_random_state_p(cl_object x)
{
	@(return ((type_of(x) == t_random) ? Ct : Cnil))
}
