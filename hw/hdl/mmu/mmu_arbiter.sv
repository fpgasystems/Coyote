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
 * @brief   RR arbitration for the DMA requests.
 *
 * Round-robin arbitration for the requests stemming from the TLB FSMs. 
 * The output requests are forwarded to the corresponding DMA engines.
 *
 *  @param DATA_BITS    Data bus size
 */
module mmu_arbiter #(
    parameter integer                   DATA_BITS = AXI_DATA_BITS
) (
	input  logic    					aclk,    
	input  logic    					aresetn,

	// User logic
    dmaIntf.s                           s_req [N_REGIONS],
    dmaIntf.m                           m_req,

    // Multiplexing
    metaIntf.m                          m_mux
);

// Constants
localparam integer BEAT_LOG_BITS = $clog2(DATA_BITS/8);
localparam integer BLEN_BITS = LEN_BITS - BEAT_LOG_BITS;

// Internal
logic [N_REGIONS-1:0] ready_snk;
logic [N_REGIONS-1:0] valid_snk;
dma_req_t [N_REGIONS-1:0] request_snk;
dma_rsp_t [N_REGIONS-1:0] response_snk;

logic ready_src;
logic valid_src;
dma_req_t request_src;
logic done_src;

logic [N_REGIONS_BITS-1:0] rr_reg;
logic [N_REGIONS_BITS-1:0] vfid;

metaIntf #(.STYPE(logic[1+N_REGIONS_BITS+BLEN_BITS-1:0])) user_seq_in ();
metaIntf #(.STYPE(logic[N_REGIONS_BITS-1:0])) done_seq_in ();
logic [N_REGIONS_BITS-1:0] done_vfid;

logic [BLEN_BITS-1:0] n_tr;

// --------------------------------------------------------------------------------
// IO
// --------------------------------------------------------------------------------
for(genvar i = 0; i < N_REGIONS; i++) begin
    assign valid_snk[i] = s_req[i].valid;
    assign s_req[i].ready = ready_snk[i];
    assign request_snk[i] = s_req[i].req;    
    assign s_req[i].rsp = response_snk[i];
end

assign m_req.valid = valid_src;
assign ready_src = m_req.ready;
always_comb begin
    m_req.req = request_src;
    m_req.req.last = 1'b1;
end
assign done_src = m_req.rsp.done;

// --------------------------------------------------------------------------------
// RR
// --------------------------------------------------------------------------------
always_ff @(posedge aclk) begin
	if(aresetn == 1'b0) begin
		rr_reg <= 0;
	end else begin
        if(valid_src & ready_src) begin 
            rr_reg <= rr_reg + 1;
            if(rr_reg >= N_REGIONS-1)
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

    for(int i = 0; i < N_REGIONS; i++) begin
        if(i+rr_reg >= N_REGIONS) begin
            if(valid_snk[i+rr_reg-N_REGIONS]) begin
                valid_src = valid_snk[i+rr_reg-N_REGIONS] && user_seq_in.ready && done_seq_in.ready;
                vfid = i+rr_reg-N_REGIONS;
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
assign user_seq_in.data = {request_snk[vfid].last, vfid, n_tr};

assign done_seq_in.valid = valid_src & ready_src;
assign done_seq_in.data = vfid;

// Multiplexer sequence
queue_stream #(
    .QTYPE(logic [1+N_REGIONS_BITS+BLEN_BITS-1:0]),
    .QDEPTH(N_OUTSTANDING)
) inst_seq_que_user (
    .aclk(aclk),
    .aresetn(aresetn),
    .val_snk(user_seq_in.valid),
    .rdy_snk(user_seq_in.ready),
    .data_snk(user_seq_in.data),
    .val_src(m_mux.valid),
    .rdy_src(m_mux.ready),
    .data_src({m_mux.data.last, m_mux.data.vfid, m_mux.data.len})
);

// Completion sequence
queue_stream #( 
    .QTYPE(logic [N_REGIONS_BITS-1:0]),
    .QDEPTH(N_OUTSTANDING)
) inst_seq_que_done (
    .aclk(aclk),
    .aresetn(aresetn),
    .val_snk(done_seq_in.valid),
    .rdy_snk(done_seq_in.ready),
    .data_snk(done_seq_in.data),
    .val_src(),
    .rdy_src(done_src),
    .data_src(done_vfid)
);

/////////////////////////////////////////////////////////////////////////////
// DEBUG
/////////////////////////////////////////////////////////////////////////////
//`define DBG_TLB_ARBITER
`ifdef DBG_TLB_ARBITER

ila_arbiter inst_ila_arbiter (
    .clk(aclk),
    .probe0(user_seq_in.valid),
    .probe1(user_seq_in.ready),
    .probe2(request_snk[vfid].last), 
    .probe3(vfid), // 2
    .probe4(m_mux.valid),
    .probe5(m_mux.ready),
    .probe6(done_seq_in.valid),
    .probe7(done_seq_in.ready),
    .probe8(done_seq_in.data), // 2
    .probe9(done_src),
    .probe10(done_vfid), // 2
    .probe11(s_req[0].valid),
    .probe12(s_req[0].ready),
    .probe13(s_req[0].rsp.done),
    .probe14(m_req.valid),
    .probe15(m_req.ready),
    .probe16(m_req.rsp.done)
);

`endif

endmodule