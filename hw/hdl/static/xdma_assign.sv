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