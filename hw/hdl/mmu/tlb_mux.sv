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
 * @brief   RR multiplex for the DMA requests.
 *
 * Round-robin multiplex for the requests stemming from the TLB FSMs according to the dest 
 * The output requests are forwarded to the corresponding DMA engines.
 *
 *  @param DATA_BITS    Data bus size
 *  @param N_OUTPUT     Number of Output Channels
 */
module tlb_mux #(
    parameter integer                   N_OUTPUT = N_CARD_AXI,
    parameter integer                   DATA_BITS = AXI_DATA_BITS
) (
	input  logic    					aclk,    
	input  logic    					aresetn,

	// User logic
    dmaIntf.s                           s_req ,
    dmaIntf.m                           m_req [N_OUTPUT]
);

// Constants
localparam integer N_OUTPUT_BITS = $clog2(N_OUTPUT);

// Internal
logic ready_snk;
logic  valid_snk;
dma_req_t request_snk;
dma_rsp_t response_snk;

logic [N_OUTPUT-1:0] ready_src;
logic [N_OUTPUT-1:0] valid_src;
dma_req_t [N_OUTPUT-1:0] request_src;
dma_rsp_t [N_OUTPUT-1:0] response_src;


logic [N_OUTPUT_BITS-1:0] rr_reg;

logic [PID_BITS-1:0] done_pid [N_OUTPUT-1:0];
logic [DEST_BITS-1:0] done_dest [N_OUTPUT-1:0];
logic done_stream [N_OUTPUT-1:0];
logic done_host [N_OUTPUT-1:0];
logic done_vld [N_OUTPUT-1:0];
logic done_rdy [N_OUTPUT-1:0];


// --------------------------------------------------------------------------------
// IO
// --------------------------------------------------------------------------------
assign valid_snk = s_req.valid;
assign s_req.ready = ready_snk;
assign request_snk = s_req.req;    
assign s_req.rsp = response_snk;

for(genvar i = 0; i < N_OUTPUT; i++) begin
    assign m_req[i].valid = valid_src[i];
    assign ready_src[i] = m_req[i].ready;
    assign m_req[i].req = request_src[i];
    assign response_src[i] = m_req[i].rsp;
end


//---------------------------------------------------------------------------------
// Req
//---------------------------------------------------------------------------------

always_comb begin
    for(int i = 0; i < N_OUTPUT; i++) begin
        request_src[i] = request_snk;
        valid_src[i] = (i == request_snk.dest) ? valid_snk : 1'b0;
    end
    ready_snk = ready_src[request_snk.dest];
end

// --------------------------------------------------------------------------------
// Rsp
// --------------------------------------------------------------------------------
always_ff @(posedge aclk) begin
	if(aresetn == 1'b0) begin
		rr_reg <= 0;
	end else begin
        rr_reg <= rr_reg + 1;
        if(rr_reg == N_OUTPUT-1)
            rr_reg <= 0;
	end
end

for(genvar i = 0; i < N_OUTPUT; i++) begin
    queue_stream #(
        .QTYPE(logic [PID_BITS+DEST_BITS+1-1:0]),
        .QDEPTH(N_OUTSTANDING*N_OUTPUT)
    ) inst_seq_que_done (
        .aclk(aclk),
        .aresetn(aresetn),
        .val_snk(response_src[i].done),
        .rdy_snk(),
        .data_snk({response_src[i].host, response_src[i].stream,response_src[i].dest,response_src[i].pid}),
        .val_src(done_vld[i]),
        .rdy_src(done_rdy[i]),
        .data_src({done_host[i], done_stream[i], done_dest[i], done_pid[i]})
    );

    assign done_rdy[i] = (i == rr_reg) ? 1'b1 : 1'b0;
end

always_comb begin
    response_snk.done = done_vld[rr_reg];
    response_snk.pid = done_pid[rr_reg];
    response_snk.stream = done_stream[rr_reg];
    response_snk.dest = done_dest[rr_reg];
    response_snk.host = done_host[rr_reg];
end


/////////////////////////////////////////////////////////////////////////////
// DEBUG
/////////////////////////////////////////////////////////////////////////////
`ifdef DBG_TLB_MUX

`endif

endmodule