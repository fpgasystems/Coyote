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
metaIntf #(.STYPE(mux_user_t)) user_seq_in ();
metaIntf #(.STYPE(req_t)) m_req_int ();

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