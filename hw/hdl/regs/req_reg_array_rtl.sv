import lynxTypes::*;

`include "lynx_macros.svh"

module req_reg_array_rtl #(
    parameter integer                       N_STAGES = 2  
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    reqIntf.s                               req_in,
    reqIntf.m                               req_out
);

// ----------------------------------------------------------------------------------------------------------------------- 
// -- Register slices ---------------------------------------------------------------------------------------------------- 
// ----------------------------------------------------------------------------------------------------------------------- 
reqIntf req_s [N_STAGES+1] ();

`REQ_ASSIGN(req_in, req_s[0])
`REQ_ASSIGN(req_s[N_STAGES], req_out)

for(genvar i = 0; i < N_STAGES; i++) begin
    req_reg_rtl inst_reg (.aclk(aclk), .aresetn(aresetn), .req_in(req_s[i]), .req_out(req_s[i+1]));  
end

endmodule