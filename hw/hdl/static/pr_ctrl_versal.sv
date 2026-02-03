/*
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2026, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

import lynxTypes::*;

/**
 * @brief Versal PR controller
 *
 * Parses incoming DMA requests, which contain physical addresses of the partial PDI on the host,
 * splits them into 4 KiB transfers and issues commands on the QDMA MM H2C interface. The partial
 * PDI is delivered to the PMC SBI through a keyhole transfer at h000102100000. Additionally,
 * it waits for completion from the PMC (eos_pmc) after which it asserts the eos_ctrl signal.
 */
module pr_ctrl_versal(
    // Clock, reset
    input logic         aclk,
    input logic         aresetn,
    
    // End-of-startup (i.e. PR has completed)
    input logic         eos_pmc,
    output logic        eos_ctrl,

    // Commands & completions
    dmaIntf.s           s_pr_dma_rd_req,
    qdmaH2CSts.s        s_qdma_h2c_sts,
    qdmaH2CDescMM.m     m_qdma_h2c_pr_desc,

    // Statistics (for pr_stats module)
    output logic        pr_cmd_sent,
    output logic        pr_cmd_done
);

localparam integer PARSE_SIZE = 4096;

typedef enum logic[2:0]  {ST_IDLE, ST_WAIT_NEXT, ST_PARSE, ST_SEND, ST_WAIT_EOS} state_t;
logic [2:0] state_C, state_N;

logic last_C, last_N;

logic [LEN_BITS-1:0] len_C, len_N;
logic [LEN_BITS-1:0] len_prev_C, len_prev_N;

logic [PADDR_BITS-1:0] paddr_rd_C, paddr_rd_N;
logic [PADDR_BITS-1:0] paddr_rd_prev_C, paddr_rd_prev_N;

// REG
always_ff @(posedge aclk) begin: REG
    if (aresetn == 1'b0) begin
        state_C <= ST_IDLE;

        last_C <= 'X; 
        len_C <= 'X;
        len_prev_C <= 'X;
        paddr_rd_C <= 'X;
        paddr_rd_prev_C <= 'X;
    end else begin
        state_C <= state_N;

        last_C <= last_N; 
        len_C <= len_N;
        len_prev_C <= len_prev_N;
        paddr_rd_C <= paddr_rd_N;
        paddr_rd_prev_C <= paddr_rd_prev_N;
    end
end

// NSL
always_comb begin: NSL
	state_N = state_C;

	unique case(state_C)
		ST_IDLE: begin 
            if (s_pr_dma_rd_req.valid) begin
                state_N = ST_PARSE;
            end
        end

        ST_WAIT_NEXT: begin
            if (s_pr_dma_rd_req.valid) begin
                state_N = ST_PARSE;
            end
        end
            
        ST_PARSE: begin
            state_N = ST_SEND;
        end

        ST_SEND: begin
            if (m_qdma_h2c_pr_desc.ready) begin 
                state_N = len_C ? ST_PARSE : (last_C ? ST_WAIT_EOS : ST_WAIT_NEXT);
            end
        end

        ST_WAIT_EOS: begin
            state_N = eos_pmc ? ST_IDLE : ST_WAIT_EOS;
        end
	endcase
end

// DP
always_comb begin: DP
    // Register updates
    len_N = len_C;
    last_N = last_C;
    len_prev_N = len_prev_C;
    paddr_rd_N = paddr_rd_C;
    paddr_rd_prev_N = paddr_rd_prev_C;
    
    // Flow control
    s_pr_dma_rd_req.ready = 1'b0;
    m_qdma_h2c_pr_desc.valid = 1'b0;

    // PR data
    m_qdma_h2c_pr_desc.req.raddr    = paddr_rd_prev_C;
    m_qdma_h2c_pr_desc.req.qid      = QDMA_PR_QUEUE_IDX;
    m_qdma_h2c_pr_desc.req.waddr    = 64'h000102100000;         // SBI keyhole address to write partial images to
    m_qdma_h2c_pr_desc.req.len      = len_prev_C[15:0];         // Per specification, only lower 16 bits of len should be set
    m_qdma_h2c_pr_desc.req.mrkr_req = 1;                        // Ensures completion signal on the s_qdma_h2c_sts interface

    // Tie off unused/constant
    m_qdma_h2c_pr_desc.req.func     = 0; 
    m_qdma_h2c_pr_desc.req.error    = 0; 
    m_qdma_h2c_pr_desc.req.no_dma   = 0; 
    m_qdma_h2c_pr_desc.req.sdi      = 0; 
    m_qdma_h2c_pr_desc.req.port_id  = 0; 
    m_qdma_h2c_pr_desc.req.cidx     = 0; 

    // Completions
    s_pr_dma_rd_req.rsp.done = 1'b0;

    // EOS
    eos_ctrl = 1'b0;

    unique case (state_C)
        ST_IDLE: begin
            s_pr_dma_rd_req.ready = 1'b1;
            if (s_pr_dma_rd_req.valid) begin
                len_N = s_pr_dma_rd_req.req.len;
                last_N = s_pr_dma_rd_req.req.last;
                paddr_rd_N = s_pr_dma_rd_req.req.paddr;
            end
        end

        ST_WAIT_NEXT: begin
            // NOTE: Done is set when all commands have been processed; however, it doesn't account for
            // possible errors during PR command processing; therefore debug probes on this interface
            // should be used with care.
            s_pr_dma_rd_req.rsp.done = 1'b1;

            s_pr_dma_rd_req.ready = 1'b1;
            if (s_pr_dma_rd_req.valid) begin
                len_N = s_pr_dma_rd_req.req.len;
                last_N = s_pr_dma_rd_req.req.last;
                paddr_rd_N = s_pr_dma_rd_req.req.paddr;
            end
        end

        ST_PARSE: begin
            paddr_rd_prev_N = paddr_rd_C;
            
            if (len_C > PARSE_SIZE) begin
                paddr_rd_N = paddr_rd_C + PARSE_SIZE;
                len_N = len_C - PARSE_SIZE;
                len_prev_N = PARSE_SIZE;
            end else begin
                len_N = 0;
                len_prev_N = len_C;
            end
        end

        ST_SEND: begin
            m_qdma_h2c_pr_desc.valid = 1'b1; 

            if (m_qdma_h2c_pr_desc.ready && last_C) begin 
                s_pr_dma_rd_req.rsp.done = 1'b1;
            end
        end

        ST_WAIT_EOS: begin
            eos_ctrl = eos_pmc;
        end
        
    endcase

    // Statistics
    pr_cmd_sent = m_qdma_h2c_pr_desc.valid && m_qdma_h2c_pr_desc.ready;
    pr_cmd_done = s_qdma_h2c_sts.valid && 
        (s_qdma_h2c_sts.qid == QDMA_PR_QUEUE_IDX) &&          // Check for queue
        (s_qdma_h2c_sts.port_id == 0) &&                      // We always set port_id to 0 anyway    
        (s_qdma_h2c_sts.op == 8'h3) &&                        // OP should match H2C-MM
        !s_qdma_h2c_sts.data[16];                             // Error bit
end

endmodule