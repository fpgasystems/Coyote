// nodbg variant of A01_hello_world — ILA (ila_perf_host) removed
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

