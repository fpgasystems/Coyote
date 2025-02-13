import lynxTypes::*;

// Instantiate top-level module
// Given that Coyote is highly configurable, we can enable or disable various components (e.g. card memory)
// Therefore, it is advisable to include safe-guards if certain logic depends on compile-time flags 
// e.g., card memory is only available when compiled with EN_MEM, and if set to false, the signal axis_card_(recv|send) does not exist

// Data movement host memory => vFPGA => host memory
`ifdef EN_STRM
perf_local inst_host_link (
    .axis_in    (axis_host_recv[0]),
    .axis_out   (axis_host_send[0]),
    .aclk       (aclk),
    .aresetn    (aresetn)
);
`endif

// Data movement card memory => vFPGA => card memory
`ifdef EN_MEM
perf_local inst_card_link (
    .axis_in    (axis_card_recv[0]),
    .axis_out   (axis_card_send[0]),
    .aclk       (aclk),
    .aresetn    (aresetn)
);
`endif

// Tie-off unused signals to avoid synthesis problems
always_comb notify.tie_off_m();
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();
always_comb axi_ctrl.tie_off_s();

// Integrated Logic Analyzer (ILA) for debugging on hardware
// Fairly simple ILA, primary meant as an example, to be extended when debugging actual bugs
// See the README.md and init_ip.tcl for more details on how to use and configure ILA
`ifdef EN_STRM
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
`endif
