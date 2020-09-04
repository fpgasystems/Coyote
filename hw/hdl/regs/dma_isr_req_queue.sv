import lynxTypes::*;

module dma_isr_req_queue (
	input logic 			aclk,
	input logic 			aresetn,
	
	dmaIsrIntf.s 			req_in,
	dmaIsrIntf.m 			req_out
);

axis_data_fifo_req_128 inst_req (
    .s_axis_aresetn(aresetn),
    .s_axis_aclk(aclk),
    .s_axis_tvalid(req_in.valid),
    .s_axis_tready(req_in.ready),
    .s_axis_tdata(req_in.req),
    .m_axis_tvalid(req_out.valid),
    .m_axis_tready(req_out.ready),
    .m_axis_tdata(req_out.req)
);

assign req_in.done = req_out.done;
assign req_in.isr_return = req_out.isr_return;

endmodule

