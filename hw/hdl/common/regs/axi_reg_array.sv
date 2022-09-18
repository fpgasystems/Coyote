`timescale 1ns / 1ps

import lynxTypes::*;

`include "axi_macros.svh"

module axi_reg_array #(
    parameter integer                       N_STAGES = 2,
    parameter integer                       ID_BITS = AXI_ID_BITS,
    parameter integer                       ADDR_BITS = AXI_ADDR_BITS
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    AXI4.s                                  s_axi,
    AXI4.m                                  m_axi
);

// ----------------------------------------------------------------------------------------------------------------------- 
// -- Register slices ---------------------------------------------------------------------------------------------------- 
// ----------------------------------------------------------------------------------------------------------------------- 
AXI4 #(.AXI4_ID_BITS(ID_BITS), .AXI4_ADDR_BITS(ADDR_BITS)) axi_s [N_STAGES+1] ();

`AXI_ASSIGN(s_axi, axi_s[0])
`AXI_ASSIGN(axi_s[N_STAGES], m_axi)

for(genvar i = 0; i < N_STAGES; i++) begin
    axi_reg inst_reg (.aclk(aclk), .aresetn(aresetn), .s_axi(axi_s[i]), .m_axi(axi_s[i+1]));  
end

endmodule