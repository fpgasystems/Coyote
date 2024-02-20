/**
  * Copyright (c) 2021, Systems Group, ETH Zurich
  * All rights reserved.
  *
  * Redistribution and use in source and binary forms, with or without modification,
  * are permitted provided that the following conditions are met:
  *
  * 1. Redistributions of source code must retain the above copyright notice,
  * this list of conditions and the following disclaimer.
  * 2. Redistributions in binary form must reproduce the above copyright notice,
  * this list of conditions and the following disclaimer in the documentation
  * and/or other materials provided with the distribution.
  * 3. Neither the name of the copyright holder nor the names of its contributors
  * may be used to endorse or promote products derived from this software
  * without specific prior written permission.
  *
  * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
  * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
  * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
  * IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
  * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
  * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
  * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
  * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
  * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
  */

`timescale 1ns / 1ps

import lynxTypes::*;

`include "axi_macros.svh"

module axi_stripe #(
    parameter integer   N_STAGES = 1  
) (
    input  logic        aclk,
    input  logic        aresetn,

    AXI4.s              s_axi,
    AXI4.m             m_axi
);

`ifdef MULT_DDR_CHAN

AXI4 s_axi_int();
AXI4 m_axi_int();

axi_reg_array #(.N_STAGES(N_STAGES)) inst_s_reg_arr (.aclk(aclk), .aresetn(aresetn), .s_axi(s_axi), .m_axi(s_axi_int));
axi_reg_array #(.N_STAGES(N_STAGES)) inst_m_reg_arr (.aclk(aclk), .aresetn(aresetn), .s_axi(m_axi_int), .m_axi(m_axi));

metaIntf #(.STYPE(logic[1+N_DDR_CHAN_BITS+8-1:0])) mux_r ();
metaIntf #(.STYPE(logic[1+N_DDR_CHAN_BITS+8-1:0])) mux_b ();

// AR
axi_stripe_a inst_axi_stripe_ar (
    .aclk(aclk),
    .aresetn(aresetn),
    
    // AR
    .s_axi_aaddr(s_axi_int.araddr),
    .s_axi_aburst(s_axi_int.arburst),
    .s_axi_acache(s_axi_int.arcache),
    .s_axi_aid(s_axi_int.arid),
    .s_axi_alen(s_axi_int.arlen),
    .s_axi_alock(s_axi_int.arlock),
    .s_axi_aprot(s_axi_int.arprot),
    .s_axi_aqos(s_axi_int.arqos),
    .s_axi_aregion(s_axi_int.arregion),
    .s_axi_asize(s_axi_int.arsize),
    .s_axi_aready(s_axi_int.arready),
    .s_axi_avalid(s_axi_int.arvalid),

    .m_axi_aaddr(m_axi_int.araddr),
    .m_axi_aburst(m_axi_int.arburst),
    .m_axi_acache(m_axi_int.arcache),
    .m_axi_aid(m_axi_int.arid),
    .m_axi_alen(m_axi_int.arlen),
    .m_axi_alock(m_axi_int.arlock),
    .m_axi_aprot(m_axi_int.arprot),
    .m_axi_aqos(m_axi_int.arqos),
    .m_axi_aregion(m_axi_int.arregion),
    .m_axi_asize(m_axi_int.arsize),
    .m_axi_aready(m_axi_int.arready),
    .m_axi_avalid(m_axi_int.arvalid),

    // Mux
    .mux(mux_r)
); 

axi_stripe_r inst_axi_stripe_r (
    .aclk(aclk),
    .aresetn(aresetn),

    // R
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
    .m_axi_rvalid(m_axi_int.rvalid),

    // Mux
    .mux(mux_r)
);  

// AW
axi_stripe_a inst_axi_stripe_aw (
    .aclk(aclk),
    .aresetn(aresetn),
    
    // AR
    .s_axi_aaddr(s_axi_int.awaddr),
    .s_axi_aburst(s_axi_int.awburst),
    .s_axi_acache(s_axi_int.awcache),
    .s_axi_aid(s_axi_int.awid),
    .s_axi_alen(s_axi_int.awlen),
    .s_axi_alock(s_axi_int.awlock),
    .s_axi_aprot(s_axi_int.awprot),
    .s_axi_aqos(s_axi_int.awqos),
    .s_axi_aregion(s_axi_int.awregion),
    .s_axi_asize(s_axi_int.awsize),
    .s_axi_aready(s_axi_int.awready),
    .s_axi_avalid(s_axi_int.awvalid),

    .m_axi_aaddr(m_axi_int.awaddr),
    .m_axi_aburst(m_axi_int.awburst),
    .m_axi_acache(m_axi_int.awcache),
    .m_axi_aid(m_axi_int.awid),
    .m_axi_alen(m_axi_int.awlen),
    .m_axi_alock(m_axi_int.awlock),
    .m_axi_aprot(m_axi_int.awprot),
    .m_axi_aqos(m_axi_int.awqos),
    .m_axi_aregion(m_axi_int.awregion),
    .m_axi_asize(m_axi_int.awsize),
    .m_axi_aready(m_axi_int.awready),
    .m_axi_avalid(m_axi_int.awvalid),

    // Mux
    .mux(mux_b)
); 

// B
axi_stripe_b inst_axi_stripe_b (
    .aclk(aclk),
    .aresetn(aresetn),

    // B
    .s_axi_bid(s_axi_int.bid),
    .s_axi_bresp(s_axi_int.bresp),
    .s_axi_bready(s_axi_int.bready),
    .s_axi_bvalid(s_axi_int.bvalid),

    .m_axi_bid(m_axi_int.bid),
    .m_axi_bresp(m_axi_int.bresp),
    .m_axi_bready(m_axi_int.bready),
    .m_axi_bvalid(m_axi_int.bvalid),

    // Mux
    .mux(mux_b)
);  

// W
assign m_axi_int.wdata = s_axi_int.wdata;
assign m_axi_int.wstrb = s_axi_int.wstrb;
assign m_axi_int.wstrb = s_axi_int.wstrb;
assign m_axi_int.wvalid = s_axi_int.wvalid;
assign s_axi_int.wready = m_axi_int.wready;

`else

`AXI_ASSIGN(s_axi, m_axi)

`endif

endmodule