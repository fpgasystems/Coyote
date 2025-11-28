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

module dest_req_mux #(
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
req_t [N_DESTS-1:0] req_data;

metaIntf #(.STYPE(req_t)) req_int [N_DESTS] (.*);

// I/O
for(genvar i = 0; i < N_DESTS; i++) begin
    assign req_int[i].valid = req_valid[i];
    assign req_ready[i] = req_int[i].ready;
    assign req_int[i].data = req_data[i];
end

// DP
always_comb begin
    for(int i = 0; i < N_DESTS; i++) begin
        req_valid[i] = (s_req.data.dest == i) ? s_req.valid : 1'b0;
        req_data[i] = s_req.data;
    end

    s_req.ready = req_ready[s_req.data.dest];
end

// REG
for(genvar i = 0; i < N_DESTS; i++) begin
    meta_reg #(.DATA_BITS($bits(req_t))) inst_reg  (.aclk(aclk), .aresetn(aresetn), .s_meta(req_int[i]), .m_meta(m_req[i]));
end
    
endmodule