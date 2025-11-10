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