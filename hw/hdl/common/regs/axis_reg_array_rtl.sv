`timescale 1ns / 1ps

import lynxTypes::*;

`include "axi_macros.svh"

module axis_reg_array_rtl #(
    parameter integer                       N_STAGES = 2 ,
    parameter integer                       DATA_BITS = AXI_DATA_BITS
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    AXI4S.s                                 s_axis,
    AXI4S.m                                 m_axis
);

// ----------------------------------------------------------------------------------------------------------------------- 
// -- Register slices ---------------------------------------------------------------------------------------------------- 
// ----------------------------------------------------------------------------------------------------------------------- 
AXI4S axis_s [N_STAGES+1] ();

`AXIS_ASSIGN(s_axis, axis_s[0])
`AXIS_ASSIGN(axis_s[N_STAGES], m_axis)

for(genvar i = 0; i < N_STAGES; i++) begin
    axis_reg_rtl #(.DATA_BITS(DATA_BITS)) inst_reg (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_s[i]), .m_axis(axis_s[i+1]));  
end

endmodule