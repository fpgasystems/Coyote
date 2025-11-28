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
 * @brief   RR arbitration for the ISR DMA requests
 *
 * Round-robin arbitration for the ISR requests stemming from the TLB FSMs. 
 * The output generates two requests, one for the XDMA engine and 
 * one for the available corresponding CDMA engines.
 *
 *  @param RDWR     Read or write requests (Mutex lock)
 */
module mmu_arbiter_isr #(
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

metaIntf #(.STYPE(logic[N_REGIONS_BITS-1:0])) done_seq_in (.*);
logic [N_REGIONS_BITS-1:0] done_vfid;

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
assign m_req_host.req.last = request_src.last;
assign m_req_card.req.last = request_src.last;
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

    response_snk[done_vfid].done = done_src;
end

assign done_seq_in.valid = valid_src & ready_src & request_src.last;
assign done_seq_in.data = vfid;

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
`ifdef DBG_TLB_ARBITER_ISR

`endif

endmodule