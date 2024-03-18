/**
 * VFPGA TOP
 *
 * Tie up all signals to the user kernels
 * Still to this day, interfaces are not supported by Vivado packager ...
 * This means verilog style port connections are needed.
 * 
 */

import lynxTypes::*;

// Instantiate top level
`ifdef EN_STRM
perf_local inst_host_link (
    .axis_sink          (axis_host_recv[0]),
    .axis_src           (axis_host_send[0]),

    .aclk               (aclk),
    .aresetn            (aresetn)
);
`endif

`ifdef EN_MEM
perf_local inst_card_link (
    .axis_sink          (axis_card_recv[0]),
    .axis_src           (axis_card_send[0]),

    .aclk               (aclk),
    .aresetn            (aresetn)
);
`endif

// Tie-off unused
always_comb axi_ctrl.tie_off_s();
always_comb notify.tie_off_m();
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();

// ILA
ila_perf_host inst_ila_perf_host (
    .clk(aclk),
    .probe0(axis_host_recv[0].tvalid),
    .probe1(axis_host_recv[0].tready),
    .probe2(axis_host_recv[0].tlast),
    .probe3(axis_card_recv[0].tvalid),
    .probe4(axis_card_recv[0].tready),
    .probe5(axis_card_recv[0].tlast)
);