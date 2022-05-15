`timescale 1ns / 1ps

import lynxTypes::*;

module dma_req_ccross (
	input logic 			s_aclk,
	input logic 			s_aresetn,
	input logic 			m_aclk,
	input logic 			m_aresetn,
	
	dmaIntf.s 				s_req,
	dmaIntf.m 				m_req
);

axis_clock_converter_96 (
    .s_axis_aclk(s_aclk),
    .s_axis_aresetn(s_aresetn),
    .m_axis_aclk(m_aclk),
    .m_axis_aresetn(m_aresetn),
    .s_axis_tvalid(s_req.valid),
    .s_axis_tready(s_req.ready),
    .s_axis_tdata(s_req.req),
    .m_axis_tvalid(m_req.valid),
    .m_axis_tready(m_req.ready),
    .m_axis_tdata(m_req.req)
);

axis_clock_converter_dma_rsp inst_ccross_dma_rsp (
    .s_axis_aclk(m_aclk),
    .s_axis_aresetn(m_aresetn),
    .m_axis_aclk(s_aclk),
    .m_axis_aresetn(s_aresetn),
    .s_axis_tvalid(m_req.rsp.done),
    .s_axis_tready(),
    .s_axis_tuser(0),
    .m_axis_tvalid(s_req.rsp.done),
    .m_axis_tready(1'b1),
    .m_axis_tuser(s_req.rsp.pid)
);

endmodule