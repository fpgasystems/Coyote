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

`include "lynx_macros.svh"

/**
 *	ECi request arbiter - Round Robin
 */ 
module eci_arbiter #(
    parameter integer                   ARB_DATA_BITS = ECI_DATA_BITS
) (
	input  logic    					aclk,    
	input  logic    					aresetn,

	// User logic
    dmaIntf.s                           req_snk [N_CHAN],
    dmaIntf.m                           req_src,

    // Multiplexing
    muxIntf.s                           mux_user
);

// Constants
localparam integer BEAT_LOG_BITS = $clog2(ARB_DATA_BITS/8);
localparam integer BLEN_BITS = LEN_BITS - BEAT_LOG_BITS;

// Internal
logic [N_CHAN-1:0] ready_snk;
logic [N_CHAN-1:0] valid_snk;
dma_req_t [N_CHAN-1:0] request_snk;
dma_rsp_t [N_CHAN-1:0] response_snk;

logic ready_src;
logic valid_src;
dma_req_t request_src;
logic done_src;

logic [N_CHAN_BITS-1:0] rr_reg;
logic [N_CHAN_BITS-1:0] vfid;

metaIntf #(.STYPE(logic[1+N_CHAN_BITS+BLEN_BITS-1:0])) user_seq_in ();
metaIntf #(.STYPE(logic[N_CHAN_BITS-1:0])) done_seq_in ();
logic [N_CHAN_BITS-1:0] done_vfid;

logic [BLEN_BITS-1:0] n_tr;

// --------------------------------------------------------------------------------
// IO
// --------------------------------------------------------------------------------
for(genvar i = 0; i < N_CHAN; i++) begin
    assign valid_snk[i] = req_snk[i].valid;
    assign req_snk[i].ready = ready_snk[i];
    assign request_snk[i] = req_snk[i].req;   
    assign req_snk[i].rsp = response_snk[i]; 
end

assign req_src.valid = valid_src;
assign ready_src = req_src.ready;
assign req_src.req = request_src;
assign done_src = req_src.rsp.done;

// --------------------------------------------------------------------------------
// RR
// --------------------------------------------------------------------------------
always_ff @(posedge aclk) begin
	if(aresetn == 1'b0) begin
		rr_reg <= 0;
	end else begin
        if(valid_src & ready_src) begin 
            rr_reg <= rr_reg + 1;
            if(rr_reg >= N_CHAN-1)
                rr_reg <= 0;
        end
	end
end

// DP
always_comb begin
    ready_snk = 0;
    valid_src = 1'b0;
    vfid = 0;

    response_snk = 0;

    for(int i = 0; i < N_CHAN; i++) begin
        if(i+rr_reg >= N_CHAN) begin
            if(valid_snk[i+rr_reg-N_CHAN]) begin
                valid_src = valid_snk[i+rr_reg-N_CHAN] && user_seq_in.ready && done_seq_in.ready;
                vfid = i+rr_reg-N_CHAN;
                break;
            end
        end
        else begin
            if(valid_snk[i+rr_reg]) begin
                valid_src = valid_snk[i+rr_reg] && user_seq_in.ready && done_seq_in.ready;
                vfid = i+rr_reg;
                break;
            end
        end
    end

    ready_snk[vfid] = ready_src && user_seq_in.ready && done_seq_in.ready;
    request_src = request_snk[vfid];

    response_snk[done_vfid].done = done_src;
end

assign n_tr = (request_snk[vfid].len - 1) >> BEAT_LOG_BITS;
assign user_seq_in.valid = valid_src & ready_src;
assign user_seq_in.data = {request_snk[vfid].ctl, vfid, n_tr};

assign done_seq_in.valid = valid_src & ready_src & request_src.ctl;
assign done_seq_in.data = vfid;

// Multiplexer sequence
queue #(
    .QTYPE(logic [1+N_CHAN_BITS+BLEN_BITS-1:0]),
    .QDEPTH(N_OUTSTANDING)
) inst_seq_que_user (
    .aclk(aclk),
    .aresetn(aresetn),
    .val_snk(user_seq_in.valid),
    .rdy_snk(user_seq_in.ready),
    .data_snk(user_seq_in.data),
    .val_src(mux_user.valid),
    .rdy_src(mux_user.ready),
    .data_src({mux_user.ctl, mux_user.vfid, mux_user.len})
);

// Completion sequence
queue #(
    .QTYPE(logic [N_CHAN_BITS-1:0]),
    .QDEPTH(N_OUTSTANDING)
) inst_seq_que_done (
    .aclk(aclk),
    .aresetn(aresetn),
    .val_snk(done_seq_in.valid),
    .rdy_snk(done_seq_in.ready),
    .data_snk(done_seq_in.data),
    .val_src(done_src),
    .rdy_src(),
    .data_src(done_vfid)
);

endmodule