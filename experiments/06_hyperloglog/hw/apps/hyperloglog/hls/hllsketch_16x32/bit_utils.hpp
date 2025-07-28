/****************************************************************************
 * Copyright (c) 2020, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 * this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 * this list of conditions and the following disclaimer in the documentation
 * and/or other materials provided with the distribution.
 * 3. Neither the name of the copyright holder nor the names of its contributors
 * may be used to endorse or promote products derived from this software
 * without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
 * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 ****************************************************************************
 * @brief
 *	Utilities for de- and transcoding low-level data representations.
 *
 *	This implementation is fiercely templated and supports both signed and
 *	unsigned representations as ap_(u)int<W> as much as semantically sensible.
 *
 * @author
 *	Thomas B. Preußer <tpreusser@inf.ethz.ch> <thomas.preusser@utexas.edu>
 ****************************************************************************/
#ifndef BIT_UTILS_HPP
#define BIT_UTILS_HPP

#include <ap_int.h>

namespace btl { // Part of the Bit-level Template Library
//---------------------------------------------------------------------------
// Compile-Time Arithmetic: LOG2 / POW2

// As soon as the HLS compiler supports modern C++ features,
// the template computations below may be simplified to:
//	constexpr unsigned flog2(unsigned n) { return n < 2? 0 : 1+flog2(n/2); }
//	constexpr unsigned clog2(unsigned n) { return n < 2? 0 : 1+flog2(n-1); }
//	constexpr unsigned pow2 (unsigned n) { return n == 0? 1 : 2*pow2(n-1); }

/** floor(log2(N)) */
template<unsigned N> struct flog2 {
	static unsigned const value = 1+flog2<N/2>::value;
};
template<> struct flog2<0> {};
template<> struct flog2<1> {
	static unsigned const value = 0;
};

/** ceil(log2(N)) */
template<unsigned N> struct clog2 {
	static unsigned const value = 1+flog2<N-1>::value;
};
template<> struct clog2<0> {};
template<> struct clog2<1> {
	static unsigned const value = 0;
};

/** 2**N */
template<unsigned N> struct pow2 {
	static unsigned const value = 2*pow2<N-1>::value;
};
template<> struct pow2<0> {
	static unsigned const value = 1;
};

//---------------------------------------------------------------------------
// Transcoding

/** Least-Significant Asserted Bit as 1-Hot (or zero if it does not exist). */
template<int W, bool S>
inline ap_int_base<W,S> lsab_hot(ap_int_base<W,S> x) {
#pragma HLS inline
	return	x & ap_int_base<W,S>(~x+1);
}

/** Most-Significant Asserted Bit as 1-Hot (or zero if it does not exist). */
template<int W, bool S>
inline ap_int_base<W,S> msab_hot(ap_int_base<W,S> x) {
#pragma HLS inline
	return	lsab_hot(x.reverse()).reverse();
}

/** One-Hot to binary.
 * The returned result is undefined if the input is not one-hot encoded.
 */
template<int W, bool S, unsigned M=clog2<W>::value>
inline ap_int_base<M,false> hot2bin(ap_int_base<W,S> x) {
#pragma HLS inline
	// Selective ORing to obtain binary index
	ap_int_base<M,false> res = 0;

	// This is what would be done in VHDL/Verilog:
	//	for(unsigned i = 0; i < W+1; i++)	if(h[i]) res |= i;

	// This is what HLS needs for a decent synthesis:
	for(unsigned i = 0; i < M; i++) {
#pragma HLS unroll
		for(ap_uint<clog2<W+1>::value> j = 0; j < W; j++) {
#pragma HLS unroll
#pragma TODO ap_fix
			if(j[i])	res[i] = res[i] | x[j];
		}
	}
	return	res;
}

/** Binary to One-Hot. */
template<int W, unsigned M=pow2<W>::value>
inline ap_int_base<M,false> bin2hot(ap_int_base<W,false> x) {
#pragma HLS inline
	ap_int_base<M,false> res(0);
	res[x] = 1;
	return	res;
}

/** Binary to reflected GRAY code. */
template<int W, bool S>
inline ap_int_base<W,S> bin2gray(ap_int_base<W,S> x) {
#pragma HLS inline
	return	x ^ x(W-1, 1);
}

/** Reflected GRAY code to binary. */
template<int W, bool S>
inline ap_int_base<W,S> gray2bin(ap_int_base<W,S> x) {
#pragma HLS inline
	ap_int_base<W,S> y = x;
	for(unsigned i = W-1; i > 0; i--) {
#pragma HLS unroll
#pragma TODO ap_fix
		y[i-1] = y[i] ^ y[i-1];
	}
	return	y;
}

//---------------------------------------------------------------------------
// Prefix and suffix counting

/** Count leading zeros. */
template<int W, bool S, unsigned M=clog2<W+1>::value>
inline ap_int_base<M,false> clz(ap_int_base<W,S> x) {
#pragma HLS inline
	return	ap_int_base<M,false>(x.countLeadingZeros());
}

/** Count trailing zeros. */
template<int W, bool S, unsigned M=clog2<W+1>::value>
inline ap_int_base<M,false> ctz(ap_int_base<W,S> x) {
#pragma HLS inline
	return	clz(x.reverse());
}

} // namespace btl
#endif
