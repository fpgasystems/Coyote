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
import block_types::*;

import lynxTypes::*;

module eci_reorder_wr_2vc #( 
    parameter integer                           N_THREADS = 32, // x2
    parameter integer                           N_BURSTED = 2
) (
    input  logic                                aclk,
    input  logic                                aresetn,

    // Input
    input  logic [ECI_ADDR_BITS-1:0]            axi_in_awaddr,
    input  logic [7:0]                          axi_in_awlen,
    input  logic                                axi_in_awvalid,
    output logic                                axi_in_awready,
    
    output logic  [ECI_ID_BITS-1:0]             axi_in_bid,
    output logic  [1:0]                         axi_in_bresp,
    output logic                                axi_in_bvalid,
    input  logic                                axi_in_bready,

    input  logic [ECI_DATA_BITS-1:0]            axi_in_wdata,
    input  logic [ECI_DATA_BITS/8-1:0]          axi_in_wstrb,
    input  logic                                axi_in_wlast,
    input  logic                                axi_in_wvalid,
    output logic                                axi_in_wready,

    // Output
    output logic [1:0][ECI_ADDR_BITS-1:0]       axi_out_awaddr,
    output logic [1:0][ECI_ID_BITS-1:0]         axi_out_awid,
    output logic [1:0][7:0]                     axi_out_awlen,
    output logic [1:0]                          axi_out_awvalid,
    input  logic [1:0]                          axi_out_awready,
    
    input  logic [1:0][ECI_ID_BITS-1:0]         axi_out_bid,
    input  logic [1:0][1:0]                     axi_out_bresp,
    input  logic [1:0]                          axi_out_bvalid,
    output logic [1:0]                          axi_out_bready,

    output logic [1:0][ECI_DATA_BITS-1:0]       axi_out_wdata,
    output logic [1:0][ECI_DATA_BITS/8-1:0]     axi_out_wstrb,
    output logic [1:0]                          axi_out_wlast,
    output logic [1:0]                          axi_out_wvalid,
    input  logic [1:0]                          axi_out_wready
);

// ----------------------------------------------------------------------

//
// Splitter
//
logic [1:0][ECI_ADDR_BITS-1:0] axi_awaddr_s0;
logic [1:0][7:0] axi_awlen_s0;
logic [1:0] axi_awvalid_s0;
logic [1:0] axi_awready_s0;

metaIntf #(.STYPE(logic[8+1-1:0])) mux_b ();
metaIntf #(.STYPE(logic[8+1-1:0])) mux_w ();

reorder_splitter_wr inst_reorder_splitter_wr (
    .aclk(aclk),
    .aresetn(aresetn),

    .axi_in_awaddr(axi_in_awaddr),
    .axi_in_awlen(axi_in_awlen),
    .axi_in_awvalid(axi_in_awvalid),
    .axi_in_awready(axi_in_awready),

    .axi_out_awaddr(axi_awaddr_s0),
    .axi_out_awlen(axi_awlen_s0),
    .axi_out_awvalid(axi_awvalid_s0),
    .axi_out_awready(axi_awready_s0),

    .mux_b(mux_b),
    .mux_w(mux_w)
);

//
// Reorder buffers
//
logic [1:0][1:0] axi_bresp_s1;
logic [1:0] axi_bvalid_s1;
logic [1:0] axi_bready_s1;

for(genvar i = 0; i < 2; i++) begin
    reorder_buffer_wr #(
        .N_THREADS(N_THREADS),
        .N_BURSTED(N_BURSTED)
    ) inst_reorder_rd (
        .aclk(aclk),
        .aresetn(aresetn),

        .axi_in_awaddr(axi_awaddr_s0[i]),
        .axi_in_awlen(axi_awlen_s0[i]),
        .axi_in_awvalid(axi_awvalid_s0[i]),
        .axi_in_awready(axi_awready_s0[i]),

        .axi_in_bresp(axi_bresp_s1[i]),
        .axi_in_bvalid(axi_bvalid_s1[i]),
        .axi_in_bready(axi_bready_s1[i]),

        .axi_out_awaddr(axi_out_awaddr[i]),
        .axi_out_awid(axi_out_awid[i]),
        .axi_out_awlen(axi_out_awlen[i]),
        .axi_out_awvalid(axi_out_awvalid[i]),
        .axi_out_awready(axi_out_awready[i]),

        .axi_out_bresp(axi_out_bresp[i]),
        .axi_out_bid(axi_out_bid[i]),
        .axi_out_bvalid(axi_out_bvalid[i]),
        .axi_out_bready(axi_out_bready[i])
    );
end

// Queueing
logic [1:0][1:0] axi_bresp_s0;
logic [1:0] axi_bvalid_s0;
logic [1:0] axi_bready_s0;

for(genvar i = 0; i < 2; i++) begin
    axis_reg_array_b #(
        .N_STAGES(2)
    ) inst_reg_b (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(axi_bvalid_s1[i]),
        .s_axis_tready(axi_bready_s1[i]),
        .s_axis_tuser(axi_bresp_s1[i]),
        .m_axis_tvalid(axi_bvalid_s0[i]),
        .m_axis_tready(axi_bready_s0[i]),
        .m_axis_tuser(axi_bresp_s0[i])
    );
end

//
// Mux
//
reorder_mux_b inst_reorder_mux_b (
    .aclk(aclk),
    .aresetn(aresetn),

    .axi_out_bresp(axi_bresp_s0),
    .axi_out_bvalid(axi_bvalid_s0),
    .axi_out_bready(axi_bready_s0),

    .axi_in_bid(axi_in_bid),
    .axi_in_bresp(axi_in_bresp),
    .axi_in_bvalid(axi_in_bvalid),
    .axi_in_bready(axi_in_bready),

    .mux_b(mux_b)
);

logic [1:0][ECI_DATA_BITS-1:0] axi_wdata_s0;
logic [1:0][ECI_DATA_BITS/8-1:0] axi_wstrb_s0;
logic [1:0] axi_wlast_s0;
logic [1:0] axi_wvalid_s0;
logic [1:0] axi_wready_s0;

reorder_mux_w inst_reorder_mux_w (
    .aclk(aclk),
    .aresetn(aresetn),

    .axi_in_wdata(axi_in_wdata),
    .axi_in_wstrb(axi_in_wstrb),
    .axi_in_wlast(axi_in_wlast),
    .axi_in_wvalid(axi_in_wvalid),
    .axi_in_wready(axi_in_wready),

    .axi_out_wdata(axi_wdata_s0),
    .axi_out_wstrb(axi_wstrb_s0),
    .axi_out_wlast(axi_wlast_s0),
    .axi_out_wvalid(axi_wvalid_s0),
    .axi_out_wready(axi_wready_s0),

    .mux_w(mux_w)
);

for(genvar i = 0; i < 2; i++) begin
    axis_data_fifo_w_buff inst_queue_w (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(axi_wvalid_s0[i]),
        .s_axis_tready(axi_wready_s0[i]),
        .s_axis_tdata(axi_wdata_s0[i]),
        .s_axis_tstrb(axi_wstrb_s0[i]),
        .s_axis_tlast(axi_wlast_s0[i]),
        .m_axis_tvalid(axi_out_wvalid[i]),
        .m_axis_tready(axi_out_wready[i]),
        .m_axis_tdata(axi_out_wdata[i]),
        .m_axis_tstrb(axi_out_wstrb[i]),
        .m_axis_tlast(axi_out_wlast[i])
    );
end

endmodule
