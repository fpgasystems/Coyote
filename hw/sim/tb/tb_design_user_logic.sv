`timescale 1ns / 1ps

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
    AXI4S.m                     axis_host_src,
    AXI4S.s                     axis_host_sink,

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
//always_comb rd_req_user.tie_off_m();
//always_comb wr_req_user.tie_off_m();
always_comb rd_req_rdma.tie_off_s();
//always_comb wr_req_rdma.tie_off_s();
//always_comb fv_sink.tie_off_s();
//always_comb fv_src.tie_off_m();
//always_comb axis_rdma_src.tie_off_m();
//always_comb axis_rdma_sink.tie_off_s();
//always_comb axis_host_src.tie_off_m();
//always_comb axis_host_sink.tie_off_s();

/* -- USER LOGIC -------------------------------------------------------- */

// Base Read + Write
always_comb begin
    axis_host_src.tvalid    = axis_host_sink.tvalid;
    axis_host_src.tdata     = ~axis_host_sink.tdata;
    axis_host_src.tkeep     = axis_host_sink.tkeep;
    axis_host_src.tlast     = axis_host_sink.tlast;
    axis_host_sink.tready   = axis_host_src.tready;
end

endmodule

