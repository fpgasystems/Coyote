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

    // IO
    s_req.ready = 1'b0;
    
    m_req_int.valid = 1'b0;
    m_req_int.data = s_req.data;

    n_beats = (s_req.data.req_1.len) >> BEAT_LOG_BITS;

    if(s_req.valid && m_req_int.ready && (cnt_C >= n_beats)) begin
        s_req.ready = 1'b1;
        m_req_int.valid = 1'b1;
 
        cnt_N = xfer ? cnt_C - (n_beats - 1) : cnt_C - n_beats;
    end
    else begin
        cnt_N = xfer ? cnt_C + 1 : cnt_C;
    end

end

meta_reg #(.DATA_BITS($bits(dreq_t))) inst_out_reg  (.aclk(aclk), .aresetn(aresetn), .s_meta(m_req_int), .m_meta(m_req));

/////////////////////////////////////////////////////////////////////////////
// DEBUG
/////////////////////////////////////////////////////////////////////////////
`ifdef DBG_REQ_CREDITS_WR

`endif


endmodule