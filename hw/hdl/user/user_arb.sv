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

module user_arbiter #(
    parameter integer                   N_CPID = 2
) (
	input  logic    					aclk,    
	input  logic    					aresetn,

	// User logic
    metaIntf.s                          s_meta [N_CPID],
    metaIntf.m                          m_meta,

    // Multiplexing
    metaIntf.s                          mux
);

// Constants
localparam integer BEAT_LOG_BITS = $clog2(DATA_BITS/8);
localparam integer BLEN_BITS = LEN_BITS - BEAT_LOG_BITS;
localparam integer N_CPID_BITS = $clog2(N_CPID);

// Internal
logic [N_CPID-1:0] ready_snk;
logic [N_CPID-1:0] valid_snk;
req_t [N_CPID-1:0] data_snk;

logic ready_src;
logic valid_src;
req_t data_src;

logic [N_CPID_BITS-1:0] rr_reg;
logic [N_CPID_BITS-1:0] id;

metaIntf #(.STYPE(logic[N_CPID_BITS+BLEN_BITS-1:0])) user_seq_in ();
logic [BLEN_BITS-1:0] n_tr;

// --------------------------------------------------------------------------------
// IO
// --------------------------------------------------------------------------------
for(genvar i = 0; i < N_CPID; i++) begin
    assign valid_snk[i] = s_meta[i].valid;
    assign s_meta[i].ready = ready_snk[i];
    assign data_snk[i] = s_meta[i].data;    
end

assign m_meta.valid = valid_src;
assign ready_src = m_meta.ready;
assign m_meta.data = data_src;

// --------------------------------------------------------------------------------
// RR
// --------------------------------------------------------------------------------
always_ff @(posedge aclk) begin
	if(aresetn == 1'b0) begin
		rr_reg <= 0;
	end else begin
        if(valid_src & ready_src) begin 
            rr_reg <= rr_reg + 1;
            if(rr_reg >= N_CPID-1)
                rr_reg <= 0;
        end
	end
end

// DP
always_comb begin
    ready_snk = 0;
    valid_src = 1'b0;
    id = 0;

    for(int i = 0; i < N_CPID; i++) begin
        if(i+rr_reg >= N_CPID) begin
            if(valid_snk[i+rr_reg-N_CPID]) begin
                valid_src = valid_snk[i+rr_reg-N_CPID] && user_seq_in.ready;
                id = i+rr_reg-N_CPID;
                break;
            end
        end
        else begin
            if(valid_snk[i+rr_reg]) begin
                valid_src = valid_snk[i+rr_reg] && user_seq_in.ready;
                id = i+rr_reg;
                break;
            end
        end
    end

    ready_snk[id] = ready_src && user_seq_in.ready;
    data_src = data_snk[id];
end

assign user_seq_in.valid = valid_src & ready_src;
assign n_tr = (data_snk[i].len - 1) >> BEAT_LOG_BITS;
assign user_seq_in.data = {id, n_tr};

// Multiplexer sequence
queue_meta #(
    .QDEPTH(N_OUTSTANDING)
) inst_seq_que_user (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_meta(user_seq_in),
    .m_meta(mux)
);


endmodule