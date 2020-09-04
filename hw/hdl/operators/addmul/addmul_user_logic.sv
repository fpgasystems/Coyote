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

logic [15:0] mul_factor;
logic [15:0] add_factor;

// Slave
addmul_slave inst_slave (
    .aclk(aclk),
    .aresetn(aresetn),
    .axi_ctrl(axi_ctrl),
    .mul_factor(mul_factor),
    .add_factor(add_factor)
);

// Addmul
addmul #(
    .ADDMUL_DATA_BITS(AXI_DATA_BITS)
) inst_top (
    .aclk(aclk),
    .aresetn(aresetn),
    .mul_factor(mul_factor),
    .add_factor(add_factor),
    .axis_in(axis_sink_r),
    .axis_out(axis_src_r)
);

endmodule
