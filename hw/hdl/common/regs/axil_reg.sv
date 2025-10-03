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


`timescale 1ns / 1ps

import lynxTypes::*;

module axil_reg (
	input logic 			aclk,
	input logic 			aresetn,
	
	AXI4L.s 			s_axi,
	AXI4L.m			m_axi
);

axil_register_slice inst_reg_slice (
    .aclk(aclk),
    .aresetn(aresetn),
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