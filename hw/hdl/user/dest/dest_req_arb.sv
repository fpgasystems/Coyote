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
module dest_req_arb #(
    parameter integer                   DATA_BITS = AXI_DATA_BITS,
    parameter integer                   N_DESTS = 1
) (
	input  logic    					aclk,    
	input  logic    					aresetn,

	// User logic
    metaIntf.s                          s_req [N_DESTS],
    metaIntf.m                          m_req,

    // Multiplexing
    metaIntf.m                          mux
);

// Constants
localparam integer N_DESTS_BITS = clog2s(N_DESTS);

// Internal
logic [N_DESTS-1:0] ready_snk;
logic [N_DESTS-1:0] valid_snk;
req_t [N_DESTS-1:0] request_snk;

logic ready_src;
logic valid_src;
req_t request_src;

logic [N_DESTS_BITS-1:0] dest;

logic [N_DESTS_BITS-1:0] rr_reg;
logic [BLEN_BITS-1:0] n_tr;

metaIntf #(.STYPE(mux_user_t)) user_seq_in ();
metaIntf #(.STYPE(req_t)) m_req_int ();

// --------------------------------------------------------------------------------
// IO
// --------------------------------------------------------------------------------
for(genvar i = 0; i < N_DESTS; i++) begin
    assign valid_snk[i] = s_req[i].valid;
    assign s_req[i].ready = ready_snk[i];
    assign request_snk[i] = s_req[i].data;
end

assign m_req_int.valid = valid_src;
assign ready_src = m_req_int.ready;
assign m_req_int.data = request_src;

// --------------------------------------------------------------------------------
// RR
// --------------------------------------------------------------------------------
always_ff @(posedge aclk) begin
	if(aresetn == 1'b0) begin
		rr_reg <= 0;
	end else begin
        if(valid_src & ready_src) begin 
            rr_reg <= rr_reg + 1;
            if(rr_reg >= N_DESTS-1)
                rr_reg <= 0;
        end
	end
end

// DP
always_comb begin
    ready_snk = 0;
    valid_src = 1'b0;
    dest = 0;

    for(int i = 0; i < N_DESTS; i++) begin
        if(i+rr_reg >= N_DESTS) begin
            if(valid_snk[i+rr_reg-N_DESTS]) begin
                valid_src = valid_snk[i+rr_reg-N_DESTS] && user_seq_in.ready;
                dest = i+rr_reg-N_DESTS;
                break;
            end
        end
        else begin
            if(valid_snk[i+rr_reg]) begin
                valid_src = valid_snk[i+rr_reg] && user_seq_in.ready;
                dest = i+rr_reg;
                break;
            end
        end
    end

    ready_snk[dest] = ready_src;
    request_src = request_snk[dest];
end

assign n_tr = (request_snk[dest].len - 1) >> BEAT_LOG_BITS;
assign user_seq_in.valid = valid_src & ready_src;
assign user_seq_in.data.pid = request_snk[dest].pid;
assign user_seq_in.data.len = n_tr;
assign user_seq_in.data.dest = dest;

// Multiplexer sequence
queue_stream #(
    .QTYPE(mux_user_t),
    .QDEPTH(N_OUTSTANDING_REGION)
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