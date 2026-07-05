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

import lynxTypes::*;

`include "axi_macros.svh"

/**
 * Memory striping module
 * Stripes a single memory request from s_axi across multiple memory controllers by genereating seperate requests through M_AXI
 * For e.g., a 4k read request from S_AXI is striped across 4 DDR controllers, each receiving a 1k read request
 *
 * NOTE: This module is only used in the following cases:
 *  - On UltraScale+ devices when more than one DDR channel is enabled
 *  - On Versal devices with HBM configured in all-to-all mode, i.e. when each HBM_NMU can access the entire HBM address space
 * NOTE: On UltraScale+ devices with HBM, this module is bypassed and striping is handled by the RAMA IP.
 */
module axi_stripe #(
    parameter integer   N_STAGES = 1  
) (
    input  logic        aclk,
    input  logic        aresetn,

    AXI4.s              s_axi,
    AXI4.m             m_axi
);

`ifdef EN_MEM_STRIPE

// REGISTER STAGE
AXI4 s_axi_int();
axi_reg_array #(.N_STAGES(N_STAGES)) inst_s_reg_arr (.aclk(aclk), .aresetn(aresetn), .s_axi(s_axi), .m_axi(s_axi_int));

AXI4 m_axi_int();
axi_reg_array #(.N_STAGES(N_STAGES)) inst_m_reg_arr (.aclk(aclk), .aresetn(aresetn), .s_axi(m_axi_int), .m_axi(m_axi));

// READS
axi_stripe_rd inst_axi_stripe_rd (
    .aclk(aclk),
    .aresetn(aresetn),
    
    .s_axi_araddr(s_axi_int.araddr),
    .s_axi_arburst(s_axi_int.arburst),
    .s_axi_arcache(s_axi_int.arcache),
    .s_axi_arid(s_axi_int.arid),
    .s_axi_arlen(s_axi_int.arlen),
    .s_axi_arlock(s_axi_int.arlock),
    .s_axi_arprot(s_axi_int.arprot),
    .s_axi_arqos(s_axi_int.arqos),
    .s_axi_arregion(s_axi_int.arregion),
    .s_axi_arsize(s_axi_int.arsize),
    .s_axi_arready(s_axi_int.arready),
    .s_axi_arvalid(s_axi_int.arvalid),

    .m_axi_araddr(m_axi_int.araddr),
    .m_axi_arburst(m_axi_int.arburst),
    .m_axi_arcache(m_axi_int.arcache),
    .m_axi_arid(m_axi_int.arid),
    .m_axi_arlen(m_axi_int.arlen),
    .m_axi_arlock(m_axi_int.arlock),
    .m_axi_arprot(m_axi_int.arprot),
    .m_axi_arqos(m_axi_int.arqos),
    .m_axi_arregion(m_axi_int.arregion),
    .m_axi_arsize(m_axi_int.arsize),
    .m_axi_arready(m_axi_int.arready),
    .m_axi_arvalid(m_axi_int.arvalid),

    .s_axi_rdata(s_axi_int.rdata),
    .s_axi_rid(s_axi_int.rid),
    .s_axi_rlast(s_axi_int.rlast),
    .s_axi_rresp(s_axi_int.rresp),
    .s_axi_rready(s_axi_int.rready),
    .s_axi_rvalid(s_axi_int.rvalid),

    .m_axi_rdata(m_axi_int.rdata),
    .m_axi_rid(m_axi_int.rid),
    .m_axi_rlast(m_axi_int.rlast),
    .m_axi_rresp(m_axi_int.rresp),
    .m_axi_rready(m_axi_int.rready),
    .m_axi_rvalid(m_axi_int.rvalid)
); 

// WRITES
axi_stripe_wr inst_axi_stripe_wr (
    .aclk(aclk),
    .aresetn(aresetn),
    
    .s_axi_awaddr(s_axi_int.awaddr),
    .s_axi_awburst(s_axi_int.awburst),
    .s_axi_awcache(s_axi_int.awcache),
    .s_axi_awid(s_axi_int.awid),
    .s_axi_awlen(s_axi_int.awlen),
    .s_axi_awlock(s_axi_int.awlock),
    .s_axi_awprot(s_axi_int.awprot),
    .s_axi_awqos(s_axi_int.awqos),
    .s_axi_awregion(s_axi_int.awregion),
    .s_axi_awsize(s_axi_int.awsize),
    .s_axi_awready(s_axi_int.awready),
    .s_axi_awvalid(s_axi_int.awvalid),

    .m_axi_awaddr(m_axi_int.awaddr),
    .m_axi_awburst(m_axi_int.awburst),
    .m_axi_awcache(m_axi_int.awcache),
    .m_axi_awid(m_axi_int.awid),
    .m_axi_awlen(m_axi_int.awlen),
    .m_axi_awlock(m_axi_int.awlock),
    .m_axi_awprot(m_axi_int.awprot),
    .m_axi_awqos(m_axi_int.awqos),
    .m_axi_awregion(m_axi_int.awregion),
    .m_axi_awsize(m_axi_int.awsize),
    .m_axi_awready(m_axi_int.awready),
    .m_axi_awvalid(m_axi_int.awvalid),

    .s_axi_bid(s_axi_int.bid),
    .s_axi_bresp(s_axi_int.bresp),
    .s_axi_bready(s_axi_int.bready),
    .s_axi_bvalid(s_axi_int.bvalid),

    .m_axi_bid(m_axi_int.bid),
    .m_axi_bresp(m_axi_int.bresp),
    .m_axi_bready(m_axi_int.bready),
    .m_axi_bvalid(m_axi_int.bvalid),

    .s_axi_wdata(s_axi_int.wdata),
    .s_axi_wlast(s_axi_int.wlast),
    .s_axi_wstrb(s_axi_int.wstrb),
    .s_axi_wready(s_axi_int.wready),
    .s_axi_wvalid(s_axi_int.wvalid),

    .m_axi_wdata(m_axi_int.wdata),
    .m_axi_wlast(m_axi_int.wlast),
    .m_axi_wstrb(m_axi_int.wstrb),
    .m_axi_wready(m_axi_int.wready),
    .m_axi_wvalid(m_axi_int.wvalid)
); 

`else

`AXI_ASSIGN(s_axi, m_axi)

`endif

endmodule