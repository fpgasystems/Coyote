`timescale 1ns / 1ps

import lynxTypes::*;

module data_queue_credits_sink (
	input logic 			aclk,
	input logic 			aresetn,
	
	AXI4S.s 				s_axis,
	AXI4S.m 				m_axis,

    output logic            wxfer
);


    axis_data_fifo_512 inst_data (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(s_axis.tvalid),
        .s_axis_tready(s_axis.tready),
        .s_axis_tdata(s_axis.tdata),
        .s_axis_tkeep(s_axis.tkeep),
        .s_axis_tlast(s_axis.tlast),
        .m_axis_tvalid(m_axis.tvalid),
        .m_axis_tready(m_axis.tready),
        .m_axis_tdata(m_axis.tdata),
        .m_axis_tkeep(m_axis.tkeep),
        .m_axis_tlast(m_axis.tlast)
    );

    assign wxfer = s_axis.tvalid & s_axis.tready;

endmodule

