#include <hls_stream.h>
#include <stdint.h>
#include <ap_int.h>

#include "HllSketch.hpp"
#include "stream.hpp"
#include "hashes.hpp"

//===========================================================================
// Design Dimensioning
unsigned const  N = 16;	// Parallel Data Lanes
unsigned const  P = 14;	// Precision
using Hash = Murmur3_64<0xDEADF00D>;
unsigned const  H = 64;

template<unsigned D>
struct net_axis {
	ap_uint<D>		data;
	ap_uint<D/8>	keep;
	ap_uint<6> 		id;
	ap_uint<1>		last;
};

unsigned const  DATA_WIDTH = 32;
unsigned const  LINE_WIDTH = N*DATA_WIDTH;
using input_t	= net_axis<LINE_WIDTH>;				// Input Tuple
using item_t	= flit_v_t<ap_uint<DATA_WIDTH>>;	// Decomposed Input Item
using output_t	= net_axis<32>;						// Output: Wrapped float


//===========================================================================
// Input Split
static void divide_data(hls::stream<input_t> &src, hls::stream<item_t> (&dst)[N]) {
#pragma HLS PIPELINE II=1
#pragma HLS INLINE off
	static item_t	buf[N]	= {};
	static bool		flush	= false;

	if(flush) {
		for(unsigned i = 0; i < N; i++) {
#pragma HLS unroll
			if(buf[i].last)	dst[i].write(buf[i]);
		}
		flush = false;
	}
	else {
		input_t x;
		if(src.read_nb(x)) {
			bool const	last = x.last;
			for(unsigned i = 0; i < N; i++) {
#pragma HLS unroll
				bool const  keep = (x.keep(4*i+3, 4*i) == 0xF);
				dst[i].write(item_t{last&&!keep, buf[i].val});
				buf[i] = item_t{keep, x.data((i+1)*DATA_WIDTH-1, i*DATA_WIDTH)};
			}
			flush = last;
		}
	}
} // divide_data()

//===========================================================================
void top(
	hls::stream<input_t>	&s_axis_data,
	hls::stream<output_t>	&m_axis_card
) {
//#pragma HLS INTERFACE axis port=s_axis_data
//#pragma HLS INTERFACE axis port=m_axis_card

#pragma HLS dataflow

	// Split the Data Lanes
	static hls::stream<item_t>	src_hll[N];

#if defined( __VITIS_HLS__)
	#pragma HLS aggregate  variable=src_hll compact=bit
#else
	#pragma HLS data_pack variable=src_hll
#endif

	divide_data(s_axis_data, src_hll);

	// HLL Sketch
	class YAssign {
		output_t& m_y;
	public:
		YAssign(output_t &y) : m_y(y) {}
		void operator=(float v) {
			union { float f; uint32_t i; } const  conv = { .f = v };
			m_y.data = conv.i;
			m_y.keep = 0xF;
		}
	};

	static HllSketch<N, H, P>	hll_sketch;
	hll_sketch.sketch(
		src_hll, m_axis_card,
		MemberLast(), [](item_t const& x){ return  Hash()(x.val); },
		MemberLast(), [](output_t &y){ return  YAssign(y); }
	); 

} // top
