`timescale 1ns / 1ps

import lynxTypes::*;

`include "axi_macros.svh"

module axis_reg_array_eci #(
    parameter integer                       N_STAGES = 2
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    AXI4S.s                                 s_axis,
    AXI4S.m                                 m_axis
);

// ----------------------------------------------------------------------------------------------------------------------- 
// -- Register slices ---------------------------------------------------------------------------------------------------- 
// ----------------------------------------------------------------------------------------------------------------------- 
AXI4S #(.AXI4S_DATA_BITS(ECI_DATA_BITS)) axis_s [N_STAGES+1] ();

`AXIS_ASSIGN(s_axis, axis_s[0])
`AXIS_ASSIGN(axis_s[N_STAGES], m_axis)

for(genvar i = 0; i < N_STAGES; i++) begin
    axis_reg_eci inst_reg (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_s[i]), .m_axis(axis_s[i+1]));  
end

endmodule