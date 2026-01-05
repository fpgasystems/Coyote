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
 * @brief Forwards DMA requests with their last signal set to 1 while forwarding the actual last 
 * signal to the data path to overwrite the actual last signal.
 */
module mmu_assign (
	input logic aclk,    
	input logic aresetn,

	// User logic
    dmaIntf.s s_req,
    dmaIntf.m m_req,

    metaIntf.m m_fwd_last
);

metaIntf #(.STYPE(logic)) queue(.*);

always_comb begin
    m_req.req      = s_req.req;
    m_req.req.last = 1'b1;
    m_req.valid    = s_req.valid && queue.ready;
    s_req.ready    = m_req.ready;

    s_req.rsp = m_req.rsp;

    queue.data  = s_req.req.last;
    queue.valid = s_req.valid && m_req.ready;
end

queue_stream #(
    .QTYPE(logic),
    .QDEPTH(N_OUTSTANDING)
) inst_seq_que_user (
    .aclk(aclk),
    .aresetn(aresetn),

    .data_snk(queue.data),
    .val_snk(queue.valid),
    .rdy_snk(queue.ready),
    
    .data_src(m_fwd_last.data),
    .val_src(m_fwd_last.valid),
    .rdy_src(m_fwd_last.ready)
);

endmodule