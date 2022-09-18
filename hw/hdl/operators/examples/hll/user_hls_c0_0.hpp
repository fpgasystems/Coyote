#pragma once

#include "hllsketch_16x32.hpp"

#include <hls_stream.h>
#include "ap_int.h"
#include <stdint.h>
#include <iostream>
#include <fstream>
#include <iomanip>
#if defined( __VITIS_HLS__)
#include "ap_axi_sdata.h"
#endif

#define AXI_DATA_BITS       512

#define VADDR_BITS          48
#define LEN_BITS            28
#define DEST_BITS           4
#define PID_BITS            6
#define RID_BITS            4


//
// Structs
//

// AXI stream
struct axisIntf {
    ap_uint<AXI_DATA_BITS> tdata;
    ap_uint<AXI_DATA_BITS/8> tkeep;
    ap_uint<PID_BITS> tid;
    ap_uint<1> tlast;

    axisIntf()
        : tdata(0), tkeep(0), tid(0), tlast(0) {}
    axisIntf(ap_uint<AXI_DATA_BITS> tdata, ap_uint<AXI_DATA_BITS/8> tkeep, ap_uint<PID_BITS> tid, ap_uint<1> tlast)
        : tdata(tdata), tkeep(tkeep), tid(tid), tlast(tlast) {}
};


//
// User logic top level
//
void design_user_hls_c0_0 (
    // Host streams
    hls::stream<axisIntf>& axis_host_sink,
    hls::stream<axisIntf>& axis_host_src,


    ap_uint<64> axi_ctrl
);


