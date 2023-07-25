`timescale 1ns / 1ps

import lynxTypes::*;

`include "axi_macros.svh"
`include "lynx_macros.svh"

/**
 * User logic
 * 
 */
module design_user_logic_c0_0 ( // TODO: Adjust the vFPGA ids
    // AXI4L CONTROL
    AXI4L.s                     axi_ctrl,

`ifdef EN_BPSS
    // DESCRIPTOR BYPASS
    metaIntf.m			        bpss_rd_req,
    metaIntf.m			        bpss_wr_req,
    metaIntf.s                  bpss_rd_done,
    metaIntf.s                  bpss_wr_done,

`endif
`ifdef EN_STRM
    // AXI4S HOST STREAMS
    AXI4SR.s                    axis_host_0_sink,
    AXI4SR.m                    axis_host_0_src,

`endif
`ifdef EN_MEM
    // AXI4S CARD STREAMS
    AXI4SR.s                    axis_card_0_sink,
    AXI4SR.m                    axis_card_0_src,
    
`endif
`ifdef EN_RDMA_0
    // RDMA QSFP0 CMD
    metaIntf.s			        rdma_0_rd_req,
    metaIntf.s 			        rdma_0_wr_req,

    // AXI4S RDMA QSFP0 STREAMS
    AXI4SR.s                    axis_rdma_0_sink,
    AXI4SR.m                    axis_rdma_0_src,

`ifdef EN_RPC
    // RDMA QSFP0 SQ and RQ
    metaIntf.m 			        rdma_0_sq,
    metaIntf.s 			        rdma_0_rq,

`endif
`endif
`ifdef EN_RDMA_1
    // RDMA QSFP1 CMD
    metaIntf.s			        rdma_1_rd_req,
    metaIntf.s 			        rdma_1_wr_req,

    // AXI4S RDMA QSFP1 STREAMS
    AXI4SR.s                    axis_rdma_1_sink,
    AXI4SR.m                    axis_rdma_1_src,

`ifdef EN_RPC
    // RDMA QSFP1 SQ and RQ
    metaIntf.m 			        rdma_1_sq,
    metaIntf.s 			        rdma_1_rq,

`endif
`endif
`ifdef EN_TCP_0
    // TCP/IP QSFP0 CMD
    metaIntf.s			        tcp_0_notify,
    metaIntf.m			        tcp_0_rd_pkg,
    metaIntf.s			        tcp_0_rx_meta,
    metaIntf.m			        tcp_0_tx_meta,
    metaIntf.s			        tcp_0_tx_stat,

    // AXI4S TCP/IP QSFP0 STREAMS
    AXI4SR.s                    axis_tcp_0_sink,
    AXI4SR.m                    axis_tcp_0_src,

`endif
`ifdef EN_TCP_1
    // TCP/IP QSFP1 CMD
    metaIntf.s			        tcp_1_notify,
    metaIntf.m			        tcp_1_rd_pkg,
    metaIntf.s			        tcp_1_rx_meta,
    metaIntf.m			        tcp_1_tx_meta,
    metaIntf.s			        tcp_1_tx_stat,

    // AXI4S TCP/IP QSFP1 STREAMS
    AXI4SR.s                    axis_tcp_1_sink, 
    AXI4SR.m                    axis_tcp_1_src,

`endif
    // Clock and reset
    input  wire                 aclk,
    input  wire[0:0]            aresetn
);

/* -- Tie-off unused interfaces and signals ----------------------------- */
//always_comb axi_ctrl.tie_off_s();
`ifdef EN_BPSS
//always_comb bpss_rd_req.tie_off_m();
//always_comb bpss_wr_req.tie_off_m();
//always_comb bpss_rd_done.tie_off_s();
//always_comb bpss_wr_done.tie_off_s();
`endif
`ifdef EN_STRM
//always_comb axis_host_0_sink.tie_off_s();
//always_comb axis_host_0_src.tie_off_m();
`endif
`ifdef EN_MEM
//always_comb axis_card_0_sink.tie_off_s();
//always_comb axis_card_0_src.tie_off_m();
`endif
`ifdef EN_RDMA_0
//always_comb rdma_0_rd_req.tie_off_s();
//always_comb rdma_0_wr_req.tie_off_s();
//always_comb axis_rdma_0_sink.tie_off_s();
//always_comb axis_rdma_0_src.tie_off_m();
`ifdef EN_RPC
//always_comb rdma_0_sq.tie_off_m();
//always_comb rdma_0_rq.tie_off_m();
`endif
`endif
`ifdef EN_RDMA_1
//always_comb rdma_1_rd_req.tie_off_s();
//always_comb rdma_1_wr_req.tie_off_s();
//always_comb axis_rdma_1_sink.tie_off_s();
//always_comb axis_rdma_1_src.tie_off_m();
`ifdef EN_RPC
//always_comb rdma_1_sq.tie_off_m();
//always_comb rdma_1_rq.tie_off_m();
`endif
`endif
`ifdef EN_TCP_0
//always_comb tcp_0_notify.tie_off_s();
//always_comb tcp_0_rd_pkg.tie_off_m();
//always_comb tcp_0_rx_meta.tie_off_s();
//always_comb tcp_0_tx_meta.tie_off_m();
//always_comb tcp_0_tx_stat.tie_off_s();
//always_comb axis_tcp_0_sink.tie_off_s();
//always_comb axis_tcp_0_src.tie_off_m();
`endif
`ifdef EN_TCP_1
//always_comb tcp_1_notify.tie_off_s();
//always_comb tcp_1_rd_pkg.tie_off_m();
//always_comb tcp_1_rx_meta.tie_off_s();
//always_comb tcp_1_tx_meta.tie_off_m();
//always_comb tcp_1_tx_stat.tie_off_s();
//always_comb axis_tcp_1_sink.tie_off_s();
//always_comb axis_tcp_1_src.tie_off_m();
`endif

/* -- USER LOGIC -------------------------------------------------------- */



endmodule