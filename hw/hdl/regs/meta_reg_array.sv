import lynxTypes::*;

`include "lynx_macros.svh"

module meta_reg_array #(
    parameter integer                       N_STAGES = 2
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    metaIntf.s                              meta_in,
    metaIntf.m                              meta_out
);

// ----------------------------------------------------------------------------------------------------------------------- 
// -- Register slices ---------------------------------------------------------------------------------------------------- 
// ----------------------------------------------------------------------------------------------------------------------- 
metaIntf #(.DATA_BITS(FV_REQ_BITS)) meta_s [N_STAGES+1] ();

`META_ASSIGN(meta_in, meta_s[0])
`META_ASSIGN(meta_s[N_STAGES], meta_out)

for(genvar i = 0; i < N_STAGES; i++) begin
    meta_reg inst_reg (.aclk(aclk), .aresetn(aresetn), .meta_in(meta_s[i]), .meta_out(meta_s[i+1]));  
end

endmodule