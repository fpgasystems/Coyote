`timescale 1ns / 1ps

import lynxTypes::*;

`include "axi_macros.svh"
`include "lynx_macros.svh"

/**
 * User logic
 * 
 */
module design_user_logic_c0_0 (
    AXI4L.s                     axi_ctrl,

    // NOTIFY
    metaIntf.m                  notify,

    // DESCRIPTORS
    metaIntf.m                  sq_rd, 
    metaIntf.m                  sq_wr,
    metaIntf.s                  cq_rd,
    metaIntf.s                  cq_wr,
`ifdef EN_RDMA
    metaIntf.s                  rq_rd,
`endif
`ifdef EN_NET
    metaIntf.s                  rq_wr,
`endif

`ifdef EN_STRM
    // HOST DATA STREAMS
    AXI4S.s                    axis_host_resp [N_STRM_AXI],
    AXI4S.m                    axis_host_send [N_STRM_AXI],
`endif 
`ifdef EN_CARD
    // CARD DATA STREAMS
    AXI4S.s                    axis_card_resp [N_CARD_AXI],
    AXI4S.m                    axis_card_send [N_CARD_AXI],
`endif
`ifdef EN_RDMA
    // RDMA DATA STREAMS
    AXI4S.s                    axis_rdma_resp [N_RDMA_AXI],
    AXI4S.m                    axis_rdma_send [N_RDMA_AXI],
    AXI4S.s                    axis_rdma_recv [N_RDMA_AXI],
`endif 
`ifdef EN_TCP
    // TCP/IP DATA STREAMS
    AXI4S.m                    axis_tcp_send [N_TCP_AXI],
    AXI4S.s                    axis_tcp_recv [N_TCP_AXI],
`endif
    // Clock and reset
    input  wire                 aclk,
    input  wire[0:0]            aresetn
);

/* -- Tie-off unused interfaces and signals ----------------------------- */
always_comb axi_ctrl.tie_off_s();
always_comb notify.tie_off_m();
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();
`ifdef EN_RDMA
always_comb rq_rd.tie_off_s();
`endif
`ifdef EN_NET
always_comb rq_wr.tie_off_s();
`endif

/* -- USER LOGIC -------------------------------------------------------- */

// By default just a loopback ...
`ifdef EN_STRM
    for(genvar i = 0; i < N_STRM_AXI; i++) begin
        `AXIS_ASSIGN(axis_host_resp[i], axis_host_send[i])
    end
`endif

`ifdef EN_MEM
    for(genvar i = 0; i < N_CARD_AXI; i++) begin
        `AXIS_ASSIGN(axis_card_resp[i], axis_card_send[i])
    end
`endif

`ifdef EN_RDMA
    for(genvar i = 0; i < N_RDMA_AXI; i++) begin
        `AXIS_ASSIGN(axis_rdma_recv[i], axis_rdma_send[i])
        always_comb axis_rdma_resp[i].tie_off_s();
    end
`endif

`ifdef EN_TCP
    for(genvar i = 0; i < N_TCP_AXI; i++) begin
        `AXIS_ASSIGN(axis_tcp_recv[i], axis_tcp_send[i])
    end
`endif

endmodule

