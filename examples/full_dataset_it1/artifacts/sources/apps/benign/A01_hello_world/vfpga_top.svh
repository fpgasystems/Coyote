// Full dataset it1 — A01_hello_world (adapted from example 01)
// Removed inst_card_link (requires EN_MEM=1 / axis_card_*).
// Added stream[1] tie-offs for N_STRM_AXI=2 shell.

import lynxTypes::*;

// Data movement host memory => vFPGA => host memory
perf_local inst_host_link (
    .axis_in    (axis_host_recv[0]),
    .axis_out   (axis_host_send[0]),
    .aclk       (aclk),
    .aresetn    (aresetn)
);

// Tie-off unused stream[1] (shell has N_STRM_AXI=2)
always_comb axis_host_recv[1].tie_off_s();
always_comb axis_host_send[1].tie_off_m();

// Tie-off unused signals to avoid synthesis problems
always_comb notify.tie_off_m();
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();
always_comb axi_ctrl.tie_off_s();

// Debug ILA
ila_perf_host inst_ila_perf_host (
    .clk(aclk),
    .probe0(axis_host_recv[0].tvalid),  // 1 bit
    .probe1(axis_host_recv[0].tready),  // 1 bit
    .probe2(axis_host_recv[0].tlast),   // 1 bit
    .probe3(axis_host_recv[0].tdata),   // 512 bits
    .probe4(axis_host_send[0].tvalid),  // 1 bit
    .probe5(axis_host_send[0].tready),  // 1 bit
    .probe6(axis_host_send[0].tlast),   // 1 bit
    .probe7(axis_host_send[0].tdata)    // 512 bits
);
