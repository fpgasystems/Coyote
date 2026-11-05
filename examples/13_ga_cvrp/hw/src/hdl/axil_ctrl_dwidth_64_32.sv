/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2026, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

`timescale 1ns / 1ps

module axil_ctrl_dwidth_64_32 (
    input  logic        s_axi_aclk,
    input  logic        s_axi_aresetn,

    // 64-bit AXI4-Lite Slave Interface (from Coyote user CSR axi_ctrl)
    input  logic [31:0] s_axi_awaddr,
    input  logic [2:0]  s_axi_awprot,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,
    input  logic [63:0] s_axi_wdata,
    input  logic [7:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,

    input  logic [31:0] s_axi_araddr,
    input  logic [2:0]  s_axi_arprot,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,
    output logic [63:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    // 32-bit AXI4-Lite Master Interface (to HLS kernel s_axi_control)
    output logic [31:0] m_axi_awaddr,
    output logic [2:0]  m_axi_awprot,
    output logic        m_axi_awvalid,
    input  logic        m_axi_awready,
    output logic [31:0] m_axi_wdata,
    output logic [3:0]  m_axi_wstrb,
    output logic        m_axi_wvalid,
    input  logic        m_axi_wready,
    input  logic [1:0]  m_axi_bresp,
    input  logic        m_axi_bvalid,
    output logic        m_axi_bready,

    output logic [31:0] m_axi_araddr,
    output logic [2:0]  m_axi_arprot,
    output logic        m_axi_arvalid,
    input  logic        m_axi_arready,
    input  logic [31:0] m_axi_rdata,
    input  logic [1:0]  m_axi_rresp,
    input  logic        m_axi_rvalid,
    output logic        m_axi_rready
);

    axil_adapter #(
        .ADDR_WIDTH   (32),
        .S_DATA_WIDTH (64),
        .S_STRB_WIDTH (8),
        .M_DATA_WIDTH (32),
        .M_STRB_WIDTH (4)
    ) inst_axil_adapter (
        .clk             (s_axi_aclk),
        .rst             (~s_axi_aresetn),

        // Slave interface (64-bit)
        .s_axil_awaddr   (s_axi_awaddr),
        .s_axil_awprot   (s_axi_awprot),
        .s_axil_awvalid  (s_axi_awvalid),
        .s_axil_awready  (s_axi_awready),
        .s_axil_wdata    (s_axi_wdata),
        .s_axil_wstrb    (s_axi_wstrb),
        .s_axil_wvalid   (s_axi_wvalid),
        .s_axil_wready   (s_axi_wready),
        .s_axil_bresp    (s_axi_bresp),
        .s_axil_bvalid   (s_axi_bvalid),
        .s_axil_bready   (s_axi_bready),
        .s_axil_araddr   (s_axi_araddr),
        .s_axil_arprot   (s_axi_arprot),
        .s_axil_arvalid  (s_axi_arvalid),
        .s_axil_arready  (s_axi_arready),
        .s_axil_rdata    (s_axi_rdata),
        .s_axil_rresp    (s_axi_rresp),
        .s_axil_rvalid   (s_axi_rvalid),
        .s_axil_rready   (s_axi_rready),

        // Master interface (32-bit)
        .m_axil_awaddr   (m_axi_awaddr),
        .m_axil_awprot   (m_axi_awprot),
        .m_axil_awvalid  (m_axi_awvalid),
        .m_axil_awready  (m_axi_awready),
        .m_axil_wdata    (m_axi_wdata),
        .m_axil_wstrb    (m_axi_wstrb),
        .m_axil_wvalid   (m_axi_wvalid),
        .m_axil_wready   (m_axi_wready),
        .m_axil_bresp    (m_axi_bresp),
        .m_axil_bvalid   (m_axi_bvalid),
        .m_axil_bready   (m_axi_bready),
        .m_axil_araddr   (m_axi_araddr),
        .m_axil_arprot   (m_axi_arprot),
        .m_axil_arvalid  (m_axi_arvalid),
        .m_axil_arready  (m_axi_arready),
        .m_axil_rdata    (m_axi_rdata),
        .m_axil_rresp    (m_axi_rresp),
        .m_axil_rvalid   (m_axi_rvalid),
        .m_axil_rready   (m_axi_rready)
    );

endmodule
