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