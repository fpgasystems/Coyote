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
 * @brief   TLB credit based system for the write requests.
 *
 * Prevents region stalls from propagating to the whole system.
 *
 *  @param ID_REG           Number of associated vFPGA
 *  @param DATA_BITS        Size of the data bus
 */
module mmu_credits_wr #(
    parameter integer ID_REG = 0,
    parameter integer DATA_BITS = AXI_DATA_BITS
) (
    input  logic            aclk,
    input  logic            aresetn,
    
    // Requests
    dmaIntf.s               s_req,
    dmaIntf.m               m_req,

    // Data write
    input  logic            wxfer
);

// -- Constants
localparam integer BEAT_LOG_BITS = $clog2(DATA_BITS/8);
localparam integer BLEN_BITS = LEN_BITS - BEAT_LOG_BITS;

// -- Internal regs
logic [BLEN_BITS:0] cnt_C, cnt_N;

// -- Internal signals
logic [BLEN_BITS:0] n_beats;

// -- REG
always_ff @(posedge aclk) begin: PROC_REG
if (aresetn == 1'b0) begin
	cnt_C <= 0;

    s_req.rsp <= 0;
end
else
    cnt_C <= cnt_N;

    s_req.rsp <= m_req.rsp;
end

// -- DP
always_comb begin
    cnt_N =  cnt_C;

    // IO
    s_req.ready = 1'b0;
    
    m_req.valid = 1'b0;
    m_req.req = s_req.req;

    n_beats = (s_req.req.len) >> BEAT_LOG_BITS;

    if(s_req.valid && m_req.ready && (cnt_C >= n_beats)) begin
        s_req.ready = 1'b1;
        m_req.valid = 1'b1;
 
        cnt_N = wxfer ? cnt_C - (n_beats - 1) : cnt_C - n_beats;
    end
    else begin
        cnt_N = wxfer ? cnt_C + 1 : cnt_C;
    end

end

/////////////////////////////////////////////////////////////////////////////
// DEBUG
/////////////////////////////////////////////////////////////////////////////
`ifdef DBG_TLB_CREDITS_RD

`endif


endmodule