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

`timescale 1 ps / 1 ps

import eci_cmd_defs::*;
import block_types::*;

import lynxTypes::*;

module eci_reorder_rd_2vc #( 
    parameter integer                           N_THREADS = 32, // x2
    parameter integer                           N_BURSTED = 2
) (
    input  logic                                aclk,
    input  logic                                aresetn,

    // Input
    input  logic [ECI_ADDR_BITS-1:0]            axi_in_araddr,
    input  logic [7:0]                          axi_in_arlen,
    input  logic                                axi_in_arvalid,
    output logic                                axi_in_arready,
    
    output logic  [ECI_DATA_BITS-1:0]           axi_in_rdata,
    output logic  [ECI_ID_BITS-1:0]             axi_in_rid,
    output logic                                axi_in_rlast,
    output logic  [1:0]                         axi_in_rresp,
    output logic                                axi_in_rvalid,
    input  logic                                axi_in_rready,

    // Output
    output logic [1:0][ECI_ADDR_BITS-1:0]       axi_out_araddr,
    output logic [1:0][ECI_ID_BITS-1:0]         axi_out_arid,
    output logic [1:0][7:0]                     axi_out_arlen,
    output logic [1:0]                          axi_out_arvalid,
    input  logic [1:0]                          axi_out_arready,
    
    input  logic [1:0][ECI_DATA_BITS-1:0]       axi_out_rdata,
    input  logic [1:0][ECI_ID_BITS-1:0]         axi_out_rid,
    input  logic [1:0]                          axi_out_rvalid,
    output logic [1:0]                          axi_out_rready
);

// ----------------------------------------------------------------------

//
// Splitter
//
logic [1:0][ECI_ADDR_BITS-1:0] axi_araddr_s0;
logic [1:0][7:0] axi_arlen_s0;
logic [1:0] axi_arvalid_s0;
logic [1:0] axi_arready_s0;

metaIntf #(.STYPE(logic[8+1-1:0])) mux_r ();

reorder_splitter_rd inst_reorder_splitter_rd (
    .aclk(aclk),
    .aresetn(aresetn),

    .axi_in_araddr(axi_in_araddr),
    .axi_in_arlen(axi_in_arlen),
    .axi_in_arvalid(axi_in_arvalid),
    .axi_in_arready(axi_in_arready),

    .axi_out_araddr(axi_araddr_s0),
    .axi_out_arlen(axi_arlen_s0),
    .axi_out_arvalid(axi_arvalid_s0),
    .axi_out_arready(axi_arready_s0),

    .mux_r(mux_r)
);

//
// Reorder buffers
//
logic [1:0][ECI_DATA_BITS-1:0] axi_rdata_s1;
logic [1:0] axi_rvalid_s1;
logic [1:0] axi_rready_s1;

for(genvar i = 0; i < 2; i++) begin
    reorder_buffer_rd #(
        .N_THREADS(N_THREADS),
        .N_BURSTED(N_BURSTED)
    ) inst_reorder_rd (
        .aclk(aclk),
        .aresetn(aresetn),

        .axi_in_araddr(axi_araddr_s0[i]),
        .axi_in_arlen(axi_arlen_s0[i]),
        .axi_in_arvalid(axi_arvalid_s0[i]),
        .axi_in_arready(axi_arready_s0[i]),

        .axi_in_rdata(axi_rdata_s1[i]),
        .axi_in_rvalid(axi_rvalid_s1[i]),
        .axi_in_rready(axi_rready_s1[i]),

        .axi_out_araddr(axi_out_araddr[i]),
        .axi_out_arid(axi_out_arid[i]),
        .axi_out_arlen(axi_out_arlen[i]),
        .axi_out_arvalid(axi_out_arvalid[i]),
        .axi_out_arready(axi_out_arready[i]),

        .axi_out_rdata(axi_out_rdata[i]),
        .axi_out_rid(axi_out_rid[i]),
        .axi_out_rvalid(axi_out_rvalid[i]),
        .axi_out_rready(axi_out_rready[i])
    );
end

// Queueing
logic [1:0][ECI_DATA_BITS-1:0] axi_rdata_s0;
logic [1:0] axi_rvalid_s0;
logic [1:0] axi_rready_s0;

for(genvar i = 0; i < 2; i++) begin
    axis_reg_array_r #(
        .N_STAGES(2)
    ) inst_reg_r (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(axi_rvalid_s1[i]),
        .s_axis_tready(axi_rready_s1[i]),
        .s_axis_tdata(axi_rdata_s1[i]),
        .m_axis_tvalid(axi_rvalid_s0[i]),
        .m_axis_tready(axi_rready_s0[i]),
        .m_axis_tdata(axi_rdata_s0[i])
    );
end

//
// Mux
//
reorder_mux_r inst_reorder_mux_r (
    .aclk(aclk),
    .aresetn(aresetn),

    .axi_out_rdata(axi_rdata_s0),
    .axi_out_rvalid(axi_rvalid_s0),
    .axi_out_rready(axi_rready_s0),

    .axi_in_rdata(axi_in_rdata),
    .axi_in_rid(axi_in_rid),
    .axi_in_rlast(axi_in_rlast),
    .axi_in_rresp(axi_in_rresp),
    .axi_in_rready(axi_in_rready),
    .axi_in_rvalid(axi_in_rvalid),

    .mux_r(mux_r)
);

endmodule
