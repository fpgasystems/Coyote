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

module eci_arbiter_top (
    input  logic            aclk,
    input  logic            aresetn,
    
    // RD
    dmaIntf.s               req_rd_snk [N_CHAN],
    dmaIntf.m               req_rd_src,
    AXI4S.s                 axis_rd_data_snk,
    AXI4S.m                 axis_rd_data_src [N_CHAN],

    // WR
    dmaIntf.s               req_wr_snk [N_CHAN],
    dmaIntf.m               req_wr_src,
    AXI4S.s                 axis_wr_data_snk [N_CHAN],
    AXI4S.m                 axis_wr_data_src 
);

muxIntf #(.N_ID_BITS(N_CHAN_BITS), .ARB_DATA_BITS(ECI_DATA_BITS)) mux_rd ();
muxIntf #(.N_ID_BITS(N_CHAN_BITS), .ARB_DATA_BITS(ECI_DATA_BITS)) mux_wr ();

// RD arbiter
eci_arbiter inst_rd_arb (
    .aclk(aclk),
    .aresetn(aresetn),
    .req_snk(req_rd_snk),
    .req_src(req_rd_src),
    .mux_user(mux_rd)
);

// RD mux
axis_mux_eci_src inst_rd_mux (
    .aclk(aclk),
    .aresetn(aresetn),
    .mux_user(mux_rd),
    .axis_in(axis_rd_data_snk),
    .axis_out(axis_rd_data_src)
);  

// WR arbiter
eci_arbiter inst_wr_arb (
    .aclk(aclk),
    .aresetn(aresetn),
    .req_snk(req_wr_snk),
    .req_src(req_wr_src),
    .mux_user(mux_wr)
);

// WR mux
axis_mux_eci_sink inst_wr_mux (
    .aclk(aclk),
    .aresetn(aresetn),
    .mux_user(mux_wr),
    .axis_in(axis_wr_data_snk),
    .axis_out(axis_wr_data_src)
);  
    
endmodule