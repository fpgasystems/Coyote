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
`include "lynx_macros.svh"

module shell_split_data #(
    parameter integer   N_SPLIT_CHAN = N_CHAN
) (
    AXI4S.s             s_axis_dyn_in,
    AXI4S.m             m_axis_dyn_in [N_SPLIT_CHAN],
    AXI4S.s             s_axis_dyn_out [N_SPLIT_CHAN],
    AXI4S.m             m_axis_dyn_out,
    dmaIntf.s           s_dma_rd_req [N_SPLIT_CHAN],
    dmaIntf.m           m_dma_rd_req,
    dmaIntf.s           s_dma_wr_req [N_SPLIT_CHAN],
    dmaIntf.m           m_dma_wr_req,

    input  logic        aclk,
    input  logic        aresetn
);

localparam integer N_SPLIT_CHAN_BITS = clog2s(N_SPLIT_CHAN);

metaIntf #(.STYPE(mux_shell_t)) mux_rd ();
metaIntf #(.STYPE(mux_shell_t)) mux_wr ();

// RD arbiter
dma_arbiter #(
  .N_SPLIT_CHAN(N_SPLIT_CHAN)
) inst_rd_arb (
  .aclk(aclk),
  .aresetn(aresetn),
  .req_snk(s_dma_rd_req),
  .req_src(m_dma_rd_req),
  .mux(mux_rd)
);

// WR arbiter
dma_arbiter #(
  .N_SPLIT_CHAN(N_SPLIT_CHAN)
) inst_wr_arb (
  .aclk(aclk),
  .aresetn(aresetn),
  .req_snk(s_dma_wr_req),
  .req_src(m_dma_wr_req),
  .mux(mux_wr)
);

// RD mux
axis_mux_dma_src #(
  .N_SPLIT_CHAN(N_SPLIT_CHAN)
) inst_rd_mux (
  .aclk(aclk),
  .aresetn(aresetn),
  .mux(mux_rd),
  .axis_in(s_axis_dyn_in),
  .axis_out(m_axis_dyn_in)
);

// WR mux
axis_mux_dma_sink #(
  .N_SPLIT_CHAN(N_SPLIT_CHAN)
) inst_wr_mux (
  .aclk(aclk),
  .aresetn(aresetn),
  .mux(mux_wr),
  .axis_in(s_axis_dyn_out),
  .axis_out(m_axis_dyn_out)
);
    
endmodule