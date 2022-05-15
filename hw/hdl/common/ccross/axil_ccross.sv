`timescale 1ns / 1ps

import lynxTypes::*;

module axil_ccross (
	input logic 			s_aclk,
	input logic 			s_aresetn,
    input logic 			m_aclk,
    input logic 			m_aresetn,
	
	AXI4L.s 				s_axi,
	AXI4L.m 				m_axi
);

axil_clock_converter (
    .s_axi_aclk(s_aclk),
    .s_axi_aresetn(s_aresetn),
    .m_axi_aclk(m_aclk),
    .m_axi_aresetn(m_aresetn),
    .s_axi_awaddr(s_axi.awaddr),
    .s_axi_awprot(s_axi.awprot),
    .s_axi_awvalid(s_axi.awvalid),
    .s_axi_awready(s_axi.awready),
    .s_axi_araddr(s_axi.araddr),
    .s_axi_arprot(s_axi.arprot),
    .s_axi_arvalid(s_axi.arvalid),
    .s_axi_arready(s_axi.arready),
    .s_axi_wdata(s_axi.wdata),
    .s_axi_wstrb(s_axi.wstrb),
    .s_axi_wvalid(s_axi.wvalid),
    .s_axi_wready(s_axi.wready),
    .s_axi_bresp(s_axi.bresp),
    .s_axi_bvalid(s_axi.bvalid),
    .s_axi_bready(s_axi.bready),
    .s_axi_rdata(s_axi.rdata),
    .s_axi_rresp(s_axi.rresp),
    .s_axi_rvalid(s_axi.rvalid),
    .s_axi_rready(s_axi.rready),
    .m_axi_awaddr(m_axi.awaddr),
    .m_axi_awprot(m_axi.awprot),
    .m_axi_awvalid(m_axi.awvalid),
    .m_axi_awready(m_axi.awready),
    .m_axi_araddr(m_axi.araddr),
    .m_axi_arprot(m_axi.arprot),
    .m_axi_arvalid(m_axi.arvalid),
    .m_axi_arready(m_axi.arready),
    .m_axi_wdata(m_axi.wdata),
    .m_axi_wstrb(m_axi.wstrb),
    .m_axi_wvalid(m_axi.wvalid),
    .m_axi_wready(m_axi.wready),
    .m_axi_bresp(m_axi.bresp),
    .m_axi_bvalid(m_axi.bvalid),
    .m_axi_bready(m_axi.bready),
    .m_axi_rdata(m_axi.rdata),
    .m_axi_rresp(m_axi.rresp),
    .m_axi_rvalid(m_axi.rvalid),
    .m_axi_rready(m_axi.rready)
);

endmodule