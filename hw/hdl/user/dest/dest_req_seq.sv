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

/**
 * @brief   RR arbitration (req_t)
 *
 */
module dest_req_seq #(
    parameter integer                   DATA_BITS = AXI_DATA_BITS,
    parameter integer                   N_DESTS = 1
) (
	input  logic    					aclk,    
	input  logic    					aresetn,

	// User logic
    metaIntf.s                          s_req,
    metaIntf.m                          m_req,

    // Multiplexing
    metaIntf.m                          mux
);

// Constants
localparam integer N_DESTS_BITS = clog2s(N_DESTS);

// Internal
metaIntf #(.STYPE(mux_user_t)) user_seq_in (.*);
metaIntf #(.STYPE(req_t)) m_req_int (.*);

logic [BLEN_BITS-1:0] n_tr;

// DP
always_comb begin
    s_req.ready = user_seq_in.ready & m_req_int.ready;
    
    n_tr = (s_req.data.len - 1) >> BEAT_LOG_BITS;
    user_seq_in.valid = s_req.ready ? s_req.valid : 1'b0;

    user_seq_in.data.pid = s_req.data.pid;
    user_seq_in.data.len = n_tr;
    user_seq_in.data.dest = s_req.data.dest;

    m_req_int.valid = user_seq_in.valid;
    m_req_int.data = s_req.data;
end

// Multiplexer sequence
queue_stream #(
    .QTYPE(mux_user_t),
    .QDEPTH(N_OUTSTANDING)
) inst_seq_que_user (
    .aclk(aclk),
    .aresetn(aresetn),
    .val_snk(user_seq_in.valid),
    .rdy_snk(user_seq_in.ready),
    .data_snk(user_seq_in.data),
    .val_src(mux.valid),
    .rdy_src(mux.ready),
    .data_src(mux.data)
);

meta_reg #(.DATA_BITS($bits(req_t))) inst_src_reg (.aclk(aclk), .aresetn(aresetn), .s_meta(m_req_int), .m_meta(m_req));

endmodule