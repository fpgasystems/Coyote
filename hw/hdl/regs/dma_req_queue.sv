import lynxTypes::*;

module dma_req_queue (
	input logic 			aclk,
	input logic 			aresetn,
	
	dmaIntf.s 				req_in,
	dmaIntf.m 				req_out
);

axis_data_fifo_req_96 inst_req (
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

endmodule

