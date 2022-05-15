import lynxTypes::*;

module axil_reg_rtl (
    input  wire                     aclk,
    input  wire                     aresetn,

    // AXIL in
    AXI4L.s                         s_axil,

    // AXIL out
    AXI4L.m                         m_axil
);

axil_register_wr #(
    .DATA_WIDTH(AXIL_DATA_BITS),
    .ADDR_WIDTH(AXI_ADDR_BITS),
    .STRB_WIDTH(AXIL_DATA_BITS/8),
    .AW_REG_TYPE(1),
    .W_REG_TYPE(1),
    .B_REG_TYPE(1)
) axil_register_wr_inst (
    .clk(aclk),
    .rst(~aresetn),

    /*
     * AXI lite slave interface
     */
    .s_axil_awaddr(s_axil.awaddr),
    .s_axil_awprot(s_axil.awprot),
    .s_axil_awvalid(s_axil.awvalid),
    .s_axil_awready(s_axil.awready),
    .s_axil_wdata(s_axil.wdata),
    .s_axil_wstrb(s_axil.wstrb),
    .s_axil_wvalid(s_axil.wvalid),
    .s_axil_wready(s_axil.wready),
    .s_axil_bresp(s_axil.bresp),
    .s_axil_bvalid(s_axil.bvalid),
    .s_axil_bready(s_axil.bready),

    /*
     * AXI lite master interface
     */
    .m_axil_awaddr(m_axil.awaddr),
    .m_axil_awprot(m_axil.awprot),
    .m_axil_awvalid(m_axil.awvalid),
    .m_axil_awready(m_axil.awready),
    .m_axil_wdata(m_axil.wdata),
    .m_axil_wstrb(m_axil.wstrb),
    .m_axil_wvalid(m_axil.wvalid),
    .m_axil_wready(m_axil.wready),
    .m_axil_bresp(m_axil.bresp),
    .m_axil_bvalid(m_axil.bvalid),
    .m_axil_bready(m_axil.bready)
);

axil_register_rd #(
    .DATA_WIDTH(AXIL_DATA_BITS),
    .ADDR_WIDTH(AXI_ADDR_BITS),
    .STRB_WIDTH(AXIL_DATA_BITS/8),
    .AR_REG_TYPE(1),
    .R_REG_TYPE(1)
)
axil_register_rd_inst (
    .clk(aclk),
    .rst(~aresetn),

    /*
     * AXI lite slave interface
     */
    .s_axil_araddr(s_axil.araddr),
    .s_axil_arprot(s_axil.arprot),
    .s_axil_arvalid(s_axil.arvalid),
    .s_axil_arready(s_axil.arready),
    .s_axil_rdata(s_axil.rdata),
    .s_axil_rresp(s_axil.rresp),
    .s_axil_rvalid(s_axil.rvalid),
    .s_axil_rready(s_axil.rready),

    /*
     * AXI lite master interface
     */
    .m_axil_araddr(m_axil.araddr),
    .m_axil_arprot(m_axil.arprot),
    .m_axil_arvalid(m_axil.arvalid),
    .m_axil_arready(m_axil.arready),
    .m_axil_rdata(m_axil.rdata),
    .m_axil_rresp(m_axil.rresp),
    .m_axil_rvalid(m_axil.rvalid),
    .m_axil_rready(m_axil.rready)
);

endmodule