`timescale 1ns / 1ps

import lynxTypes::*;

`include "axi_macros.svh"

module axi_reg_array_eci #(
    parameter integer                       N_STAGES = 2
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    AXI4.s                                  s_axi,
    AXI4.m                                  m_axi
);

// ----------------------------------------------------------------------------------------------------------------------- 
// -- Register slices ---------------------------------------------------------------------------------------------------- 
// ----------------------------------------------------------------------------------------------------------------------- 
AXI4 #(.AXI4_DATA_BITS(ECI_DATA_BITS), .AXI4_ID_BITS(ECI_ID_BITS), .AXI4_ADDR_BITS(ECI_ADDR_BITS)) axi_s [N_STAGES+1] ();

`AXI_ASSIGN(s_axi, axi_s[0])
`AXI_ASSIGN(axi_s[N_STAGES], m_axi)

for(genvar i = 0; i < N_STAGES; i++) begin
    axi_reg_eci inst_reg (.aclk(aclk), .aresetn(aresetn), .s_axi(axi_s[i]), .m_axi(axi_s[i+1]));  
end

endmodule