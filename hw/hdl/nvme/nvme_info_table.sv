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
 * SQ space follows SQHD; CID/PRP ownership follows completion, independently.
 */
module nvme_info_table #(
    parameter int MAX_NVME_DEVICES = NVME_NUM_DEVICES,
    parameter int MAX_NSID         = 256
) (
    input  logic        aclk,
    input  logic        aresetn,

    metaIntf.s          s_tbl_req,         // nvme_info_req_t (with region_id, naddr, len)
    metaIntf.m          m_tbl_rsp,         // nvme_info_rsp_t (with lba_offset)

    // Internal sidebands; shared request/response types stay unchanged.
    output logic [NVME_QUEUE_BITS-1:0] alloc_cid,
    input logic cpl_valid,
    input logic [N_NVME_BITS-1:0] cpl_dev,
    input logic [NVME_QUEUE_BITS-1:0] cpl_cid,
    input logic [15:0] cpl_sq_head,
    input logic resolve_valid,
    input logic resolve_abort,
    input logic [N_NVME_BITS-1:0] resolve_dev,
    input logic [NVME_QUEUE_BITS-1:0] resolve_cid,
    metaIntf.s          s_update_tbl,      // update_tbl_t (device info)
    metaIntf.s          s_perm_update      // nvme_perm_update_t (region permission)
);

    // Storage arrays
    nvme_info_entry_t nvme_info_tbl [MAX_NVME_DEVICES][MAX_NSID];
    logic [NVME_QUEUE_BITS-1:0] sq_tail [MAX_NVME_DEVICES];
    logic [NVME_QUEUE_BITS-1:0] sq_head [MAX_NVME_DEVICES];
    localparam int CID_COUNT = 1 << NVME_QUEUE_BITS;
    // The free pool is authoritative. This bitmap is a simulation scoreboard,
    // maintained with local updates to check ownership and return invariants.
`ifndef SYNTHESIS
    logic [CID_COUNT-1:0] cid_owned [MAX_NVME_DEVICES];
`endif
    // At most one unpublished SQ slot per device. Tail commits only after
    // SQE storage, so a preparation failure can cancel without an SQ hole.
    logic sq_reserved [MAX_NVME_DEVICES];
    logic [NVME_QUEUE_BITS-1:0] reserved_cid [MAX_NVME_DEVICES];
    nvme_perm_entry_t perm_table    [N_REGIONS][MAX_NVME_DEVICES];

    // Response registers
    nvme_info_rsp_t   rsp_C, rsp_N;
    logic             rsp_valid_C, rsp_valid_N;

    // Temporaries
    logic             rsp_free;
    logic             request_ready;
    logic [NVME_QUEUE_BITS-1:0] rsp_cid_C;
    logic [NVME_QUEUE_BITS-1:0] next_sq_tail;

    // One FIFO per device, with a registered head. Completion returns use its
    // single write port. An aborted unpublished command uses a separate cache:
    // at most one reservation exists per device, and allocation consumes this
    // cache before the FIFO. Thus completion + abort needs no second write port.
    logic [MAX_NVME_DEVICES-1:0] pool_ready, recycled_valid;
    logic [NVME_QUEUE_BITS:0] free_count [MAX_NVME_DEVICES];
    logic [NVME_QUEUE_BITS-1:0] pool_head [MAX_NVME_DEVICES];
    logic [NVME_QUEUE_BITS-1:0] recycled_cid [MAX_NVME_DEVICES];
    logic [NVME_QUEUE_BITS-1:0] candidate_cid_C;
    logic candidate_valid_C;
    wire allocate = s_tbl_req.valid && request_ready && rsp_N.error == NVME_NO_ERROR;
    assign candidate_valid_C = (s_tbl_req.data.dev_id < MAX_NVME_DEVICES) ?
        pool_ready[s_tbl_req.data.dev_id] &&
        (recycled_valid[s_tbl_req.data.dev_id] || free_count[s_tbl_req.data.dev_id] != 0) : 1'b0;
    assign candidate_cid_C = (s_tbl_req.data.dev_id < MAX_NVME_DEVICES) ?
        (recycled_valid[s_tbl_req.data.dev_id] ? recycled_cid[s_tbl_req.data.dev_id] :
         pool_head[s_tbl_req.data.dev_id]) : '0;
    assign alloc_cid = rsp_cid_C;
    assign s_tbl_req.ready = request_ready;
    assign next_sq_tail = (s_tbl_req.data.dev_id < MAX_NVME_DEVICES) ?
                         sq_tail[s_tbl_req.data.dev_id] + 1'b1 : '0;

    for (genvar d = 0; d < MAX_NVME_DEVICES; d++) begin : gen_cid_pool
        logic [NVME_QUEUE_BITS-1:0] free_fifo [CID_COUNT];
        logic [NVME_QUEUE_BITS-1:0] read_ptr, write_ptr, init_ptr;
        wire reset_device = s_update_tbl.valid && s_update_tbl.ready &&
            s_update_tbl.data.reset_queue && s_update_tbl.data.dev_id == N_NVME_BITS'(d);
        wire allocate_device = allocate && s_tbl_req.data.dev_id == N_NVME_BITS'(d);
        wire resolve_device = resolve_valid && resolve_dev == N_NVME_BITS'(d) &&
            sq_reserved[d] && reserved_cid[d] == resolve_cid;
        wire return_abort = resolve_device && resolve_abort;
        // cpl_valid is a retirement pulse, already validated against cid_live
        // by nvme_top. A CID must never be returned merely on an SQHD change.
        wire return_cpl = cpl_valid && cpl_dev == N_NVME_BITS'(d);
        wire fifo_pop = allocate_device && !recycled_valid[d];
        wire [NVME_QUEUE_BITS-1:0] next_read_ptr = read_ptr + 1'b1;

        // No array reset: initialize one word per clock, in parallel for all
        // devices. The pool is unavailable for CID_COUNT clocks after reset.
        always_ff @(posedge aclk) begin
            if (aresetn) begin
                if (!pool_ready[d]) free_fifo[init_ptr] <= init_ptr;
                else if (return_cpl) free_fifo[write_ptr] <= cpl_cid;
            end
        end

        always_ff @(posedge aclk) begin
            if (!aresetn || reset_device) begin
                pool_ready[d] <= 1'b0;
                init_ptr <= '0;
                read_ptr <= '0;
                write_ptr <= '0;
                free_count[d] <= '0;
                pool_head[d] <= '0;
                recycled_valid[d] <= 1'b0;
                recycled_cid[d] <= '0;
            end else if (!pool_ready[d]) begin
                init_ptr <= init_ptr + 1'b1;
                if (init_ptr == NVME_QUEUE_BITS'(CID_COUNT-1)) begin
                    pool_ready[d] <= 1'b1;
                    free_count[d] <= (NVME_QUEUE_BITS+1)'(CID_COUNT);
                end
            end else begin
                case ({return_cpl, fifo_pop})
                    2'b10: free_count[d] <= free_count[d] + 1'b1;
                    2'b01: free_count[d] <= free_count[d] - 1'b1;
                    default: ;
                endcase
                if (return_cpl) write_ptr <= write_ptr + 1'b1;
                if (fifo_pop) begin
                    read_ptr <= next_read_ptr;
                    if (free_count[d] > 1)
                        pool_head[d] <= free_fifo[next_read_ptr];
                    else if (return_cpl)
                        pool_head[d] <= cpl_cid;
                end else if (return_cpl && free_count[d] == 0)
                    pool_head[d] <= cpl_cid;
                if (allocate_device && recycled_valid[d]) recycled_valid[d] <= 1'b0;
                if (return_abort) begin
                    recycled_valid[d] <= 1'b1;
                    recycled_cid[d] <= resolve_cid;
                end
            end
        end

        // Local per-device SQ/reservation updates; no variable-index RMW path.
        always_ff @(posedge aclk) begin
            if (!aresetn || reset_device) begin
                sq_tail[d] <= '0;
                sq_head[d] <= '0;
                sq_reserved[d] <= 1'b0;
                reserved_cid[d] <= '0;
            end else begin
                if (return_cpl && cpl_sq_head < CID_COUNT)
                    sq_head[d] <= cpl_sq_head[NVME_QUEUE_BITS-1:0];
                if (resolve_device) begin
                    sq_reserved[d] <= 1'b0;
                    if (!resolve_abort) sq_tail[d] <= sq_tail[d] + 1'b1;
                end
                if (allocate_device) begin
                    sq_reserved[d] <= 1'b1;
                    reserved_cid[d] <= candidate_cid_C;
                end
            end
        end

`ifndef SYNTHESIS
        for (genvar c = 0; c < CID_COUNT; c++) begin : gen_owned_check
            always_ff @(posedge aclk) begin
                if (!aresetn || reset_device) cid_owned[d][c] <= 1'b0;
                else if (allocate_device && candidate_cid_C == NVME_QUEUE_BITS'(c))
                    cid_owned[d][c] <= 1'b1;
                else if ((return_cpl && cpl_cid == NVME_QUEUE_BITS'(c)) ||
                         (return_abort && resolve_cid == NVME_QUEUE_BITS'(c)))
                    cid_owned[d][c] <= 1'b0;
            end
        end
        always_ff @(posedge aclk) if (aresetn && pool_ready[d]) begin
            assert (int'(free_count[d]) + int'(recycled_valid[d]) + $countones(cid_owned[d]) == CID_COUNT)
                else $fatal(1, "CID pool conservation failed for device %0d", d);
            if (allocate_device) assert (!cid_owned[d][candidate_cid_C] && !sq_reserved[d])
                else $fatal(1, "CID double allocation");
            if (return_cpl) assert (cid_owned[d][cpl_cid] &&
                !(sq_reserved[d] && reserved_cid[d] == cpl_cid))
                else $fatal(1, "Completion returned an unowned/unpublished CID");
            if (return_abort) assert (cid_owned[d][resolve_cid] && !recycled_valid[d])
                else $fatal(1, "Abort cache overflow or invalid CID");
        end
`endif
    end

`ifndef SYNTHESIS
    initial begin
        assert (NVME_QUEUE_BITS >= 6 && NVME_QUEUE_BITS <= 8);
        assert (MAX_NVME_DEVICES >= 1 && MAX_NVME_DEVICES <= (1 << N_NVME_BITS));
    end
`endif

    integer i, j, k;

    // Combinational logic
    always_comb begin
        // Defaults
        s_update_tbl.ready     = 1'b0;
        s_perm_update.ready    = 1'b0;
        request_ready         = 1'b0;

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
        // Credit returns and reservation resolution below are independent of
        // this response slot, so stalled admission cannot block completions.
        if (rsp_free) begin
            if (s_update_tbl.valid) begin
                // Queue recreation is quiescent; SQHD alone cannot prove that
                // the SSD has finished reading a live command's PRP storage.
                // Inactive device writes are acknowledged and ignored.
                s_update_tbl.ready = 1'b1;
                if (s_update_tbl.data.dev_id < MAX_NVME_DEVICES && s_update_tbl.data.reset_queue)
                    s_update_tbl.ready = pool_ready[s_update_tbl.data.dev_id] &&
                        (free_count[s_update_tbl.data.dev_id] +
                         (NVME_QUEUE_BITS+1)'(recycled_valid[s_update_tbl.data.dev_id]) == CID_COUNT);
            end
            else if (s_perm_update.valid) begin
                s_perm_update.ready = 1'b1;
            end
            else if (s_tbl_req.valid) begin
                request_ready = 1'b1;

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
                else if (s_tbl_req.data.region_id >= N_REGIONS ||
                         !perm_table[s_tbl_req.data.region_id][s_tbl_req.data.dev_id].valid) begin
                    rsp_N.error = NVME_PERMISSION_DENIED;
                end
                // Permission check: offset + len within allowed range?
                else if ((s_tbl_req.data.naddr + s_tbl_req.data.len) >
                         perm_table[s_tbl_req.data.region_id][s_tbl_req.data.dev_id].lba_size) begin
                    rsp_N.error = NVME_PERMISSION_DENIED;
                end
                // Both an SQ slot and an independently owned CID are needed.
                else if (sq_reserved[s_tbl_req.data.dev_id] ||
                         next_sq_tail == sq_head[s_tbl_req.data.dev_id] ||
                         !candidate_valid_C) begin
                    request_ready = 1'b0;
                end
                // Success path
                else begin
                    rsp_N.error      = NVME_NO_ERROR;
                    rsp_N.dev_id     = s_tbl_req.data.dev_id;
                    rsp_N.nsid       = s_tbl_req.data.nsid;
                    rsp_N.lbaf       = nvme_info_tbl[s_tbl_req.data.dev_id][s_tbl_req.data.nsid].lbaf;
                    rsp_N.nsze       = nvme_info_tbl[s_tbl_req.data.dev_id][s_tbl_req.data.nsid].nsze;
                    rsp_N.sq_db_addr = nvme_info_tbl[s_tbl_req.data.dev_id][s_tbl_req.data.nsid].sq_db_addr;
                    rsp_N.sq_tail    = sq_tail[s_tbl_req.data.dev_id];
                    rsp_N.lba_offset = perm_table[s_tbl_req.data.region_id][s_tbl_req.data.dev_id].lba_offset;
                end

                // Emit a response only when the request was accepted; a
                // backpressured (SQ-full) request produces no response.
                rsp_valid_N = request_ready;
            end
        end
    end

    // Sequential logic
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            rsp_C       <= '0;
            rsp_valid_C <= 1'b0;
            rsp_cid_C   <= '0;

            for (i = 0; i < MAX_NVME_DEVICES; i++) begin
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
            if (s_update_tbl.valid && s_update_tbl.ready &&
                s_update_tbl.data.dev_id < MAX_NVME_DEVICES && s_update_tbl.data.nsid < MAX_NSID) begin
                nvme_info_tbl[s_update_tbl.data.dev_id][s_update_tbl.data.nsid].lbaf       <= s_update_tbl.data.lbaf;
                nvme_info_tbl[s_update_tbl.data.dev_id][s_update_tbl.data.nsid].nsze       <= s_update_tbl.data.nsze;
                nvme_info_tbl[s_update_tbl.data.dev_id][s_update_tbl.data.nsid].valid      <= s_update_tbl.data.valid;
                nvme_info_tbl[s_update_tbl.data.dev_id][s_update_tbl.data.nsid].sq_db_addr <= s_update_tbl.data.sq_db_addr;

            end
            // Update permission entry
            else if (s_perm_update.valid && s_perm_update.ready &&
                     s_perm_update.data.dev_id < MAX_NVME_DEVICES && s_perm_update.data.region_id < N_REGIONS) begin
                perm_table[s_perm_update.data.region_id][s_perm_update.data.dev_id].lba_offset <= s_perm_update.data.lba_offset;
                perm_table[s_perm_update.data.region_id][s_perm_update.data.dev_id].lba_size   <= s_perm_update.data.lba_size;
                perm_table[s_perm_update.data.region_id][s_perm_update.data.dev_id].valid      <= 1'b1;
            end
            if (allocate) rsp_cid_C <= candidate_cid_C;
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
        // Completion/SQ consumption, independent of CQ acknowledgement
        .probe11(cpl_valid),                            // 1
        .probe12(candidate_valid_C),                    // 1
        .probe13(cpl_dev),                              // N_NVME_BITS (4)
        .probe14(cpl_sq_head[NVME_QUEUE_BITS-1:0]),      // NVME_QUEUE_BITS (6)
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
