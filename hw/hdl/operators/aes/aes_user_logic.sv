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
//AXI4S axis_sink_r ();
//AXI4S axis_src_r ();
//axis_reg_rtl inst_reg_sink (.aclk(aclk), .aresetn(aresetn), .axis_in(axis_sink), .axis_out(axis_sink_r));
//axis_reg_rtl inst_reg_src (.aclk(aclk), .aresetn(aresetn), .axis_in(axis_src_r), .axis_out(axis_src));

localparam integer N_AES_PIPELINES = 4;

logic [127:0] key;
logic key_start;
logic key_done;

// Slave
aes_slave inst_slave (
    .aclk(aclk),
    .aresetn(aresetn),
    .axi_ctrl(axi_ctrl),
    .key_out(key),
    .keyStart(key_start),
    .keyDone(key_done)
);

// AES pipelines
aes_top #(
    .NPAR(N_AES_PIPELINES)
) inst_aes_top (
    .clk(aclk),
    .reset_n(aresetn),
    .stall(~axis_src.tready),
    .key_in(key),
    .keyVal_in(key_start),
    .keyVal_out(key_done),
    .last_in(axis_sink.tlast),
    .last_out(axis_src.tlast),
    .keep_in(axis_sink.tkeep),
    .keep_out(axis_src.tkeep),
    .dVal_in(axis_sink.tvalid),
    .dVal_out(axis_src.tvalid),
    .data_in(axis_sink.tdata),
    .data_out(axis_src.tdata)
);

assign axis_sink.tready = axis_src.tready;

endmodule
