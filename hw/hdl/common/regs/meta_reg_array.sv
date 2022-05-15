import lynxTypes::*;

`include "lynx_macros.svh"

module meta_reg_array #(
    parameter integer                       N_STAGES = 2,
    parameter integer                       DATA_BITS = 32
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    metaIntf.s                              s_meta,
    metaIntf.m                              m_meta
);

// ----------------------------------------------------------------------------------------------------------------------- 
// -- Register slices ---------------------------------------------------------------------------------------------------- 
// ----------------------------------------------------------------------------------------------------------------------- 
metaIntf #(.STYPE(logic[DATA_BITS-1:0])) meta_s [N_STAGES+1] ();

`META_ASSIGN(s_meta, meta_s[0])
`META_ASSIGN(meta_s[N_STAGES], m_meta)

for(genvar i = 0; i < N_STAGES; i++) begin
    meta_reg #(.DATA_BITS(DATA_BITS)) inst_reg (.aclk(aclk), .aresetn(aresetn), .s_meta(meta_s[i]), .m_meta(meta_s[i+1]));  
end

endmodule