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
 * @brief   TLB idma request arbitration between read and write channels
 *
 * Read and write channel sync.
 *
 *  @param RDWR     Read or write requests (Mutex lock)
 */
module tlb_idma_arb #(
    parameter integer RDWR = 0
) (
	input  logic    					aclk,    
	input  logic    					aresetn,

    input  logic                        mutex,

    dmaIsrIntf.s                        s_rd_IDMA,
    dmaIsrIntf.s                        s_wr_IDMA,
    dmaIsrIntf.m                        m_IDMA
);

// IDMA
logic sync_seq_snk_ready;
logic sync_seq_snk_valid;
logic [1:0] sync_seq_snk_data; // 1: ISR return, 0: rd/wr
logic [1:0] sync_seq_src_data;

// Sequence queue IDMA
queue #(
    .QTYPE(logic [1:0]),
    .QDEPTH(N_OUTSTANDING)
) inst_seq_que_idma (
    .aclk(aclk),
    .aresetn(aresetn),
    .val_snk(sync_seq_snk_valid),
    .rdy_snk(sync_seq_snk_ready),
    .data_snk(sync_seq_snk_data),
    .val_src(m_IDMA.rsp.done),
    .rdy_src(),
    .data_src(sync_seq_src_data)
);

always_comb begin
    s_rd_IDMA.rsp.done = m_IDMA.rsp.done && ~sync_seq_src_data[0];
    s_wr_IDMA.rsp.done = m_IDMA.rsp.done && sync_seq_src_data[0];
    
    s_rd_IDMA.rsp.pid = m_IDMA.rsp.pid;
    s_rd_IDMA.rsp.host = m_IDMA.rsp.host;
    s_wr_IDMA.rsp.pid = m_IDMA.rsp.pid;
    s_wr_IDMA.rsp.host = m_IDMA.rsp.host;
    s_rd_IDMA.rsp.isr = sync_seq_src_data[1];
    s_wr_IDMA.rsp.isr = sync_seq_src_data[1];

    if(mutex) begin // mutex[1]
        s_wr_IDMA.ready = m_IDMA.ready && sync_seq_snk_ready;
        s_rd_IDMA.ready = 1'b0;

        sync_seq_snk_valid = s_wr_IDMA.valid && s_wr_IDMA.ready && s_wr_IDMA.req.ctl; 
        sync_seq_snk_data = {s_wr_IDMA.req.isr, 1'b1};

        m_IDMA.valid = s_wr_IDMA.valid && s_wr_IDMA.ready;
        m_IDMA.req.paddr_host = s_wr_IDMA.req.paddr_host;
        m_IDMA.req.paddr_card = s_wr_IDMA.req.paddr_card;
        m_IDMA.req.len = s_wr_IDMA.req.len;
        m_IDMA.req.ctl = s_wr_IDMA.req.ctl;
        m_IDMA.req.isr = 1'b0;
        m_IDMA.req.pid = s_wr_IDMA.req.pid;
        m_IDMA.req.host = s_wr_IDMA.req.host;
    end 
    else begin
        s_rd_IDMA.ready = m_IDMA.ready && sync_seq_snk_ready;
        s_wr_IDMA.ready = 1'b0;

        sync_seq_snk_valid = s_rd_IDMA.valid && s_rd_IDMA.ready && s_rd_IDMA.req.ctl; 
        sync_seq_snk_data = {s_rd_IDMA.req.isr, 1'b0};

        m_IDMA.valid = s_rd_IDMA.valid && s_rd_IDMA.ready;
        m_IDMA.req.paddr_host = s_rd_IDMA.req.paddr_host;
        m_IDMA.req.paddr_card = s_rd_IDMA.req.paddr_card;
        m_IDMA.req.len = s_rd_IDMA.req.len;
        m_IDMA.req.ctl = s_rd_IDMA.req.ctl;
        m_IDMA.req.isr = 1'b0;
        m_IDMA.req.pid = s_rd_IDMA.req.pid;
        m_IDMA.req.host = s_rd_IDMA.req.host;
    end
end

/////////////////////////////////////////////////////////////////////////////
// DEBUG
/////////////////////////////////////////////////////////////////////////////
`ifdef DBG_TLB_IDMA_ARB

`endif

endmodule