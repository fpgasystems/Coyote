#ifndef COLLECTOR_HPP
#define COLLECTOR_HPP

#include <ap_int.h>
#include <hls_stream.h>

#include "stream.hpp"

/**
 * Statistics collector over an input stream using a key space of 2**K and
 * the value type TV.
 */
template<
	unsigned K,
	typename TV
>
class Collector {

	static unsigned const FEED = 0;
	static unsigned const SETTLE1 = 1;
	static unsigned const SETTLE2 = 2;
	static unsigned const DUMP = 3;
	using TK = ap_uint<K>;

	unsigned	state		= FEED;
	TK		dump_ptr	= 0;
	TV		mem[1<<K]	= { 0, };

	// Registered Update for better Timing on `mem`
	bool	z_stb = false;
	TK		z_key;
	TV		z_val;
	bool	zz_stb = false;
	TK		zz_key;
	TV		zz_val;
	bool	zzz_stb = false;
	TK		zzz_key;
	TV		zzz_val;

	// Registered Result Output for better Timing and II=1
	bool	y_stb = false;
	bool	y_last;
	TV		y_val;

public:
	template<
		typename TIXL = MemberLast,
		typename TIXK = MemberKey,
		typename TIXV = MemberVal,
		typename TOXL = MemberLast,
		typename TOXV = MemberVal,
		typename TI,
		typename TO,
		typename F
	>
	void collect(
		F &&f,					// Update Value Folding Function: (TV, TV) -> TV
		hls::stream<TI> &src,	// Input: tixl(x) -> last, tixk(x) -> key, tixv(x) -> val
		hls::stream<TO> &dst,	// Output: toxl(y) <- last, toxv(y) <- val
		TIXL &&tixl = TIXL(),	// default: TI.last
		TIXK &&tixk = TIXK(),	// default: TI.key
		TIXV &&tixv = TIXV(),	// default: TI.val
		TOXL &&toxl = TOXL(),	// default: TO.last
		TOXV &&toxv = TOXV()	// default: TO.val
	) {
#pragma HLS inline off
#pragma HLS pipeline II=1

#if defined( __VITIS_HLS__)
	#pragma HLS bind_storage variable=mem type=RAM_T2P impl=BRAM
#else
	#pragma HLS RESOURCE variable=mem core=RAM_T2P_BRAM
#endif

#pragma HLS DEPENDENCE variable=mem inter distance=2

		// Execute pending Memory Update and Output
		bool const  z_stb0 = z_stb;
		TK	 const  z_key0 = z_key;
		TV	 const  z_val0 = z_val;
		if(z_stb)	mem[z_key] = z_val;

		if(y_stb) {
			TO y;
			toxl(y) = y_last;
			toxv(y) = y_val;
			if(dst.write_nb(y))	y_stb = false;
		}

		// Controlling FSM
		switch(state) {

			// Read and process Data
			case FEED: {
				TI x;
				bool const  x_stb = src.read_nb(x);
				TK	 const  x_key = tixk(x);
				bool const  z_match = z_stb && (z_key == x_key);
				bool const  zz_match = zz_stb && (zz_key == x_key);
				bool const  zzz_match = zzz_stb && (zzz_key == x_key);
				TV	 const  x_val = f(tixv(x), z_match? z_val : zz_match? zz_val : zzz_match? zzz_val : mem[x_key]);

				z_stb = x_stb;
				z_key = x_key;
				z_val = x_val;
				if(x_stb && tixl(x))  state = SETTLE1;
			}
			break;

			// Cover Memory Update Latency
			case SETTLE1:	state = SETTLE2;	break;
			case SETTLE2:	state = DUMP;		break;

			// Stream out Contents
			case DUMP: {
				if(!y_stb) {
					bool const  last = ~dump_ptr == 0;

					y_stb	= true;
					y_last	= last;
					y_val	= mem[dump_ptr];

					z_stb = true;
					z_key = dump_ptr;
					z_val = 0;

					if(last)	state = FEED;
					dump_ptr++;
				}
			}
			break;
		}
		zzz_stb = zz_stb;
		zzz_key = zz_key;
		zzz_val = zz_val;
		zz_stb = z_stb0;
		zz_key = z_key0;
		zz_val = z_val0;

	} // collect()

}; // class Collector

#endif
