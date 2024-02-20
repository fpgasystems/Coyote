//#include "user_hls_c0_0.hpp"

#include "hllsketch_16x32.hpp"

#include <hls_stream.h>
#include "ap_int.h"
#include <stdint.h>
#include <iostream>
#include <fstream>
#include <iomanip>
#include "ap_axi_sdata.h"

#define AXI_DATA_BITS       512

#define VADDR_BITS          48
#define LEN_BITS            28
#define DEST_BITS           4
#define PID_BITS            6
#define RID_BITS            4

/**
 * User logic
 *
 */

// Interface adjustments
// Sink

void input_cnvrt (
    hls::stream<ap_axiu<AXI_DATA_BITS, 0, PID_BITS, 0> >& axis_host_sink,
    hls::stream<input_t>& hll_sink
) {
#pragma HLS inline off
#pragma HLS pipeline II=1

    ap_axiu<AXI_DATA_BITS, 0, PID_BITS, 0> in_data;
	input_t out_data;
	
	if (!axis_host_sink.empty()) {
        axis_host_sink.read(in_data);

        out_data.data = in_data.data;
        out_data.keep = in_data.keep;
        out_data.id   = in_data.id;
        out_data.last = in_data.last;

        hll_sink.write(out_data);
	}
}

void output_cnvrt (
    hls::stream<output_t>& hll_src,
    hls::stream<ap_axiu<AXI_DATA_BITS, 0, PID_BITS, 0> >& axis_host_src
) {
#pragma HLS inline off
#pragma HLS pipeline II=1

    output_t  in_data;
    ap_axiu<AXI_DATA_BITS, 0, PID_BITS, 0> out_data;

    if(!hll_src.empty()) {
        hll_src.read(in_data);

        out_data.data = in_data.data;
        out_data.keep = in_data.keep;
        out_data.id   = in_data.id;
        out_data.last = in_data.last;

        axis_host_src.write(out_data);
    }
}

/**
 * Main
 */
void hllsketch_16x32 (
    // Host streams
    hls::stream<ap_axiu<AXI_DATA_BITS, 0, PID_BITS, 0> >& axis_host_sink,
    hls::stream<ap_axiu<AXI_DATA_BITS, 0, PID_BITS, 0> >& axis_host_src,

    ap_uint<64> axi_ctrl
) {
    #pragma HLS DATAFLOW disable_start_propagation
    #pragma HLS INTERFACE ap_ctrl_none port=return  

    #pragma HLS INTERFACE axis register port=axis_host_sink name=s_axis_host_sink
    #pragma HLS INTERFACE axis register port=axis_host_src name=m_axis_host_src

    
    #pragma HLS INTERFACE s_axilite port=return     bundle=control
    //#pragma HLS INTERFACE s_axilite port=axi_ctrl_a bundle=control
    //#pragma HLS INTERFACE s_axilite port=axi_ctrl_b bundle=control
    //#pragma HLS INTERFACE s_axilite port=axi_ctrl_c bundle=control
    #pragma HLS INTERFACE s_axilite port=axi_ctrl bundle=control

    //
    // User logic 
    //
	static hls::stream<input_t> hll_sink;
	static hls::stream<output_t> hll_src;
    #pragma HLS STREAM depth=2 variable=hll_sink
    #pragma HLS STREAM depth=2 variable=hll_src

    input_cnvrt(axis_host_sink, hll_sink);
    top(hll_sink, hll_src);
    output_cnvrt(hll_src, axis_host_src);

}
