/* mpn_popcount, mpn_hamdist -- mpn bit population count/hamming distance.

Copyright 1994, 1996, 2000, 2001, 2002, 2005 Free Software Foundation, Inc.

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
the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA. */

#include "gmp.h"
#include "gmp-impl.h"

#define OPERATION_popcount 1
#define OPERATION_hamdist  0

#include "..\mpn\generic\popham.c"

#undef OPERATION_popcount
#undef OPERATION_hamdist
#undef FNAME
#undef POPHAM
#define OPERATION_popcount 0
#define OPERATION_hamdist  1

#include "..\mpn\generic\popham.c"
