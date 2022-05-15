`timescale 1ns / 1ps

import lynxTypes::*;

`include "lynx_macros.svh"

module dma_isr_reg_array #(
    parameter integer                       N_STAGES = 2  
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    dmaIsrIntf.s                            s_req,
    dmaIsrIntf.m                            m_req
);

// ----------------------------------------------------------------------------------------------------------------------- 
// -- Register slices ---------------------------------------------------------------------------------------------------- 
// ----------------------------------------------------------------------------------------------------------------------- 
dmaIsrIntf req_s [N_STAGES+1] ();

`DMA_ISR_REQ_ASSIGN(s_req, req_s[0])
`DMA_ISR_REQ_ASSIGN(req_s[N_STAGES], m_req)

for(genvar i = 0; i < N_STAGES; i++) begin
    dma_isr_reg inst_reg (.aclk(aclk), .aresetn(aresetn), .s_req(req_s[i]), .m_req(req_s[i+1]));  
end

endmodule