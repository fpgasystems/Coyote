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

`timescale 1 ps / 1 ps

import eci_cmd_defs::*;

import lynxTypes::*;

module eci_reorder_top_2vc #(
    parameter integer           N_THREADS = 32,
    parameter integer           N_BURSTED = 2
) (
    input  logic                aclk,
    input  logic                aresetn,

    AXI4.s                      axi_in,
    AXI4.m                      axi_out [2]
);

//
// Rd reordering
//
logic [1:0][ECI_ADDR_BITS-1:0] axi_out_araddr;
logic [1:0][ECI_ID_BITS-1:0] axi_out_arid;
logic [1:0][7:0] axi_out_arlen;
logic [1:0] axi_out_arvalid;
logic [1:0] axi_out_arready;

logic [1:0][ECI_DATA_BITS-1:0] axi_out_rdata;
logic [1:0][ECI_ID_BITS-1:0] axi_out_rid;
logic [1:0] axi_out_rvalid;
logic [1:0] axi_out_rready;

for(genvar i = 0; i < 2; i++) begin
    assign axi_out[i].araddr        = axi_out_araddr[i];
    assign axi_out[i].arid          = axi_out_arid[i];
    assign axi_out[i].arlen         = axi_out_arlen[i];
    assign axi_out[i].arvalid       = axi_out_arvalid[i];
    assign axi_out_arready[i]       = axi_out[i].arready;

    assign axi_out_rdata[i]         = axi_out[i].rdata;
    assign axi_out_rid[i]           = axi_out[i].rid;
    assign axi_out_rvalid[i]        = axi_out[i].rvalid;
    assign axi_out[i].rready        = axi_out_rready[i];

    assign axi_out[i].arsize        = 3'b111;
    assign axi_out[i].arburst       = 2'b01;
    assign axi_out[i].arlock        = 1'b0;
    assign axi_out[i].arcache       = 4'b0011;
    assign axi_out[i].arprot        = 3'b010;
end

eci_reorder_rd_2vc #(
    .N_THREADS(N_THREADS),
    .N_BURSTED(N_BURSTED)
) inst_rd_reorder (
    .aclk(aclk),
    .aresetn(aresetn),
    
    // Input
    .axi_in_araddr(axi_in.araddr),
    .axi_in_arlen(axi_in.arlen),
    .axi_in_arvalid(axi_in.arvalid),  
    .axi_in_arready(axi_in.arready),
    
    .axi_in_rdata(axi_in.rdata),
    .axi_in_rid(axi_in.rid),
    .axi_in_rlast(axi_in.rlast),
    .axi_in_rresp(axi_in.rresp),
    .axi_in_rvalid(axi_in.rvalid),
    .axi_in_rready(axi_in.rready),
    
    // Output
    .axi_out_araddr(axi_out_araddr),
    .axi_out_arid(axi_out_arid),
    .axi_out_arlen(axi_out_arlen),
    .axi_out_arvalid(axi_out_arvalid),
    .axi_out_arready(axi_out_arready),

    .axi_out_rdata(axi_out_rdata),
    .axi_out_rid(axi_out_rid),
    .axi_out_rvalid(axi_out_rvalid),
    .axi_out_rready(axi_out_rready)
);

//
// Wr reordering
//
logic [1:0][ECI_ADDR_BITS-1:0] axi_out_awaddr;
logic [1:0][7:0] axi_out_awlen;
logic [1:0][4:0] axi_out_awid;
logic [1:0] axi_out_awvalid;
logic [1:0] axi_out_awready;

logic [1:0][ECI_DATA_BITS-1:0] axi_out_wdata;
logic [1:0][ECI_DATA_BITS/8-1:0] axi_out_wstrb;
logic [1:0] axi_out_wlast;
logic [1:0] axi_out_wvalid;
logic [1:0] axi_out_wready;

logic [1:0][ECI_ID_BITS-1:0] axi_out_bid;
logic [1:0][1:0] axi_out_bresp;
logic [1:0] axi_out_bvalid;
logic [1:0] axi_out_bready;


for(genvar i = 0; i < 2; i++) begin
    assign axi_out[i].awaddr        = axi_out_awaddr[i];
    assign axi_out[i].awlen         = axi_out_awlen[i];
    assign axi_out[i].awid          = axi_out_awid[i];
    assign axi_out[i].awvalid       = axi_out_awvalid[i];
    assign axi_out_awready[i]       = axi_out[i].awready;

    assign axi_out[i].wdata         = axi_out_wdata[i];
    assign axi_out[i].wstrb         = axi_out_wstrb[i];
    assign axi_out[i].wlast         = axi_out_wlast[i];
    assign axi_out[i].wvalid        = axi_out_wvalid[i];
    assign axi_out_wready[i]        = axi_out[i].wready;

    assign axi_out_bid[i]           = axi_out[i].bid;
    assign axi_out_bresp[i]         = axi_out[i].bresp;
    assign axi_out_bvalid[i]        = axi_out[i].bvalid;
    assign axi_out[i].bready        = axi_out_bready[i];

    assign axi_out[i].awsize        = 3'b111;
    assign axi_out[i].awburst       = 2'b01;
    assign axi_out[i].awlock        = 1'b0;
    assign axi_out[i].awcache       = 4'b0011;
    assign axi_out[i].awprot        = 3'b010;
end

eci_reorder_wr_2vc #(
    .N_THREADS(N_THREADS),
    .N_BURSTED(N_BURSTED)
) inst_wr_reorder (
    .aclk(aclk),
    .aresetn(aresetn),

    // Input
    .axi_in_awaddr(axi_in.awaddr),
    .axi_in_awlen(axi_in.awlen),
    .axi_in_awvalid(axi_in.awvalid),  
    .axi_in_awready(axi_in.awready),

    .axi_in_bid(axi_in.bid),
    .axi_in_bresp(axi_in.bresp),
    .axi_in_bvalid(axi_in.bvalid),
    .axi_in_bready(axi_in.bready),

    .axi_in_wdata(axi_in.wdata),
    .axi_in_wstrb(axi_in.wstrb),
    .axi_in_wlast(axi_in.wlast),
    .axi_in_wvalid(axi_in.wvalid),
    .axi_in_wready(axi_in.wready),

    // Output
    .axi_out_awaddr(axi_out_awaddr),
    .axi_out_awid(axi_out_awid),
    .axi_out_awlen(axi_out_awlen),
    .axi_out_awvalid(axi_out_awvalid),
    .axi_out_awready(axi_out_awready),

    .axi_out_bid(axi_out_bid),
    .axi_out_bresp(axi_out_bresp),
    .axi_out_bvalid(axi_out_bvalid),
    .axi_out_bready(axi_out_bready),

    .axi_out_wdata(axi_out_wdata),
    .axi_out_wstrb(axi_out_wstrb),
    .axi_out_wlast(axi_out_wlast),
    .axi_out_wvalid(axi_out_wvalid),
    .axi_out_wready(axi_out_wready)
);

endmodule
