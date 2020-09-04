`timescale 1ns / 1ps

import lynxTypes::*;

/**
 * User logic
 * 
 */
module design_user_logic_6 (
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
    AXI4S axis_sink_r();
    axis_reg_rtl inst_r_in (.aclk(aclk), .aresetn(aresetn), .axis_in(axis_sink), .axis_out(axis_sink_r));

    logic resultValid;
    logic [63:0] result;
    logic resetn_hll;

    //
    hll_slave inst_hll_slv (
        .aclk(aclk),
        .aresetn(aresetn),
        .axi_ctrl(axi_ctrl),
        .resultValid(resultValid),
        .result(result),
        .resetn_hll(resetn_hll)
    );

    hyperloglog_0 inst_hll (
        .s_axis_input_tuple_TVALID(axis_sink_r.tvalid),
        .s_axis_input_tuple_TREADY(axis_sink_r.tready),
        .s_axis_input_tuple_TDATA(axis_sink_r.tdata),
        .s_axis_input_tuple_TKEEP(axis_sink_r.tkeep),
        .s_axis_input_tuple_TLAST(axis_sink_r.tlast),
        .regResult_V(result),
        .res_valid_V(resultValid),
        .ap_clk(aclk),
        .ap_rst_n(resetn_hll)
    );


endmodule

