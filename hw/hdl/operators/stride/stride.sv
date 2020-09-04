`timescale 1ns / 1ps

`include "axi_macros.svh"
`include "lynx_macros.svh"

import lynxTypes::*;

/**
 * User logic
 * 
 */
module design_user_logic_0 (
    // AXI4L CONTROL
    // Slave control. Utilize this interface for any kind of CSR implementation.
    AXI4L.s                     axi_ctrl,

    // AXI4S HOST
    AXI4S.m                     axis_card_src,
    AXI4S.s                     axis_card_sink,

    // AXI4S RDMA
    AXI4S.m                     axis_rdma_src,
    AXI4S.s                     axis_rdma_sink,

    // FV
    metaIntf.s                  fv_sink,
    metaIntf.m                  fv_src,

    // Requests
    reqIntf.m                   rd_req_user,
    reqIntf.m                   wr_req_user,

    // RDMA
    reqIntf.s                   rd_req_rdma,
    reqIntf.s                   wr_req_rdma,

    // Clock and reset
    input  wire                 aclk,
    input  wire[0:0]            aresetn
);

/* -- Tie-off unused interfaces and signals ----------------------------- */
always_comb axi_ctrl.tie_off_s();
//always_comb axis_card_src.tie_off_m();
//always_comb axis_card_sink.tie_off_s();
//always_comb axis_rdma_src.tie_off_m();
//always_comb axis_rdma_sink.tie_off_s();
//always_comb fv_sink.tie_off_s();
//always_comb fv_src.tie_off_m();
//always_comb rd_req_user.tie_off_m();
//always_comb wr_req_user.tie_off_m();
always_comb rd_req_rdma.tie_off_s();
//always_comb wr_req_rdma.tie_off_s();


/* -- USER LOGIC -------------------------------------------------------- */

localparam integer PARAMS_BITS = 64;

// Write - RDMA
`AXIS_ASSIGN(axis_rdma_sink, axis_card_src)
`REQ_ASSIGN(wr_req_rdma, wr_req_user)

// Read - Farview
metaIntf #(.DATA_BITS(PARAMS_BITS)) params_sink ();
metaIntf #(.DATA_BITS(PARAMS_BITS)) params_src ();

// Request handler
stride_req inst_stride_req (
    .aclk(aclk),
    .aresetn(aresetn),
    .fv_sink(fv_sink),
    .fv_src(fv_src),
    .rd_req_user(rd_req_user),
    .params(params_sink)
);

// Data handler
stride_data inst_stride_data (
    .aclk(aclk),
    .aresetn(aresetn),
    .params(params_src),
    .axis_sink(axis_card_sink),
    .axis_src(axis_rdma_src)
);

// Sequence
queue_meta inst_seq (
    .aclk(aclk),
    .aresetn(aresetn),
    .sink(params_sink),
    .src(params_src)
);


endmodule