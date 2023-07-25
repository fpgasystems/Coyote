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
 * @brief   Propagate DMA requests with backpressuring queue for 
 * outstanding requests.
 *
 * Provides a backpressuring mechanism for the requests.
 */
module tlb_assign (
	input  logic    					aclk,    
	input  logic    					aresetn,

	// User logic
    dmaIntf.s                           s_req,
    dmaIntf.m                           m_req
);

// Internal
metaIntf #(.STYPE(logic[PID_BITS+DEST_BITS+1-1:0])) done_seq_in ();
logic [PID_BITS-1:0] done_pid;
logic [DEST_BITS-1:0] done_dest;
logic done_stream;
logic done_host;

// Assign
always_comb begin
    s_req.ready = m_req.ready & done_seq_in.ready;
    m_req.valid = s_req.valid & s_req.ready;
    
    m_req.req = s_req.req;
    
    s_req.rsp.done = m_req.rsp.done;
    s_req.rsp.pid = done_pid;
    s_req.rsp.dest = done_dest;
    s_req.rsp.stream = done_stream;
    s_req.rsp.host = done_host;
end

assign done_seq_in.valid = m_req.valid & m_req.ready & m_req.req.ctl;
assign done_seq_in.data = {m_req.req.host, m_req.req.stream, m_req.req.dest, m_req.req.pid};

// Completion sequence
queue #(
    .QTYPE(logic [PID_BITS+DEST_BITS+1-1:0]),
    .QDEPTH(N_OUTSTANDING)
) inst_seq_que_done (
    .aclk(aclk),
    .aresetn(aresetn),
    .val_snk(done_seq_in.valid),
    .rdy_snk(done_seq_in.ready),
    .data_snk(done_seq_in.data),
    .val_src(m_req.rsp.done),
    .rdy_src(),
    .data_src({done_host, done_stream, done_dest, done_pid})
); 

/////////////////////////////////////////////////////////////////////////////
// DEBUG
/////////////////////////////////////////////////////////////////////////////
`ifdef DBG_TLB_ASSIGN

`endif

endmodule