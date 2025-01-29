`timescale 1ns / 1ps

import lynxTypes::*;

`include "axi_macros.svh"

module axisr_reg_array #(
    parameter integer                       N_STAGES = 2,
    parameter integer                       DATA_BITS = AXI_DATA_BITS
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    AXI4SR.s                                s_axis,
    AXI4SR.m                               m_axis
);

// ----------------------------------------------------------------------------------------------------------------------- 
// -- Register slices ---------------------------------------------------------------------------------------------------- 
// ----------------------------------------------------------------------------------------------------------------------- 
AXI4SR #(.AXI4S_DATA_BITS(DATA_BITS)) axis_s [N_STAGES+1] ();

`AXISR_ASSIGN(s_axis, axis_s[0])
`AXISR_ASSIGN(axis_s[N_STAGES], m_axis)

for(genvar i = 0; i < N_STAGES; i++) begin
    axisr_reg #(.DATA_BITS(DATA_BITS)) inst_reg (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_s[i]), .m_axis(axis_s[i+1]));  
end

endmodule