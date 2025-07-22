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
 * @brief   Assign DMA to XDMA interface
 *
 * DMA -> XDMA. 
 */
module xdma_assign (
    dmaIntf.s                           s_dma_rd,
    dmaIntf.s                           s_dma_wr,
    xdmaIntf.m                          m_xdma
);

// RD
assign m_xdma.h2c_ctl             = {{11{1'b0}}, s_dma_rd.req.last, {2{1'b0}}, {2{s_dma_rd.req.last}}};
assign m_xdma.h2c_addr            = s_dma_rd.req.paddr;
assign m_xdma.h2c_len             = s_dma_rd.req.len;
assign m_xdma.h2c_valid           = s_dma_rd.valid & m_xdma.h2c_ready;
assign s_dma_rd.ready             = m_xdma.h2c_ready;
assign s_dma_rd.rsp.done          = m_xdma.h2c_status[1];

// WR
assign m_xdma.c2h_ctl             = {{11{1'b0}}, s_dma_wr.req.last, {2{1'b0}}, {2{s_dma_wr.req.last}}};
assign m_xdma.c2h_addr            = s_dma_wr.req.paddr;
assign m_xdma.c2h_len             = s_dma_wr.req.len;
assign m_xdma.c2h_valid           = s_dma_wr.valid & m_xdma.c2h_ready;
assign s_dma_wr.ready             = m_xdma.c2h_ready;
assign s_dma_wr.rsp.done          = m_xdma.c2h_status[1];

endmodule