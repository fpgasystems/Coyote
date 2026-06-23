/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2021-2026, Systems Group, ETH Zurich
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


`timescale 1ns/1ps

import lynxTypes::*;

/**
 * @brief   NVMe PRP builder
 *
 * Translates a PRP request via the MMU and emits the PRP response and PRP-list
 * writes, handling 4 KB, 8 KB, and multi-page transfers.
 */
module nvme_prp_builder #(
    parameter integer PRP_ADDR_BITS = lynxTypes::PRP_ADDR_BITS
)(
    input  logic        aclk,
    input  logic        aresetn,

    metaIntf.s          s_nvme_prp_req,       // nvme_prp_req_t
    metaIntf.m          m_nvme_prp_rsp,       // nvme_prp_rsp_t

    metaIntf.m          m_nvme_mmu_req,       // req_t (strm=STRM_NVME)
    metaIntf.s          s_nvme_mmu_rsp,       // nvme_mmu_rsp_t

    metaIntf.m          m_nvme_prp_write_req, // nvme_prp_write_t

    input  logic [63:0] FPGA_BAR_BASE,
    input  logic [63:0] FPGA_PRP_BAR_BASE
);

    // State machine
    typedef enum logic [3:0] {
        ST_IDLE              = 4'd0,
        ST_SEND_MMU_PRP1     = 4'd1,
        ST_WAIT_MMU_PRP1     = 4'd2,
        ST_CHECK_SIZE        = 4'd3,
        ST_SEND_PRP_4KB      = 4'd4,
        ST_SEND_MMU_PRP2     = 4'd5,
        ST_WAIT_MMU_PRP2     = 4'd6,
        ST_SEND_PRP_8KB      = 4'd7,
        ST_SEND_PRP_MULT     = 4'd8,
        ST_SEND_WRITE_MULT   = 4'd9,
        ST_WAIT_MMU_MULT     = 4'd10,
        ST_SEND_WRITE_LOOP   = 4'd11,
        ST_FAULT             = 4'd12
    } state_t;

    state_t          state_C, state_N;

    // Registered data
    nvme_prp_req_t   prp_req_C, prp_req_N;
    nvme_prp_rsp_t   prp_rsp_C, prp_rsp_N;
    nvme_prp_write_t prp_write_C, prp_write_N;
    nvme_mmu_rsp_t   mmu_rsp_C, mmu_rsp_N;

    // Temporaries (module scope)
    req_t            mmu_req;

    // Combinational logic
    always_comb begin
        // Defaults
        state_N     = state_C;
        prp_req_N   = prp_req_C;
        prp_rsp_N   = prp_rsp_C;
        prp_write_N = prp_write_C;
        mmu_rsp_N   = mmu_rsp_C;

        s_nvme_prp_req.ready       = 1'b0;
        m_nvme_mmu_req.valid       = 1'b0;
        m_nvme_mmu_req.data        = '0;

        s_nvme_mmu_rsp.ready       = 1'b0;

        m_nvme_prp_rsp.valid       = 1'b0;
        m_nvme_prp_rsp.data        = '0;

        m_nvme_prp_write_req.valid = 1'b0;
        m_nvme_prp_write_req.data  = '0;

        mmu_req = '0;

        case (state_C)
            // ST_IDLE: Accept PRP request
            ST_IDLE: begin
                s_nvme_prp_req.ready = 1'b1;
                if (s_nvme_prp_req.valid) begin
                    prp_req_N = s_nvme_prp_req.data;
                    prp_rsp_N = '0;
                    state_N   = ST_SEND_MMU_PRP1;
                end
            end

            // ST_SEND_MMU_PRP1: Send MMU request for PRP1
            ST_SEND_MMU_PRP1: begin
                mmu_req       = '0;
                mmu_req.strm  = STRM_NVME;
                mmu_req.vaddr = prp_req_C.vaddr;
                mmu_req.len   = prp_req_C.len;
                mmu_req.last  = 1'b1;

                m_nvme_mmu_req.valid = 1'b1;
                m_nvme_mmu_req.data  = mmu_req;

                if (m_nvme_mmu_req.ready) begin
                    state_N = ST_WAIT_MMU_PRP1;
                end
            end

            // ST_WAIT_MMU_PRP1: Receive MMU response for PRP1
            ST_WAIT_MMU_PRP1: begin
                s_nvme_mmu_rsp.ready = 1'b1;
                if (s_nvme_mmu_rsp.valid) begin
                    mmu_rsp_N = s_nvme_mmu_rsp.data;
                    // Translation fault → abort
                    if (s_nvme_mmu_rsp.data.fault)
                        state_N = ST_FAULT;
                    else
                        state_N = ST_CHECK_SIZE;
                end
            end

            // ST_CHECK_SIZE: Decide path based on transfer size
            ST_CHECK_SIZE: begin
                // Set PRP1
                prp_rsp_N = prp_rsp_C;
                if (mmu_rsp_C.is_host == 1'b0)
                    prp_rsp_N.prp1 = mmu_rsp_C.paddr + FPGA_BAR_BASE;
                else
                    prp_rsp_N.prp1 = mmu_rsp_C.paddr;

                if (prp_req_C.len <= 4096) begin
                    // 4KB: Only PRP1 needed
                    prp_rsp_N.prp2 = 64'd0;
                    state_N = ST_SEND_PRP_4KB;
                end
                else begin
                    // >4KB: Need PRP2, send MMU request
                    state_N = ST_SEND_MMU_PRP2;
                end
            end

            // ST_SEND_PRP_4KB: Send PRP response (4KB case)
            ST_SEND_PRP_4KB: begin
                m_nvme_prp_rsp.valid = 1'b1;
                m_nvme_prp_rsp.data  = prp_rsp_C;

                if (m_nvme_prp_rsp.ready) begin
                    state_N = ST_IDLE;
                end
            end

            // ST_SEND_MMU_PRP2: Send MMU request for PRP2 (>4KB)
            ST_SEND_MMU_PRP2: begin
                // MMU continues streaming from previous request
                // Just wait for next response
                state_N = ST_WAIT_MMU_PRP2;
            end

            // ST_WAIT_MMU_PRP2: Receive MMU response for PRP2
            ST_WAIT_MMU_PRP2: begin
                s_nvme_mmu_rsp.ready = 1'b1;
                if (s_nvme_mmu_rsp.valid) begin
                    mmu_rsp_N = s_nvme_mmu_rsp.data;

                    if (s_nvme_mmu_rsp.data.fault) begin
                        // Translation fault → abort
                        state_N = ST_FAULT;
                    end
                    else if (prp_req_C.len <= 8192) begin
                        // 8KB: PRP2 is direct address
                        prp_rsp_N = prp_rsp_C;
                        if (s_nvme_mmu_rsp.data.is_host == 1'b0)
                            prp_rsp_N.prp2 = s_nvme_mmu_rsp.data.paddr + FPGA_BAR_BASE;
                        else
                            prp_rsp_N.prp2 = s_nvme_mmu_rsp.data.paddr;
                        state_N = ST_SEND_PRP_8KB;
                    end
                    else begin
                        // >8KB: PRP2 points to PRP list
                        prp_rsp_N = prp_rsp_C;
                        prp_rsp_N.prp2 = FPGA_PRP_BAR_BASE
                                       + (prp_req_C.dev_id  << (NVME_QUEUE_BITS + 12))
                                       + (prp_req_C.sq_tail << 12);

                        // Prepare first write entry
                        prp_write_N.addr = {prp_req_C.dev_id, prp_req_C.sq_tail, {PRP_ADDR_BITS{1'b0}}};
                        if (s_nvme_mmu_rsp.data.is_host == 1'b0)
                            prp_write_N.data = s_nvme_mmu_rsp.data.paddr + FPGA_BAR_BASE;
                        else
                            prp_write_N.data = s_nvme_mmu_rsp.data.paddr;

                        state_N = ST_SEND_PRP_MULT;
                    end
                end
            end

            // ST_SEND_PRP_8KB: Send PRP response (8KB case)
            ST_SEND_PRP_8KB: begin
                m_nvme_prp_rsp.valid = 1'b1;
                m_nvme_prp_rsp.data  = prp_rsp_C;

                if (m_nvme_prp_rsp.ready) begin
                    state_N = ST_IDLE;
                end
            end

            // ST_SEND_PRP_MULT: Send PRP response (>8KB, with list)
            ST_SEND_PRP_MULT: begin
                m_nvme_prp_rsp.valid = 1'b1;
                m_nvme_prp_rsp.data  = prp_rsp_C;

                if (m_nvme_prp_rsp.ready) begin
                    state_N = ST_SEND_WRITE_MULT;
                end
            end

            // ST_SEND_WRITE_MULT: Send first PRP list write
            ST_SEND_WRITE_MULT: begin
                m_nvme_prp_write_req.valid = 1'b1;
                m_nvme_prp_write_req.data  = prp_write_C;

                if (m_nvme_prp_write_req.ready) begin
                    prp_write_N.addr = prp_write_C.addr + 1'b1;
                    state_N = ST_WAIT_MMU_MULT;
                end
            end

            // ST_WAIT_MMU_MULT: Wait for next MMU response
            ST_WAIT_MMU_MULT: begin
                s_nvme_mmu_rsp.ready = 1'b1;
                if (s_nvme_mmu_rsp.valid) begin
                    mmu_rsp_N = s_nvme_mmu_rsp.data;

                    if (s_nvme_mmu_rsp.data.fault) begin
                        // Translation fault → abort
                        state_N = ST_FAULT;
                    end
                    else begin
                        // Prepare write data
                        prp_write_N = prp_write_C;
                        if (s_nvme_mmu_rsp.data.is_host == 1'b0)
                            prp_write_N.data = s_nvme_mmu_rsp.data.paddr + FPGA_BAR_BASE;
                        else
                            prp_write_N.data = s_nvme_mmu_rsp.data.paddr;

                        state_N = ST_SEND_WRITE_LOOP;
                    end
                end
            end

            // ST_SEND_WRITE_LOOP: Send PRP list write entries
            ST_SEND_WRITE_LOOP: begin
                m_nvme_prp_write_req.valid = 1'b1;
                m_nvme_prp_write_req.data  = prp_write_C;

                if (m_nvme_prp_write_req.ready) begin
                    if (mmu_rsp_C.last) begin
                        // Last entry written
                        state_N = ST_IDLE;
                    end
                    else begin
                        // More entries to come
                        prp_write_N.addr = prp_write_C.addr + 1'b1;
                        state_N = ST_WAIT_MMU_MULT;
                    end
                end
            end

            // ST_FAULT: abort command, no PRP issued
            ST_FAULT: begin
                state_N = ST_IDLE;
            end

            default: begin
                state_N = ST_IDLE;
            end
        endcase
    end

    // Sequential logic
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            state_C     <= ST_IDLE;
            prp_req_C   <= '0;
            prp_rsp_C   <= '0;
            prp_write_C <= '0;
            mmu_rsp_C   <= '0;
        end
        else begin
            state_C     <= state_N;
            prp_req_C   <= prp_req_N;
            prp_rsp_C   <= prp_rsp_N;
            prp_write_C <= prp_write_N;
            mmu_rsp_C   <= mmu_rsp_N;
        end
    end

    // ILA Debug
// `define EN_ILA_NVME_MANAGE_PRP
`ifdef EN_ILA_NVME_MANAGE_PRP
    ila_nvme_manage_prp inst_ila_nvme_manage_prp (
        .clk    (aclk),
        .probe0 (s_nvme_prp_req.valid),                 // 1
        .probe1 (s_nvme_prp_req.ready),                 // 1
        .probe2 (m_nvme_prp_rsp.valid),                 // 1
        .probe3 (m_nvme_prp_rsp.ready),                 // 1
        .probe4 (m_nvme_prp_rsp.data.prp1),             // 64
        .probe5 (m_nvme_prp_rsp.data.prp2),             // 64
        .probe6 (m_nvme_mmu_req.valid),                 // 1
        .probe7 (m_nvme_mmu_req.ready),                 // 1
        .probe8 (s_nvme_mmu_rsp.valid),                 // 1
        .probe9 (s_nvme_mmu_rsp.ready),                 // 1
        .probe10(s_nvme_mmu_rsp.data.paddr),            // ADDR_BITS (48)
        .probe11(s_nvme_mmu_rsp.data.fault),            // 1
        .probe12(m_nvme_prp_write_req.valid),           // 1
        .probe13(m_nvme_prp_write_req.ready),           // 1
        .probe14(state_C),                              // 4
        .probe15(FPGA_BAR_BASE)                         // 64
    );
`endif

endmodule
