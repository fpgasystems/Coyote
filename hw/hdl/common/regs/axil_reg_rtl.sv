/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2021-2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

import lynxTypes::*;

module axil_reg_rtl (
    input  wire                     aclk,
    input  wire                     aresetn,

    // AXIL in
    AXI4L.s                     s_axi,

    // AXIL out
    AXI4L.m                     m_axi
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
    .s_axil_awaddr(s_axi.awaddr),
    .s_axil_awprot(s_axi.awprot),
    .s_axil_awvalid(s_axi.awvalid),
    .s_axil_awready(s_axi.awready),
    .s_axil_wdata(s_axi.wdata),
    .s_axil_wstrb(s_axi.wstrb),
    .s_axil_wvalid(s_axi.wvalid),
    .s_axil_wready(s_axi.wready),
    .s_axil_bresp(s_axi.bresp),
    .s_axil_bvalid(s_axi.bvalid),
    .s_axil_bready(s_axi.bready),

    /*
     * AXI lite master interface
     */
    .m_axil_awaddr(m_axi.awaddr),
    .m_axil_awprot(m_axi.awprot),
    .m_axil_awvalid(m_axi.awvalid),
    .m_axil_awready(m_axi.awready),
    .m_axil_wdata(m_axi.wdata),
    .m_axil_wstrb(m_axi.wstrb),
    .m_axil_wvalid(m_axi.wvalid),
    .m_axil_wready(m_axi.wready),
    .m_axil_bresp(m_axi.bresp),
    .m_axil_bvalid(m_axi.bvalid),
    .m_axil_bready(m_axi.bready)
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
    .s_axil_araddr(s_axi.araddr),
    .s_axil_arprot(s_axi.arprot),
    .s_axil_arvalid(s_axi.arvalid),
    .s_axil_arready(s_axi.arready),
    .s_axil_rdata(s_axi.rdata),
    .s_axil_rresp(s_axi.rresp),
    .s_axil_rvalid(s_axi.rvalid),
    .s_axil_rready(s_axi.rready),

    /*
     * AXI lite master interface
     */
    .m_axil_araddr(m_axi.araddr),
    .m_axil_arprot(m_axi.arprot),
    .m_axil_arvalid(m_axi.arvalid),
    .m_axil_arready(m_axi.arready),
    .m_axil_rdata(m_axi.rdata),
    .m_axil_rresp(m_axi.rresp),
    .m_axil_rvalid(m_axi.rvalid),
    .m_axil_rready(m_axi.rready)
);

endmodule