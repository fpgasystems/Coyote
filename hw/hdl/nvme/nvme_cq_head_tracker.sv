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
 * @brief   NVMe CQ head tracker
 *
 * Tracks the per-device CQ head and issues the CQ doorbell DMA when the batch
 * or timeout trigger fires, round-robining across devices.
 */
module nvme_cq_head_tracker #(
    parameter int unsigned NVME_QUEUE_BITS = 6,
    parameter int unsigned N_NVME_BITS     = 4,
    parameter int unsigned BATCH_SIZE      = 4,
    parameter int unsigned TIMEOUT_CYCLES  = 80
)(
    input  logic        aclk,
    input  logic        aresetn,

    // Pulse on each CQE handshake
    input  logic                    cqe_valid,
    input  logic [N_NVME_BITS-1:0]  cqe_dev_id,    // which device's CQE

    // Output: CQ head update to info_table
    metaIntf.m          m_cq_head_update,   // cq_head_update_t

    // Output: CQ Doorbell DMA
    dmaIntf.m           m_cq_dma_req,
    AXI4S.m             m_cq_dma_data,

    // Config: per-device SQ doorbell addresses (CQ doorbell = SQ + 4)
    input  logic [63:0] sq_db_addr_tbl [(1 << N_NVME_BITS)]
);

    localparam int unsigned CQ_DEPTH     = (1 << NVME_QUEUE_BITS);
    localparam int unsigned N_NVME       = (1 << N_NVME_BITS);
    localparam int unsigned TIMER_BITS   = $clog2(TIMEOUT_CYCLES + 1);
    localparam logic [63:0] CQ_DB_OFFSET = 64'd4;

    // Per-device state
    logic [NVME_QUEUE_BITS-1:0] internal_head [N_NVME];
    logic [NVME_QUEUE_BITS-1:0] external_head [N_NVME];
    logic [TIMER_BITS-1:0]      timer         [N_NVME];

    // FSM
    typedef enum logic [2:0] {
        ST_SCAN,
        ST_SEND_DMA_REQ,
        ST_SEND_DMA_DATA,
        ST_UPDATE_TABLE
    } state_t;

    state_t                   state_C, state_N;
    logic [N_NVME_BITS-1:0]   scan_dev_C, scan_dev_N;   // device being scanned/serviced

    // Pending count for scanned device
    logic [NVME_QUEUE_BITS:0] pending_count;

    always_comb begin
        if (internal_head[scan_dev_C] >= external_head[scan_dev_C])
            pending_count = internal_head[scan_dev_C] - external_head[scan_dev_C];
        else
            pending_count = CQ_DEPTH - external_head[scan_dev_C] + internal_head[scan_dev_C];
    end

    logic batch_trigger;
    logic timeout_trigger;
    logic should_send_dma;

    assign batch_trigger   = (pending_count >= BATCH_SIZE);
    assign timeout_trigger = (timer[scan_dev_C] >= TIMEOUT_CYCLES) && (pending_count > 0);
    assign should_send_dma = batch_trigger || timeout_trigger;

    // CQ doorbell = SQ doorbell + 4, indexed by current scan device
    logic [63:0] cq_doorbell_addr;
    assign cq_doorbell_addr = sq_db_addr_tbl[scan_dev_C] + CQ_DB_OFFSET;

    // Combinational logic
    always_comb begin
        state_N    = state_C;
        scan_dev_N = scan_dev_C;

        m_cq_head_update.valid = 1'b0;
        m_cq_head_update.data  = '0;

        m_cq_dma_req.valid = 1'b0;
        m_cq_dma_req.req   = '0;

        m_cq_dma_data.tvalid = 1'b0;
        m_cq_dma_data.tdata  = '0;
        m_cq_dma_data.tkeep  = '0;
        m_cq_dma_data.tlast  = 1'b0;

        case (state_C)

            ST_SCAN: begin
                if (should_send_dma) begin
                    state_N = ST_SEND_DMA_REQ;
                end else begin
                    // Move to next device
                    scan_dev_N = scan_dev_C + 1'b1;
                end
            end

            ST_SEND_DMA_REQ: begin
                m_cq_dma_req.valid     = 1'b1;
                m_cq_dma_req.req.paddr = cq_doorbell_addr;
                m_cq_dma_req.req.len   = 4;
                m_cq_dma_req.req.last  = 1'b1;
                m_cq_dma_req.req.rsrvd = '0;

                if (m_cq_dma_req.ready)
                    state_N = ST_SEND_DMA_DATA;
            end

            ST_SEND_DMA_DATA: begin
                m_cq_dma_data.tvalid = 1'b1;
                m_cq_dma_data.tdata  = {'0, {(32-NVME_QUEUE_BITS){1'b0}}, internal_head[scan_dev_C]};
                m_cq_dma_data.tkeep  = {{(AXI_DATA_BITS/8 - 4){1'b0}}, 4'hF};
                m_cq_dma_data.tlast  = 1'b1;

                if (m_cq_dma_data.tready)
                    state_N = ST_UPDATE_TABLE;
            end

            ST_UPDATE_TABLE: begin
                m_cq_head_update.valid        = 1'b1;
                m_cq_head_update.data.dev_id  = scan_dev_C;
                m_cq_head_update.data.cq_head = external_head[scan_dev_C];

                if (m_cq_head_update.ready) begin
                    // Move to next device after servicing
                    scan_dev_N = scan_dev_C + 1'b1;
                    state_N    = ST_SCAN;
                end
            end

            default: state_N = ST_SCAN;

        endcase
    end

    // Sequential logic
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            state_C    <= ST_SCAN;
            scan_dev_C <= '0;
            for (int d = 0; d < N_NVME; d++) begin
                internal_head[d] <= '0;
                external_head[d] <= '0;
                timer[d]         <= '0;
            end
        end
        else begin
            state_C    <= state_N;
            scan_dev_C <= scan_dev_N;

            // Advance internal_head on each CQE
            if (cqe_valid) begin
                if (internal_head[cqe_dev_id] == CQ_DEPTH - 1)
                    internal_head[cqe_dev_id] <= '0;
                else
                    internal_head[cqe_dev_id] <= internal_head[cqe_dev_id] + 1'b1;
            end

            // Update timers for all devices
            for (int d = 0; d < N_NVME; d++) begin
                if (internal_head[d] != external_head[d]) begin
                    if (timer[d] < TIMEOUT_CYCLES)
                        timer[d] <= timer[d] + 1'b1;
                end else begin
                    timer[d] <= '0;
                end
            end

            // On DMA data sent: snapshot external_head, reset timer
            if (state_C == ST_SEND_DMA_DATA && m_cq_dma_data.tvalid && m_cq_dma_data.tready) begin
                external_head[scan_dev_C] <= internal_head[scan_dev_C];
                timer[scan_dev_C]         <= '0;
            end
        end
    end

    // ILA Debug
// `define EN_ILA_NVME_CQ_HEAD_TRACKER
`ifdef EN_ILA_NVME_CQ_HEAD_TRACKER
    ila_nvme_cq_head_tracker inst_ila_nvme_cq_head_tracker (
        .clk    (aclk),
        .probe0 (cqe_valid),                            // 1
        .probe1 (cqe_dev_id),                           // N_NVME_BITS (4)
        .probe2 (state_C),                              // 3
        .probe3 (scan_dev_C),                           // N_NVME_BITS (4)
        .probe4 (m_cq_head_update.valid),               // 1
        .probe5 (m_cq_head_update.ready),               // 1
        .probe6 (m_cq_head_update.data.dev_id),         // N_NVME_BITS (4)
        .probe7 (m_cq_head_update.data.cq_head),        // NVME_QUEUE_BITS (6)
        .probe8 (m_cq_dma_req.valid),                   // 1
        .probe9 (m_cq_dma_req.ready),                   // 1
        .probe10(m_cq_dma_req.req.paddr),               // ADDR_BITS (48)
        .probe11(m_cq_dma_data.tvalid),                 // 1
        .probe12(m_cq_dma_data.tready),                 // 1
        .probe13(pending_count),                        // NVME_QUEUE_BITS+1 (7)
        .probe14(should_send_dma),                      // 1
        .probe15(cq_doorbell_addr)                      // 64
    );
`endif

endmodule
