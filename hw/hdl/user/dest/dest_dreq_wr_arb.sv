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
 * @brief   RR arbitration (dreq_t)
 *
 */
module dest_dreq_wr_arb #(
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
dreq_t [N_DESTS-1:0] request_snk;

logic ready_src;
logic valid_src;
dreq_t request_src;

logic [N_DESTS_BITS-1:0] dest;

logic [N_DESTS_BITS-1:0] rr_reg;
logic [BLEN_BITS-1:0] n_tr;

metaIntf #(.STYPE(mux_user_t)) user_seq_in (.*);
metaIntf #(.STYPE(dreq_t)) m_req_int (.*);

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
                valid_src = valid_snk[i+rr_reg-N_DESTS];
                dest = i+rr_reg-N_DESTS;
                break;
            end
        end
        else begin
            if(valid_snk[i+rr_reg]) begin
                valid_src = valid_snk[i+rr_reg];
                dest = i+rr_reg;
                break;
            end
        end
    end

    ready_snk[dest] = ready_src;
    request_src = request_snk[dest];
end

assign n_tr = (request_snk[dest].req_1.len - 1) >> BEAT_LOG_BITS;
assign user_seq_in.valid = valid_src & ready_src;
assign user_seq_in.data.pid = request_snk[dest].req_1.pid;
assign user_seq_in.data.len = n_tr;
assign user_seq_in.data.dest = dest;

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

meta_reg #(.DATA_BITS($bits(dreq_t))) inst_src_reg (.aclk(aclk), .aresetn(aresetn), .s_meta(m_req_int), .m_meta(m_req));

endmodule