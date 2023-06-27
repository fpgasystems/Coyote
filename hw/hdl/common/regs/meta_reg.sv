`timescale 1ns / 1ps

import lynxTypes::*;

module meta_reg #(
	parameter DATA_BITS = 32
) (
	input logic 			aclk,
	input logic 			aresetn,
	
	metaIntf.s 				s_meta,
	metaIntf.m 				m_meta
);

if(DATA_BITS == 6) begin
	axis_register_slice_meta_8 inst_reg_slice (
		.aclk(aclk),
		.aresetn(aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_meta.data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_meta.data)
	);
end
if(DATA_BITS == 11) begin
	axis_register_slice_meta_16 inst_reg_slice (
		.aclk(aclk),
		.aresetn(aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_meta.data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_meta.data)
	);
end
if(DATA_BITS == 13) begin
	axis_register_slice_meta_16 inst_reg_slice (
		.aclk(aclk),
		.aresetn(aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_meta.data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_meta.data)
	);
end
if(DATA_BITS == 32) begin
	axis_register_slice_meta_32 inst_reg_slice (
		.aclk(aclk),
		.aresetn(aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_meta.data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_meta.data)
	);
end
if(DATA_BITS == 56) begin
	axis_register_slice_meta_56 inst_reg_slice (
		.aclk(aclk),
		.aresetn(aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_meta.data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_meta.data)
	);
end
if(DATA_BITS == 64) begin
	axis_register_slice_meta_64 inst_reg_slice (
		.aclk(aclk),
		.aresetn(aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_meta.data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_meta.data)
	);
end
if(DATA_BITS == 96) begin
	axis_register_slice_meta_96 inst_reg_slice (
		.aclk(aclk),
		.aresetn(aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_meta.data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_meta.data)
	);
end
if(DATA_BITS == 128) begin
	axis_register_slice_meta_128 inst_reg_slice (
		.aclk(aclk),
		.aresetn(aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_meta.data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_meta.data)
	);
end
if(DATA_BITS == 256) begin
	axis_register_slice_meta_256 inst_reg_slice (
		.aclk(aclk),
		.aresetn(aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_meta.data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_meta.data)
	);
end
if(DATA_BITS == 544) begin
	axis_register_slice_meta_544 inst_reg_slice (
		.aclk(aclk),
		.aresetn(aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_meta.data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_meta.data)
	);
end

endmodule