#ifndef HLLSKETCH_HPP
#define HLLSKETCH_HPP

#include "Collector.hpp"
#include "stream.hpp"
#include "bit_utils.hpp"
#include "hls_math.h"

#include <algorithm>

template<
	unsigned H,	// Total Number of Hash Bits
	unsigned P	// Precision: Bits used to differentiate Buckets
>
class HllEstimator {
	static unsigned	constexpr	M		= 1u<<P;	// Number of Buckets
	static float	constexpr	ALPHAM2	= M * (M * (0.7213/(1+(1.079/M)))); // for M >= 128

	/**
	 * Exact accumulation until float conversion for output for M=2^P buckets:
	 *
	 * | <- P -> . <- H-P+1 -> |
	 *
	 * Numeric Range:
	 *	0.0 .. (2^P)*1.0
	 *
	 * All values are represented exact except for the maximum final result
	 * in the case that *all* buckets report a rank of zero, i.e. empty. The
	 * accumulator will then be ignored in favor of linear counting.
	 */
	using accu_t = ap_ufixed<H+1, P>;
	ap_uint<P+1>	zeros	= 0;
	accu_t			accu	= 0;

public:
	template<typename TR>
	void collect(TR  rank) {
#pragma HLS inline
		if(rank == 0)	zeros++;
		accu_t  d = 0;		// d = 2^(-rank)
		d[H-P+1 - rank] = 1;
		accu += d;

	} // collect()

public:
	float estimate() {
#pragma HLS inline
		// Raw Cardinality
		float card = ALPHAM2 / accu.to_float();

		// Estimate Refinement
		if(card <= 2.5*M){
			// Linear Counting if there are empty Buckets
			if(zeros != 0)	card = M*logf((float)M / (float)zeros);
		}

		// State Reset
		zeros = 0;
		accu  = 0;

		return	card;

	} // estimate()

}; // HllEstimator

template<
	unsigned N,
	unsigned H,	// Total Number of Hash Bits
	unsigned P	// Precision: Bits used to differentiate Buckets
>
class HllSketch {
	using buck_t = ap_uint<P>;	// Key
	using rank_t = ap_uint<btl::clog2<H-P+2>::value>;	// Rank: 0, 1, .., (H-P+1)
	using ranked_t = flit_kv_t<buck_t, rank_t>;
	using res_t	 = flit_v_t<rank_t>;

	//- Structure -----------------------------------------------------------
	hls::stream<ranked_t>	ranked[N];
	Collector<P, rank_t>	collector[N];
	hls::stream<res_t>		dsti[N];
	HllEstimator<H,P>		estimator;

public:
	template<
		typename TIXL = MemberLast,
		typename TIXV = MemberVal,
		typename TOXL = MemberLast,
		typename TOXV = MemberVal,
		typename TI,
		typename TO
	>
	void sketch(
		hls::stream<TI> (&src)[N],
		hls::stream<TO>  &dst,
		TIXL &&tixl = TIXL(),	// TI.last
		TIXV &&tixv = TIXV(),	// TI.val
		TOXL &&toxl = TOXL(),	// TO.last
		TOXV &&toxv = TOXV()	// TO.val
	) {
#pragma HLS inline off
#pragma HLS dataflow
#pragma HLS array_partition variable=collector dim=1

#if defined( __VITIS_HLS__)
	#pragma HLS aggregate  variable=ranked compact=bit
	#pragma HLS aggregate  variable=dsti compact=bit
#else
	#pragma HLS data_pack variable=ranked
	#pragma HLS data_pack variable=dsti
#endif

		rank(src, tixl, tixv);
		collect();
		fold(dst, toxl, toxv);

	} // sketch()

private:
	template<typename TIXL, typename TIXV, typename TI>
	void rank(hls::stream<TI> (&src)[N], TIXL &&tixl, TIXV &&tixv) {
#pragma HLS inline off
#pragma HLS pipeline II=1
		auto const  f_rank = [&tixl,&tixv](TI const& x)->ranked_t{
#pragma HLS inline
			auto const&  hash = tixv(x);
			return	ranked_t{tixl(x), hash(H-1, H-P), 1+btl::clz(ap_uint<H-P>(hash))};
		};
		for(unsigned i = 0; i < N; i++) {
#pragma HLS unroll
			stage_guarded(src[i], ranked[i], f_rank);
		}
	} // rank()

	void collect() {
#pragma HLS inline
		for(unsigned i = 0; i < N; i++) {
#pragma HLS unroll
			collector[i].collect(
				[](rank_t const &a, rank_t const &b)->rank_t{ return  std::max(a, b); },
				ranked[i], dsti[i]);
		}
	} // collect()

	template<typename TOXL, typename TOXV, typename TO>
	void fold(hls::stream<TO> &dst, TOXL &&toxl, TOXV &&toxv) {
#pragma HLS pipeline II=1
		ap_uint<N> empty;
		for(unsigned i = 0; i < N; i++) {
#pragma HLS unroll
			empty[i] = dsti[i].empty();
		}
		if(empty == 0) {

			// Maximum Fold across parallel Channels
			bool	last = false;
			rank_t	rank = 0;
			for(unsigned i = 0; i < N; i++) {
#pragma HLS unroll
				res_t x;
				dsti[i].read_nb(x);
				last |= x.last;
				rank = std::max(rank, x.val);
			}

			// HLL Metrics Update
			estimator.collect(rank);

			// Result Output
			if(last) {
				TO y{};
				toxl(y) = true;
				toxv(y) = estimator.estimate();
				dst.write(y);
			}
		}

	} // fold()

}; // class HllSketch

#endif
