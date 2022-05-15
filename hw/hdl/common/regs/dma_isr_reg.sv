`timescale 1ns / 1ps

import lynxTypes::*;

module dma_isr_reg (
	input logic 			aclk,
	input logic 			aresetn,
	
	dmaIsrIntf.s 		    s_req,
	dmaIsrIntf.m 		    m_req
);

axis_register_slice_req_128 inst_reg_slice (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_axis_tvalid(s_req.valid),
    .s_axis_tready(s_req.ready),
    .s_axis_tdata(s_req.req),
    .m_axis_tvalid(m_req.valid),
    .m_axis_tready(m_req.ready),
    .m_axis_tdata(m_req.req)
);

always_ff @( posedge aclk ) begin : REG
    if(~aresetn) begin
        s_req.rsp.done <= 1'b0;
        s_req.rsp.pid <= 'X;
        s_req.rsp.isr <= 'X;
    end
    else begin
        s_req.rsp <= m_req.rsp;
    end
end

endmodule