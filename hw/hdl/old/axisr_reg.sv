`timescale 1ns / 1ps

import lynxTypes::*;

module axisr_reg #(
	parameter integer DATA_BITS		= AXI_DATA_BITS
) (
	input logic 			aclk,
	input logic 			aresetn,
	
	AXI4SR.s 				s_axis,
	AXI4SR.m				m_axis
);

if(DATA_BITS == 512) begin
	axisr_register_slice_512 inst_reg_slice (
		.aclk(aclk),
		.aresetn(aresetn),
		.s_axis_tvalid(s_axis.tvalid),
		.s_axis_tready(s_axis.tready),
		.s_axis_tdata(s_axis.tdata),
		.s_axis_tkeep(s_axis.tkeep),
		.s_axis_tlast(s_axis.tlast),
		.s_axis_tdest(s_axis.tdest),
		.s_axis_tid(s_axis.tid),
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
	axisr_register_slice_1k inst_reg_slice (
		.aclk(aclk),
		.aresetn(aresetn),
		.s_axis_tvalid(s_axis.tvalid),
		.s_axis_tready(s_axis.tready),
		.s_axis_tdata(s_axis.tdata),
		.s_axis_tkeep(s_axis.tkeep),
		.s_axis_tlast(s_axis.tlast),
		.s_axis_tdest(s_axis.tdest),
		.s_axis_tid(s_axis.tid),
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
	axisr_register_slice_2k inst_reg_slice (
		.aclk(aclk),
		.aresetn(aresetn),
		.s_axis_tvalid(s_axis.tvalid),
		.s_axis_tready(s_axis.tready),
		.s_axis_tdata(s_axis.tdata),
		.s_axis_tkeep(s_axis.tkeep),
		.s_axis_tlast(s_axis.tlast),
		.s_axis_tdest(s_axis.tdest),
		.s_axis_tid(s_axis.tid),
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