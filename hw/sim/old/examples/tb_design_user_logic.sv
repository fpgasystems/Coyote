`timescale 1ns / 1ps

import lynxTypes::*;

`include "axi_macros.svh"
`include "lynx_macros.svh".s

/**
 * User logic
 * 
 */
module design_user_logic_c0_0 (
// AXI4L CONTROL
    AXI4L.s                     axi_ctrl,

`ifdef EN_BPSS
    // DESCRIPTOR BYPASS
    metaIntf.m		        bpss_rd_req,
    metaIntf.m		        bpss_wr_req,
    metaIntf.s                  bpss_rd_done,
    metaIntf.s                  bpss_wr_done,

`endif
`ifdef EN_STRM
    // AXI4S HOST STREAMS
    AXI4SR.s                    axis_host_sink,
    AXI4SR.m                   axis_host_src,
`endif
`ifdef EN_MEM
    // AXI4S CARD STREAMS
    AXI4SR.s                    axis_card_sink,
    AXI4SR.m                   axis_card_src,
`endif
`ifdef EN_RDMA_0
    // RDMA QSFP0 CMD
    metaIntf.s 		        rdma_0_rd_req,
    metaIntf.s 			        rdma_0_wr_req,

    // AXI4S RDMA QSFP0 STREAMS
    AXI4SR.s                    axis_rdma_0_sink,
    AXI4SR.m                   axis_rdma_0_src,
`ifdef EN_RPC
    // RDMA QSFP1 SQ
    metaIntf.m			        rdma_0_sq,
    metaIntf.s                  rdma_0_rq,
`endif
`endif
`ifdef EN_RDMA_1
    // RDMA QSFP1 CMD
    metaIntf.s 		        rdma_1_rd_req,
    metaIntf.s 			        rdma_1_wr_req,

    // AXI4S RDMA QSFP1 STREAMS
    AXI4SR.s                    axis_rdma_1_sink,
    AXI4SR.m                   axis_rdma_1_src,
`ifdef EN_RPC
    // RDMA QSFP1 SQ
    metaIntf.m			        rdma_1_sq,
    metaIntf.s                  rdma_1_rq,
`endif
`endif
`ifdef EN_TCP_0
    // TCP/IP QSFP0 CMD
    metaIntf.m		        tcp_0_listen_req,
    metaIntf.s 		        tcp_0_listen_rsp,
    metaIntf.m		        tcp_0_open_req,
    metaIntf.s 		        tcp_0_open_rsp,
    metaIntf.m		        tcp_0_close_req,
    metaIntf.s 		        tcp_0_notify,
    metaIntf.m		        tcp_0_rd_pkg,
    metaIntf.s 		        tcp_0_rx_meta,
    metaIntf.m		        tcp_0_tx_meta,
    metaIntf.s 		        tcp_0_tx_stat,

    // AXI4S TCP/IP QSFP0 STREAMS
    AXI4SR.s                    axis_tcp_0_sink,
    AXI4SR.m                   axis_tcp_0_src,
`endif
`ifdef EN_TCP_1
    // TCP/IP QSFP1 CMD
    metaIntf.m		        tcp_1_listen_req,
    metaIntf.s 		        tcp_1_listen_rsp,
    metaIntf.m		        tcp_1_open_req,
    metaIntf.s 		        tcp_1_open_rsp,
    metaIntf.m		        tcp_1_close_req,
    metaIntf.s 		        tcp_1_notify,
    metaIntf.m		        tcp_1_rd_pkg,
    metaIntf.s 		        tcp_1_rx_meta,
    metaIntf.m		        tcp_1_tx_meta,
    metaIntf.s 		        tcp_1_tx_stat,

    // AXI4S TCP/IP QSFP1 STREAMS
    AXI4SR.s                    axis_tcp_1_sink, 
    AXI4SR.m                   axis_tcp_1_src,
`endif
    // Clock and reset
    input  wire                 aclk,
    input  wire[0:0]            aresetn
);

/* -- Tie-off unused interfaces and signals ----------------------------- */
always_comb axi_ctrl.tie_off_s();
`ifdef EN_BPSS
always_comb bpss_rd_req.tie_off_m();
always_comb bpss_wr_req.tie_off_m();
always_comb bpss_rd_done.tie_off_s();
always_comb bpss_wr_done.tie_off_s();
`endif
`ifdef EN_STRM
always_comb axis_host_sink.tie_off_s();
always_comb axis_host_src.tie_off_m();
`endif
`ifdef EN_MEM
always_comb axis_card_sink.tie_off_s();
always_comb axis_card_src.tie_off_m();
`endif
`ifdef EN_RDMA_0
always_comb rdma_0_rd_req.tie_off_s();
always_comb rdma_0_wr_req.tie_off_s();
always_comb axis_rdma_0_sink.tie_off_s();
always_comb axis_rdma_0_src.tie_off_m();
`ifdef EN_RPC
always_comb rdma_0_sq.tie_off_m();
always_comb rdma_0_rq.tie_off_m();
`endif
`endif
`ifdef EN_RDMA_1
always_comb rdma_1_rd_req.tie_off_s();
always_comb rdma_1_wr_req.tie_off_s();
always_comb axis_rdma_1_sink.tie_off_s();
always_comb axis_rdma_1_src.tie_off_m();
`ifdef EN_RPC
always_comb rdma_1_sq.tie_off_m();
always_comb rdma_1_rq.tie_off_m();
`endif
`endif
`ifdef EN_TCP_0
always_comb tcp_0_listen_req.tie_off_m();
always_comb tcp_0_listen_rsp.tie_off_s();
always_comb tcp_0_open_req.tie_off_m();
always_comb tcp_0_open_rsp.tie_off_s();
always_comb tcp_0_close_req.tie_off_m();
always_comb tcp_0_notify.tie_off_s();
always_comb tcp_0_rd_pkg.tie_off_m();
always_comb tcp_0_rx_meta.tie_off_s();
always_comb tcp_0_tx_meta.tie_off_m();
always_comb tcp_0_tx_stat.tie_off_s();
always_comb axis_tcp_0_sink.tie_off_s();
always_comb axis_tcp_0_src.tie_off_m();
`endif
`ifdef EN_TCP_1
always_comb tcp_1_listen_req.tie_off_m();
always_comb tcp_1_listen_rsp.tie_off_s();
always_comb tcp_1_open_req.tie_off_m();
always_comb tcp_1_open_rsp.tie_off_s();
always_comb tcp_1_close_req.tie_off_m();
always_comb tcp_1_notify.tie_off_s();
always_comb tcp_1_rd_pkg.tie_off_m();
always_comb tcp_1_rx_meta.tie_off_s();
always_comb tcp_1_tx_meta.tie_off_m();
always_comb tcp_1_tx_stat.tie_off_s();
always_comb axis_tcp_1_sink.tie_off_s();
always_comb axis_tcp_1_src.tie_off_m();
`endif

/* -- USER LOGIC -------------------------------------------------------- */

`define CIRCT_COMPILED_CODE
`ifdef CIRCT_COMPILED_CODE

    // Circt generated
    tuples inst_tuples (
        .clock(aclk),
        .reset(~aresetn),
        .in0_valid(axis_host_sink.tvalid),
        .in0_ready(axis_host_sink.tready),
        .in0_data_field0(axis_host_sink.tdata[0*32+:32]),
        .in0_data_field1(axis_host_sink.tdata[1*32+:32]),
        .in0_data_field2(axis_host_sink.tdata[2*32+:32]),
        .in0_data_field3(axis_host_sink.tdata[3*32+:32]),
        .in0_data_field4(axis_host_sink.tdata[4*32+:32]),
        .in0_data_field5(axis_host_sink.tdata[5*32+:32]),
        .in0_data_field6(axis_host_sink.tdata[6*32+:32]),
        .in0_data_field7(axis_host_sink.tdata[7*32+:32]),
        .in0_data_field8(axis_host_sink.tdata[8*32+:32]),
        .in0_data_field9(axis_host_sink.tdata[9*32+:32]),
        .in0_data_field10(axis_host_sink.tdata[10*32+:32]),
        .in0_data_field11(axis_host_sink.tdata[11*32+:32]),
        .in0_data_field12(axis_host_sink.tdata[12*32+:32]),
        .in0_data_field13(axis_host_sink.tdata[13*32+:32]),
        .in0_data_field14(axis_host_sink.tdata[14*32+:32]),
        .in0_data_field15(axis_host_sink.tdata[15*32+:32]),
        .inCtrl_valid(axis_host_sink.tvalid & axis_host_sink.tready),
        .inCtrl_ready(),
        .out0_valid(axis_host_src.tvalid),
        .out0_ready(axis_host_src.tready),
        .out0_data(axis_host_src.tdata[31:0]),
        .outCtrl_ready(1'b1),
        .outCtrl_valid()
    );

    assign axis_host_src.tdata[511:32] = 0;
    assign axis_host_src.tkeep = ~0;
    assign axis_host_src.tid   = 0;
    assign axis_host_src.tlast = 1'b0;

`else

    // Simple tuple adder
    adder inst_adder (
        .aclk(aclk),
        .aresetn(aresetn),
        .axis_sink(axis_host_sink),
        .axis_src(axis_host_src)
    );

`endif

endmodule

