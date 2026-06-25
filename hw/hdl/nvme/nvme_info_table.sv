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
 * @brief   NVMe info table
 *
 * Stores per-device NVMe info and per-(region, device) permissions.
 * Write priority: update_tbl > perm_update > cq_head_update > tbl_req.
 */
module nvme_info_table #(
    parameter int MAX_NVME_DEVICES = 16,
    parameter int MAX_NSID         = 256
) (
    input  logic        aclk,
    input  logic        aresetn,

    metaIntf.s          s_tbl_req,         // nvme_info_req_t (with region_id, naddr, len)
    metaIntf.m          m_tbl_rsp,         // nvme_info_rsp_t (with lba_offset)

    metaIntf.s          s_cq_head_update,  // cq_head_update_t
    metaIntf.s          s_update_tbl,      // update_tbl_t (device info)
    metaIntf.s          s_perm_update      // nvme_perm_update_t (region permission)
);

    // Storage arrays
    nvme_info_entry_t nvme_info_tbl [MAX_NVME_DEVICES][MAX_NSID];
    nvme_queue_ptr_t  pointer_table [MAX_NVME_DEVICES];
    nvme_perm_entry_t perm_table    [N_REGIONS][MAX_NVME_DEVICES];

    // Response registers
    nvme_info_rsp_t   rsp_C, rsp_N;
    logic             rsp_valid_C, rsp_valid_N;

    // Temporaries
    logic             rsp_free;

    integer i, j, k;

    // Combinational logic
    always_comb begin
        // Defaults
        s_update_tbl.ready     = 1'b0;
        s_perm_update.ready    = 1'b0;
        s_cq_head_update.ready = 1'b0;
        s_tbl_req.ready        = 1'b0;

        m_tbl_rsp.valid = rsp_valid_C;
        m_tbl_rsp.data  = rsp_C;

        rsp_N       = rsp_C;
        rsp_valid_N = rsp_valid_C;

        // Response slot is free when empty or being consumed this cycle
        rsp_free = (~rsp_valid_C) || (rsp_valid_C && m_tbl_rsp.ready);

        // Clear valid when consumed
        if (rsp_valid_C && m_tbl_rsp.ready) begin
            rsp_valid_N = 1'b0;
        end

        // One accepted op per cycle when response slot is free
        // Priority: update_tbl > perm_update > cq_head_update > tbl_req
        if (rsp_free) begin
            if (s_update_tbl.valid) begin
                s_update_tbl.ready = 1'b1;
            end
            else if (s_perm_update.valid) begin
                s_perm_update.ready = 1'b1;
            end
            else if (s_cq_head_update.valid) begin
                s_cq_head_update.ready = 1'b1;
            end
            else if (s_tbl_req.valid) begin
                s_tbl_req.ready = 1'b1;

                // Generate response based on table lookup
                rsp_N = '0;

                // Bounds check
                if (s_tbl_req.data.dev_id >= MAX_NVME_DEVICES || s_tbl_req.data.nsid >= MAX_NSID) begin
                    rsp_N.error = NVME_NO_DEVICE;
                end
                // Valid check
                else if (!nvme_info_tbl[s_tbl_req.data.dev_id][s_tbl_req.data.nsid].valid) begin
                    rsp_N.error = NVME_NO_DEVICE;
                end
                // Permission check: region allowed for this device?
                else if (!perm_table[s_tbl_req.data.region_id][s_tbl_req.data.dev_id].valid) begin
                    rsp_N.error = NVME_PERMISSION_DENIED;
                end
                // Permission check: offset + len within allowed range?
                else if ((s_tbl_req.data.naddr + s_tbl_req.data.len) >
                         perm_table[s_tbl_req.data.region_id][s_tbl_req.data.dev_id].lba_size) begin
                    rsp_N.error = NVME_PERMISSION_DENIED;
                end
                // SQ full: backpressure (deassert ready) instead of erroring, so
                // the upstream holds the request until a completion frees a slot.
                else if ((pointer_table[s_tbl_req.data.dev_id].sq_tail + 1'b1) ==
                          pointer_table[s_tbl_req.data.dev_id].cq_head) begin
                    s_tbl_req.ready = 1'b0;
                end
                // Success path
                else begin
                    rsp_N.error      = NVME_NO_ERROR;
                    rsp_N.dev_id     = s_tbl_req.data.dev_id;
                    rsp_N.nsid       = s_tbl_req.data.nsid;
                    rsp_N.lbaf       = nvme_info_tbl[s_tbl_req.data.dev_id][s_tbl_req.data.nsid].lbaf;
                    rsp_N.nsze       = nvme_info_tbl[s_tbl_req.data.dev_id][s_tbl_req.data.nsid].nsze;
                    rsp_N.sq_db_addr = nvme_info_tbl[s_tbl_req.data.dev_id][s_tbl_req.data.nsid].sq_db_addr;
                    rsp_N.sq_tail    = pointer_table[s_tbl_req.data.dev_id].sq_tail;
                    rsp_N.lba_offset = perm_table[s_tbl_req.data.region_id][s_tbl_req.data.dev_id].lba_offset;
                end

                // Emit a response only when the request was accepted; a
                // backpressured (SQ-full) request produces no response.
                rsp_valid_N = s_tbl_req.ready;
            end
        end
    end

    // Sequential logic
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            rsp_C       <= '0;
            rsp_valid_C <= 1'b0;

            for (i = 0; i < MAX_NVME_DEVICES; i++) begin
                pointer_table[i] <= '0;
                for (j = 0; j < MAX_NSID; j++) begin
                    nvme_info_tbl[i][j] <= '0;
                end
            end
            for (k = 0; k < N_REGIONS; k++) begin
                for (i = 0; i < MAX_NVME_DEVICES; i++) begin
                    perm_table[k][i] <= '0;
                end
            end
        end
        else begin
            rsp_C       <= rsp_N;
            rsp_valid_C <= rsp_valid_N;

            // Update device info (highest priority)
            if (s_update_tbl.valid && s_update_tbl.ready) begin
                nvme_info_tbl[s_update_tbl.data.dev_id][s_update_tbl.data.nsid].lbaf       <= s_update_tbl.data.lbaf;
                nvme_info_tbl[s_update_tbl.data.dev_id][s_update_tbl.data.nsid].nsze       <= s_update_tbl.data.nsze;
                nvme_info_tbl[s_update_tbl.data.dev_id][s_update_tbl.data.nsid].valid      <= s_update_tbl.data.valid;
                nvme_info_tbl[s_update_tbl.data.dev_id][s_update_tbl.data.nsid].sq_db_addr <= s_update_tbl.data.sq_db_addr;

                if (s_update_tbl.data.reset_queue) begin
                    pointer_table[s_update_tbl.data.dev_id].sq_tail <= '0;
                    pointer_table[s_update_tbl.data.dev_id].cq_head <= '0;
                end
            end
            // Update permission entry
            else if (s_perm_update.valid && s_perm_update.ready) begin
                perm_table[s_perm_update.data.region_id][s_perm_update.data.dev_id].lba_offset <= s_perm_update.data.lba_offset;
                perm_table[s_perm_update.data.region_id][s_perm_update.data.dev_id].lba_size   <= s_perm_update.data.lba_size;
                perm_table[s_perm_update.data.region_id][s_perm_update.data.dev_id].valid      <= 1'b1;
            end
            // CQ head update
            else if (s_cq_head_update.valid && s_cq_head_update.ready) begin
                pointer_table[s_cq_head_update.data.dev_id].cq_head <= s_cq_head_update.data.cq_head;
            end
            // Table read request -> increment sq_tail on success
            else if (s_tbl_req.valid && s_tbl_req.ready) begin
                if (s_tbl_req.data.dev_id < MAX_NVME_DEVICES &&
                    s_tbl_req.data.nsid < MAX_NSID &&
                    nvme_info_tbl[s_tbl_req.data.dev_id][s_tbl_req.data.nsid].valid &&
                    perm_table[s_tbl_req.data.region_id][s_tbl_req.data.dev_id].valid &&
                    ((s_tbl_req.data.naddr + s_tbl_req.data.len) <=
                     perm_table[s_tbl_req.data.region_id][s_tbl_req.data.dev_id].lba_size) &&
                    (pointer_table[s_tbl_req.data.dev_id].sq_tail + 1'b1) !=
                     pointer_table[s_tbl_req.data.dev_id].cq_head) begin

                    pointer_table[s_tbl_req.data.dev_id].sq_tail <= pointer_table[s_tbl_req.data.dev_id].sq_tail + 1'b1;
                end
            end
        end
    end

    // ILA Debug
// `define EN_ILA_NVME_INFO_TABLE
`ifdef EN_ILA_NVME_INFO_TABLE
    ila_nvme_info_table inst_ila_nvme_info_table (
        .clk    (aclk),
        // s_tbl_req
        .probe0 (s_tbl_req.valid),                      // 1
        .probe1 (s_tbl_req.ready),                      // 1
        .probe2 (s_tbl_req.data.dev_id),                // N_NVME_BITS (4)
        .probe3 (s_tbl_req.data.region_id),             // REGION_ID_BITS
        .probe4 (s_tbl_req.data.naddr),                 // ADDR_BITS (48)
        .probe5 (s_tbl_req.data.len),                   // LEN_BITS (28)
        // m_tbl_rsp
        .probe6 (m_tbl_rsp.valid),                      // 1
        .probe7 (m_tbl_rsp.ready),                      // 1
        .probe8 (m_tbl_rsp.data.error),                 // 16
        .probe9 (m_tbl_rsp.data.lba_offset),            // 64
        .probe10(m_tbl_rsp.data.sq_tail),               // NVME_QUEUE_BITS (6)
        // s_cq_head_update
        .probe11(s_cq_head_update.valid),               // 1
        .probe12(s_cq_head_update.ready),               // 1
        .probe13(s_cq_head_update.data.dev_id),         // N_NVME_BITS (4)
        .probe14(s_cq_head_update.data.cq_head),        // NVME_QUEUE_BITS (6)
        // s_update_tbl
        .probe15(s_update_tbl.valid),                   // 1
        .probe16(s_update_tbl.ready),                   // 1
        .probe17(s_update_tbl.data.dev_id),             // N_NVME_BITS (4)
        // s_perm_update
        .probe18(s_perm_update.valid),                  // 1
        .probe19(s_perm_update.ready),                  // 1
        .probe20(s_perm_update.data.region_id),         // REGION_ID_BITS
        .probe21(s_perm_update.data.dev_id),            // N_NVME_BITS (4)
        // Internal
        .probe22(rsp_free),                             // 1
        .probe23(rsp_valid_C)                           // 1
    );
`endif

endmodule
