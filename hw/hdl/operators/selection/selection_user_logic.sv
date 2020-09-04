`timescale 1ns / 1ps

import lynxTypes::*;

/**
 * User logic
 * 
 */
module design_user_logic_0 (
    // Clock and reset
    input  wire                 aclk,
    input  wire[0:0]            aresetn,

    // AXI4 control
    AXI4L.s                     axi_ctrl,

    // AXI4S
    AXI4S.m                     axis_src,
    AXI4S.s                     axis_sink
);

/* -- Tie-off unused interfaces and signals ----------------------------- */
//always_comb axi_ctrl.tie_off_s();
//always_comb axis_src.tie_off_m();
//always_comb axis_sink.tie_off_s();

/* -- USER LOGIC -------------------------------------------------------- */
// Reg input
AXI4S axis_sink_r ();
AXI4S axis_src_r ();
axis_reg_rtl inst_reg_sink (.aclk(aclk), .aresetn(aresetn), .axis_in(axis_sink), .axis_out(axis_sink_r));
axis_reg_rtl inst_reg_src (.aclk(aclk), .aresetn(aresetn), .axis_in(axis_src_r), .axis_out(axis_src));

logic [31:0] selType;
logic [31:0] lowThr;
logic [31:0] uppThr;

// Slave
selection_slave inst_slave (
    .aclk(aclk),                
    .aresetn(aresetn),
    .axi_ctrl(axi_ctrl),
    .selType(selType),
    .lowThr(lowThr),
    .uppThr(uppThr)
);

// Selection
selection inst_top (
    .clk(aclk),
    .rst_n(aresetn),
    .selType(selType),
    .lowThr(lowThr),
    .uppThr(uppThr),
    .axis_in_tvalid(axis_sink_r.tvalid),
    .axis_in_tready(axis_sink_r.tready),
    .axis_in_tdata(axis_sink_r.tdata),
    .axis_in_tkeep(axis_sink_r.tkeep),
    .axis_in_tlast(axis_sink_r.tlast),
    .axis_out_tvalid(axis_src_r.tvalid),
    .axis_out_tready(axis_src_r.tready),
    .axis_out_tdata(axis_src_r.tdata),
    .axis_out_tkeep(axis_src_r.tkeep),
    .axis_out_tlast(axis_src_r.tlast),
);

endmodule
