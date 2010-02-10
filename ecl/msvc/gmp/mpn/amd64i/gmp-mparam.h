/* Generic x86 gmp-mparam.h -- Compiler/machine parameter header file.

Copyright 1991, 1993, 1994, 2000, 2001, 2002 Free Software Foundation, Inc.

This file is part of the GNU MP Library.

The GNU MP Library is free software; you can redistribute it and/or modify
it under the terms of the GNU Lesser General Public License as published by
the Free Software Foundation; either version 2.1 of the License, or (at your
option) any later version.

The GNU MP Library is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
License for more details.

You should have received a copy of the GNU Lesser General Public License
along with the GNU MP Library; see the file COPYING.LIB.  If not, write to
the Free Software Foundation, Inc., 59 Temple Place - Suite 330, Boston,
MA 02111-1307, USA. */

#ifndef GMP_MPARAM_H
#define GMP_MPARAM_H

#ifndef BITS_PER_MP_LIMB
#define BITS_PER_MP_LIMB 64
#elif   BITS_PER_MP_LIMB != 64
#error  Bad configuration in gmp-mparam.h
#endif

#ifndef BYTES_PER_MP_LIMB
#define BYTES_PER_MP_LIMB 8
#elif   BYTES_PER_MP_LIMB != 8
#error  Bad configuration in gmp-mparam.h
#endif

/* Generic x86 mpn_divexact_1 is faster than generic x86 mpn_divrem_1 on all
   of p5, p6, k6 and k7, so use it always.  It's probably slower on 386 and
   486, but that's too bad.  */
#define DIVEXACT_1_THRESHOLD  0

#define SQR_KARATSUBA_THRESHOLD 	33
#define MUL_KARATSUBA_THRESHOLD     26
#define MUL_TOOM3_THRESHOLD        298

#endif
