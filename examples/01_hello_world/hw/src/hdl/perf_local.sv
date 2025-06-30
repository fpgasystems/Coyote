`timescale 1ns / 1ps

import lynxTypes::*;

`include "axi_macros.svh"

/**
 * perf_local example
 * @brief Reads the incoming stream and adds 1 to every integer
 * 
 * @param[in] axis_in Incoming AXI stream
 * @param[out] axis_out Outgoing AXI stream
 * @param[in] aclk Clock signal
 * @param[in] aresetn Active low reset signal
 */
module perf_local (
    AXI4SR.s        axis_in,
    AXI4SR.m        axis_out,

    input  logic    aclk,
    input  logic    aresetn
);

// Simple pipeline stages, buffering the input/output signals (not really needed, but nice to have for easier timing closure)
AXI4SR axis_in_int();
axisr_reg inst_reg_sink (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_in), .m_axis(axis_in_int));

AXI4SR axis_out_int();
axisr_reg inst_reg_src  (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_out_int), .m_axis(axis_out));

// User logic; adding 1 to the input stream and writing it to the output stream
// The other signals (valid, ready etc.) are simply propagated
always_comb begin
    for(int i = 0; i < 16; i++) begin
        axis_out_int.tdata[i*32+:32] = axis_in_int.tdata[i*32+:32] + 1; 
    end
    
    axis_out_int.tvalid  = axis_in_int.tvalid;
    axis_in_int.tready   = axis_out_int.tready;
    axis_out_int.tkeep   = axis_in_int.tkeep;
    axis_out_int.tid     = axis_in_int.tid;
    axis_out_int.tlast   = axis_in_int.tlast;
end

endmodule
