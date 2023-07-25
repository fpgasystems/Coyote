`timescale 1ns / 1ps

import lynxTypes::*;

module meta_ccross #(
	parameter integer DATA_BITS		= 32
) (
	input logic 			s_aclk,
	input logic 			s_aresetn,
	input logic 			m_aclk,
	input logic 			m_aresetn,
	
	metaIntf.s 				s_meta,
	metaIntf.m 				m_meta
);

if(DATA_BITS == 6) begin
	meta_clock_converter_8 inst_reg_slice (
		.s_axis_aclk(s_aclk),
		.s_axis_aresetn(s_aresetn),
		.m_axis_aclk(m_aclk),
		.m_axis_aresetn(m_aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_meta.data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_meta.data)
	);
end
if(DATA_BITS == 11) begin
	meta_clock_converter_16 inst_reg_slice (
		.s_axis_aclk(s_aclk),
		.s_axis_aresetn(s_aresetn),
		.m_axis_aclk(m_aclk),
		.m_axis_aresetn(m_aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_meta.data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_meta.data)
	);
end
if(DATA_BITS == 13) begin
	meta_clock_converter_16 inst_reg_slice (
		.s_axis_aclk(s_aclk),
		.s_axis_aresetn(s_aresetn),
		.m_axis_aclk(m_aclk),
		.m_axis_aresetn(m_aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_meta.data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_meta.data)
	);
end
if(DATA_BITS == 32) begin
	meta_clock_converter_32 inst_reg_slice (
		.s_axis_aclk(s_aclk),
		.s_axis_aresetn(s_aresetn),
		.m_axis_aclk(m_aclk),
		.m_axis_aresetn(m_aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_meta.data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_meta.data)
	);
end
if(DATA_BITS == 96) begin
	meta_clock_converter_96 inst_reg_slice (
		.s_axis_aclk(s_aclk),
		.s_axis_aresetn(s_aresetn),
		.m_axis_aclk(m_aclk),
		.m_axis_aresetn(m_aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_meta.data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_meta.data)
	);
end
else if(DATA_BITS == 256) begin
	meta_clock_converter_256 inst_reg_slice (
		.s_axis_aclk(s_aclk),
		.s_axis_aresetn(s_aresetn),
		.m_axis_aclk(m_aclk),
		.m_axis_aresetn(m_aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_meta.data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_meta.data)
	);
end

endmodule