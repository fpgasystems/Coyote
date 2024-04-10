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

module dest_dreq_mux #(
    parameter integer                   N_DESTS = 1
) (
    // HOST 
    metaIntf.s                          s_req,

    metaIntf.m                          m_req [N_DESTS],

    input  logic    					aclk,    
	input  logic    					aresetn
);

logic [N_DESTS-1:0] req_valid;
logic [N_DESTS-1:0] req_ready;
dreq_t [N_DESTS-1:0] req_data;

metaIntf #(.STYPE(dreq_t)) req_int [N_DESTS] ();

// I/O
for(genvar i = 0; i < N_DESTS; i++) begin
    assign req_int[i].valid = req_valid[i];
    assign req_ready[i] = req_int[i].ready;
    assign req_int[i].data = req_data[i];
end

// DP
always_comb begin
    for(int i = 0; i < N_DESTS; i++) begin
        req_valid[i] = ((s_req.data.req_1.actv ? s_req.data.req_1.dest : s_req.data.req_2.dest) == i) ? s_req.valid : 1'b0;
        req_data[i] = s_req.data;
    end

    s_req.ready = req_ready[(s_req.data.req_1.actv ? s_req.data.req_1.dest : s_req.data.req_2.dest)];
end

// REG
for(genvar i = 0; i < N_DESTS; i++) begin
    meta_reg #(.DATA_BITS($bits(dreq_t))) inst_reg  (.aclk(aclk), .aresetn(aresetn), .s_meta(req_int[i]), .m_meta(m_req[i]));
end
    
endmodule