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
 * @brief   RR arbitration for the ISR DMA requests
 *
 * Round-robin arbitration for the ISR requests stemming from the TLB FSMs. 
 * The output generates two requests, one for the XDMA engine and 
 * one for the available corresponding CDMA engines.
 *
 *  @param RDWR     Read or write requests (Mutex lock)
 */
module tlb_arbiter_isr #(
    parameter integer                   RDWR = 0
) (
	input  logic    					aclk,    
	input  logic    					aresetn,

	// User logic
    dmaIsrIntf.s                        s_req [N_REGIONS],
    dmaIntf.m                           m_req_host,
    dmaIntf.m                           m_req_card
);

// Internal
logic [N_REGIONS-1:0] ready_snk;
logic [N_REGIONS-1:0] valid_snk;
dma_isr_req_t [N_REGIONS-1:0] request_snk;
dma_isr_rsp_t [N_REGIONS-1:0] response_snk;

logic ready_src;
logic valid_src;
dma_isr_req_t request_src;
logic done_src;

logic [N_REGIONS_BITS-1:0] rr_reg;
logic [N_REGIONS_BITS-1:0] vfid;
logic [PID_BITS-1:0] pid;
logic [DEST_BITS-1:0] dest;
logic stream;
logic host;

metaIntf #(.STYPE(logic[N_REGIONS_BITS+PID_BITS+DEST_BITS+1+1-1:0])) done_seq_in ();
logic [N_REGIONS_BITS-1:0] done_vfid;
logic [PID_BITS-1:0] done_pid;
logic [DEST_BITS-1:0] done_dest;
logic done_stream;
logic done_host;

// --------------------------------------------------------------------------------
// IO
// --------------------------------------------------------------------------------

// Sink
for(genvar i = 0; i < N_REGIONS; i++) begin
    assign valid_snk[i] = s_req[i].valid;
    assign s_req[i].ready = ready_snk[i];
    assign request_snk[i] = s_req[i].req;    
    assign s_req[i].rsp = response_snk[i];
end

// Source
assign m_req_host.valid = ready_src & valid_src;
assign m_req_card.valid = ready_src & valid_src;
assign m_req_host.req.paddr = request_src.paddr_host;
assign m_req_card.req.paddr = request_src.paddr_card;
assign m_req_host.req.len = request_src.len;
assign m_req_card.req.len = request_src.len;
assign m_req_host.req.ctl = request_src.ctl;
assign m_req_card.req.ctl = request_src.ctl;
assign m_req_host.req.rsrvd = 0;
assign m_req_card.req.rsrvd = 0;

assign ready_src = m_req_host.ready & m_req_card.ready;
if(RDWR == 0) begin
    assign done_src = m_req_card.rsp.done;
end
else begin
    assign done_src = m_req_host.rsp.done;
end

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
    pid = 0;
    dest = 0;
    stream = 0;
    host = 0;

    response_snk = 0;

    for(int i = 0; i < N_REGIONS; i++) begin
        if(i+rr_reg >= N_REGIONS) begin
            if(valid_snk[i+rr_reg-N_REGIONS]) begin
                valid_src = valid_snk[i+rr_reg-N_REGIONS] && done_seq_in.ready;
                vfid = i+rr_reg-N_REGIONS;
                break;
            end
        end
        else begin
            if(valid_snk[i+rr_reg]) begin
                valid_src = valid_snk[i+rr_reg] && done_seq_in.ready;
                vfid = i+rr_reg;
                break;
            end
        end
    end

    ready_snk[vfid] = ready_src && done_seq_in.ready;
    request_src = request_snk[vfid];
    pid = request_snk[vfid].pid;
    stream = request_snk[vfid].stream;
    dest = request_snk[vfid].dest;
    host = request_snk[vfid].host;

    response_snk[done_vfid].done = done_src;
    response_snk[done_vfid].pid = done_pid;
    response_snk[done_vfid].stream = done_stream;
    response_snk[done_vfid].dest = done_dest;
    response_snk[done_vfid].host = done_host;
end

assign done_seq_in.valid = valid_src & ready_src & request_src.ctl;
assign done_seq_in.data = {host, stream, dest, vfid, pid};

// Completion sequence
queue #(
    .QTYPE(logic [N_REGIONS_BITS+PID_BITS+DEST_BITS+1+1-1:0]),
    .QDEPTH(N_OUTSTANDING)
) inst_seq_que_done (
    .aclk(aclk),
    .aresetn(aresetn),
    .val_snk(done_seq_in.valid),
    .rdy_snk(done_seq_in.ready),
    .data_snk(done_seq_in.data),
    .val_src(done_src),
    .rdy_src(),
    .data_src({done_host, done_stream, done_dest, done_vfid, done_pid})
);

/////////////////////////////////////////////////////////////////////////////
// DEBUG
/////////////////////////////////////////////////////////////////////////////
`ifdef DBG_TLB_ARBITER_ISR

`endif

endmodule