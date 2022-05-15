`timescale 1ns / 1ps

import lynxTypes::*;

`include "axi_macros.svh"

module meta_reg_array_rtl #(
    parameter integer                       N_STAGES = 2 ,
    parameter integer                       DATA_BITS = AXI_DATA_BITS
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    metaIntf.s                              s_meta,
    metaIntf.m                              m_meta
);

// ----------------------------------------------------------------------------------------------------------------------- 
// -- Register slices ---------------------------------------------------------------------------------------------------- 
// ----------------------------------------------------------------------------------------------------------------------- 
AXI4S meta_s [N_STAGES+1] ();

`AXIS_ASSIGN(s_meta, meta_s[0])
`AXIS_ASSIGN(meta_s[N_STAGES], m_meta)

for(genvar i = 0; i < N_STAGES; i++) begin
    meta_reg_rtl #(.DATA_BITS(DATA_BITS)) inst_reg (.aclk(aclk), .aresetn(aresetn), .s_meta(meta_s[i]), .m_meta(meta_s[i+1]));  
end

endmodule