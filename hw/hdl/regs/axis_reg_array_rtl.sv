import lynxTypes::*;

`include "axi_macros.svh"

module axis_reg_array_rtl #(
    parameter integer                       N_STAGES = 2  
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    AXI4S.s                                 axis_in,
    AXI4S.m                                 axis_out
);

// ----------------------------------------------------------------------------------------------------------------------- 
// -- Register slices ---------------------------------------------------------------------------------------------------- 
// ----------------------------------------------------------------------------------------------------------------------- 
AXI4S axis_s [N_STAGES+1] ();

`AXIS_ASSIGN(axis_in, axis_s[0])
`AXIS_ASSIGN(axis_s[N_STAGES], axis_out)

for(genvar i = 0; i < N_STAGES; i++) begin
    axis_reg_rtl inst_reg (.aclk(aclk), .aresetn(aresetn), .axis_in(axis_s[i]), .axis_out(axis_s[i+1]));  
end

endmodule