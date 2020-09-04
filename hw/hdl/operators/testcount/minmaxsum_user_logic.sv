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
always_comb axis_src.tie_off_m();
//always_comb axis_sink.tie_off_s();

/* -- USER LOGIC -------------------------------------------------------- */
// Reg input
AXI4S axis_sink_r ();
//AXI4S axis_src_r ();
axis_reg_rtl inst_reg_sink (.aclk(aclk), .aresetn(aresetn), .axis_in(axis_sink), .axis_out(axis_sink_r));
//axis_reg_rtl inst_reg_src (.aclk(aclk), .aresetn(aresetn), .axis_in(axis_src_r), .axis_out(axis_src));

logic clr;
logic done;
logic [3:0] test_type;
logic [31:0] test_condition;
logic [31:0] result_count;

// Slave
testcount_slave inst_slave (
    .aclk(aclk),
    .aresetn(aresetn),
    .axi_ctrl(axi_ctrl),
    .clr(clr),
    .done(done),
    .test_type(test_type),
    .test_condition(test_condition),
    .result_count(result_count)
)

// Minmaxsum
minmaxsum inst_top (
    .clk(aclk),
    .rst_n(aresetn),
    .clr(clr),
    .done(done),
    .test_type(test_type),
    .test_condition(test_condition),
    .result_count(result_count),
    .axis_in(axis_sink_r)
);

endmodule
