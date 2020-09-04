import lynxTypes::*;

module axil_reg (
	input logic 			aclk,
	input logic 			aresetn,
	
	AXI4L.s 				axi_in,
	AXI4L.m 				axi_out
);

axil_register_slice_0 (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_axi_awaddr(axi_in.awaddr),
    .s_axi_awprot(axi_in.awprot),
    .s_axi_awvalid(axi_in.awvalid),
    .s_axi_awready(axi_in.awready),
    .s_axi_araddr(axi_in.araddr),
    .s_axi_arprot(axi_in.arprot),
    .s_axi_arvalid(axi_in.arvalid),
    .s_axi_arready(axi_in.arready),
    .s_axi_wdata(axi_in.wdata),
    .s_axi_wstrb(axi_in.wstrb),
    .s_axi_wvalid(axi_in.wvalid),
    .s_axi_wready(axi_in.wready),
    .s_axi_bresp(axi_in.bresp),
    .s_axi_bvalid(axi_in.bvalid),
    .s_axi_bready(axi_in.bready),
    .s_axi_rdata(axi_in.rdata),
    .s_axi_rresp(axi_in.rresp),
    .s_axi_rvalid(axi_in.rvalid),
    .s_axi_rready(axi_in.rready),
    .m_axi_awaddr(axi_out.awaddr),
    .m_axi_awprot(axi_out.awprot),
    .m_axi_awvalid(axi_out.awvalid),
    .m_axi_awready(axi_out.awready),
    .m_axi_araddr(axi_out.araddr),
    .m_axi_arprot(axi_out.arprot),
    .m_axi_arvalid(axi_out.arvalid),
    .m_axi_arready(axi_out.arready),
    .m_axi_wdata(axi_out.wdata),
    .m_axi_wstrb(axi_out.wstrb),
    .m_axi_wvalid(axi_out.wvalid),
    .m_axi_wready(axi_out.wready),
    .m_axi_bresp(axi_out.bresp),
    .m_axi_bvalid(axi_out.bvalid),
    .m_axi_bready(axi_out.bready),
    .m_axi_rdata(axi_out.rdata),
    .m_axi_rresp(axi_out.rresp),
    .m_axi_rvalid(axi_out.rvalid),
    .m_axi_rready(axi_out.rready)
);

endmodule