`timescale 1ns / 1ps

import lynxTypes::*;

`include "axi_macros.svh"

module axil_reg_array #(
    parameter integer                       N_STAGES = 2
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    AXI4L.s                                 s_axi,
    AXI4L.m                                 m_axi
);

// ----------------------------------------------------------------------------------------------------------------------- 
// -- Register slices ---------------------------------------------------------------------------------------------------- 
// ----------------------------------------------------------------------------------------------------------------------- 
AXI4L axi_s [N_STAGES+1] ();

`AXIL_ASSIGN(s_axi, axi_s[0])
`AXIL_ASSIGN(axi_s[N_STAGES], m_axi)

for(genvar i = 0; i < N_STAGES; i++) begin
    axil_reg inst_reg (.aclk(aclk), .aresetn(aresetn), .s_axi(axi_s[i]), .m_axi(axi_s[i+1]));  
end

endmodule