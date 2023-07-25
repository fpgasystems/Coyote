`timescale 1ns / 1ps

import lynxTypes::*;

module meta_queue #(
    parameter integer       DATA_BITS = 32
) (
	input logic 			aclk,
	input logic 			aresetn,
	
	metaIntf.s 				s_meta,
	metaIntf.m 				m_meta
);

if(DATA_BITS == 8) begin
	axis_data_fifo_meta_8 inst_meta (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(s_meta.valid),
        .s_axis_tready(s_meta.ready),
        .s_axis_tdata(s_meta.data),
        .m_axis_tvalid(m_meta.valid),
        .m_axis_tready(m_meta.ready),
        .m_axis_tdata(m_meta.data)
    );
end
else if(DATA_BITS == 16) begin
	axis_data_fifo_meta_16 inst_meta (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(s_meta.valid),
        .s_axis_tready(s_meta.ready),
        .s_axis_tdata(s_meta.data),
        .m_axis_tvalid(m_meta.valid),
        .m_axis_tready(m_meta.ready),
        .m_axis_tdata(m_meta.data)
    );
end
else if(DATA_BITS == 32) begin
	axis_data_fifo_meta_32 inst_meta (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(s_meta.valid),
        .s_axis_tready(s_meta.ready),
        .s_axis_tdata(s_meta.data),
        .m_axis_tvalid(m_meta.valid),
        .m_axis_tready(m_meta.ready),
        .m_axis_tdata(m_meta.data)
    );
end
else if(DATA_BITS == 48) begin
	axis_data_fifo_meta_48 inst_meta (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(s_meta.valid),
        .s_axis_tready(s_meta.ready),
        .s_axis_tdata(s_meta.data),
        .m_axis_tvalid(m_meta.valid),
        .m_axis_tready(m_meta.ready),
        .m_axis_tdata(m_meta.data)
    );
end
else if(DATA_BITS == 72) begin
	axis_data_fifo_meta_72 inst_meta (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(s_meta.valid),
        .s_axis_tready(s_meta.ready),
        .s_axis_tdata(s_meta.data),
        .m_axis_tvalid(m_meta.valid),
        .m_axis_tready(m_meta.ready),
        .m_axis_tdata(m_meta.data)
    );
end
else if(DATA_BITS == 96) begin
	axis_data_fifo_meta_96 inst_meta (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(s_meta.valid),
        .s_axis_tready(s_meta.ready),
        .s_axis_tdata(s_meta.data),
        .m_axis_tvalid(m_meta.valid),
        .m_axis_tready(m_meta.ready),
        .m_axis_tdata(m_meta.data)
    );
end
else if(DATA_BITS == 256) begin
	axis_data_fifo_meta_256 inst_meta (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(s_meta.valid),
        .s_axis_tready(s_meta.ready),
        .s_axis_tdata(s_meta.data),
        .m_axis_tvalid(m_meta.valid),
        .m_axis_tready(m_meta.ready),
        .m_axis_tdata(m_meta.data)
    );
end

endmodule

