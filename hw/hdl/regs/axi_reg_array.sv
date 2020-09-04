import lynxTypes::*;

`include "axi_macros.svh"

module axi_reg_array #(
    parameter integer                       N_STAGES = 2  
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    AXI4.s                                  axi_in,
    AXI4.m                                  axi_out
);

// ----------------------------------------------------------------------------------------------------------------------- 
// -- Register slices ---------------------------------------------------------------------------------------------------- 
// ----------------------------------------------------------------------------------------------------------------------- 
AXI4 axi_s [N_STAGES+1] ();

`AXIS_ASSIGN(axi_in, axi_s[0])
`AXIS_ASSIGN(axi_s[N_STAGES], axi_out)

for(genvar i = 0; i < N_STAGES; i++) begin
    axi_reg inst_reg (.aclk(aclk), .aresetn(aresetn), .axi_in(axi_s[i]), .axi_out(axi_s[i+1]));  
end

endmodule