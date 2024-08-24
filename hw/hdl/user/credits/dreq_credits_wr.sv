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
 * @brief   Credit based system for the write requests.
 *
 * Prevents region stalls from propagating to the whole system.
 *
 *  @param DATA_BITS        Size of the data bus
 */
module dreq_credits_wr #(
    parameter integer DATA_BITS = AXI_DATA_BITS
) (
    input  logic            aclk,
    input  logic            aresetn,
    
    // Requests
    metaIntf.s              s_req,
    metaIntf.m              m_req,

    // Data write
    input  logic            xfer
);

// -- Internal regs
logic [BLEN_BITS:0] cnt_C, cnt_N;

// -- Internal signals
logic [BLEN_BITS:0] n_beats;

metaIntf #(.STYPE(dreq_t)) m_req_int ();

// -- REG
always_ff @(posedge aclk) begin: PROC_REG
if (aresetn == 1'b0) begin
	cnt_C <= 0;
end
else
    cnt_C <= cnt_N;
end

// -- DP
always_comb begin
    cnt_N =  cnt_C;

    n_beats = (s_req.data.req_1.len) >> BEAT_LOG_BITS;

    if(s_req.valid && m_req_int.ready && (cnt_C >= n_beats)) begin
        s_req.ready = 1'b1;
        m_req_int.valid = 1'b1;
 
        cnt_N = xfer ? cnt_C - (n_beats - 1) : cnt_C - n_beats;
    end
    else begin
        cnt_N = xfer ? cnt_C + 1 : cnt_C;

        // IO
        s_req.ready = 1'b0;

        m_req_int.valid = 1'b0;
        m_req_int.data = s_req.data;
    end

end

meta_reg #(.DATA_BITS($bits(dreq_t))) inst_out_reg  (.aclk(aclk), .aresetn(aresetn), .s_meta(m_req_int), .m_meta(m_req));

/////////////////////////////////////////////////////////////////////////////
// DEBUG
/////////////////////////////////////////////////////////////////////////////
`ifdef DBG_REQ_CREDITS_WR

`endif


endmodule
