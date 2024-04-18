`timescale 1ns / 1ps

import lynxTypes::*;

module axisr_ccross #(
	parameter integer DATA_BITS		= AXI_DATA_BITS
) (
	input logic 			s_aclk,
	input logic 			s_aresetn,
	input logic 			m_aclk,
	input logic 			m_aresetn,
	
	AXI4SR.s 				s_axis,
	AXI4SR.m				m_axis
);

if(DATA_BITS == 512) begin
	axisr_clock_converter_512 inst_reg_slice (
		.s_axis_aclk(s_aclk),
		.s_axis_aresetn(s_aresetn),
		.m_axis_aclk(m_aclk),
		.m_axis_aresetn(m_aresetn),
		.s_axis_tvalid(s_axis.tvalid),
		.s_axis_tready(s_axis.tready),
		.s_axis_tdata(s_axis.tdata),
		.s_axis_tkeep(s_axis.tkeep),
		.s_axis_tlast(s_axis.tlast),
		.s_axis_tdest(s_axis.tdest),
		.s_axis_tuser(s_axis.tid),
		.s_axis_tuser(s_axis.tuser),
		.m_axis_tvalid(m_axis.tvalid),
		.m_axis_tready(m_axis.tready),
		.m_axis_tdata(m_axis.tdata),
		.m_axis_tkeep(m_axis.tkeep),
		.m_axis_tlast(m_axis.tlast),
		.m_axis_tdest(m_axis.tdest),
		.m_axis_tid(m_axis.tid),
		.m_axis_tuser(m_axis.tuser)
	);
end
else if(DATA_BITS == 1024) begin
	axisr_clock_converter_1024 inst_reg_slice (
		.s_axis_aclk(s_aclk),
		.s_axis_aresetn(s_aresetn),
		.m_axis_aclk(m_aclk),
		.m_axis_aresetn(m_aresetn),
		.s_axis_tvalid(s_axis.tvalid),
		.s_axis_tready(s_axis.tready),
		.s_axis_tdata(s_axis.tdata),
		.s_axis_tkeep(s_axis.tkeep),
		.s_axis_tlast(s_axis.tlast),
		.s_axis_tdest(s_axis.tdest),
		.s_axis_tuser(s_axis.tid),
		.s_axis_tuser(s_axis.tuser),
		.m_axis_tvalid(m_axis.tvalid),
		.m_axis_tready(m_axis.tready),
		.m_axis_tdata(m_axis.tdata),
		.m_axis_tkeep(m_axis.tkeep),
		.m_axis_tlast(m_axis.tlast),
		.m_axis_tdest(m_axis.tdest),
		.m_axis_tid(m_axis.tid),
		.m_axis_tuser(m_axis.tuser)
	);
end
else if(DATA_BITS == 2048) begin
	axisr_clock_converter_2048 inst_reg_slice (
		.s_axis_aclk(s_aclk),
		.s_axis_aresetn(s_aresetn),
		.m_axis_aclk(m_aclk),
		.m_axis_aresetn(m_aresetn),
		.s_axis_tvalid(s_axis.tvalid),
		.s_axis_tready(s_axis.tready),
		.s_axis_tdata(s_axis.tdata),
		.s_axis_tkeep(s_axis.tkeep),
		.s_axis_tlast(s_axis.tlast),
		.s_axis_tdest(s_axis.tdest),
		.s_axis_tuser(s_axis.tid),
		.s_axis_tuser(s_axis.tuser),
		.m_axis_tvalid(m_axis.tvalid),
		.m_axis_tready(m_axis.tready),
		.m_axis_tdata(m_axis.tdata),
		.m_axis_tkeep(m_axis.tkeep),
		.m_axis_tlast(m_axis.tlast),
		.m_axis_tdest(m_axis.tdest),
		.m_axis_tid(m_axis.tid),
		.m_axis_tuser(m_axis.tuser)
	);
end

endmodule