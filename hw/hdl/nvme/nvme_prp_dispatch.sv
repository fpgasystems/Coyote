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
 * @brief   NVMe PRP dispatch
 *
 * Combines the parsed command with the info-table response. Lookup failures
 * follow the command stream so the SQE builder returns all responses in order.
 */
module nvme_prp_dispatch (
    input  logic        aclk,
    input  logic        aresetn,

    metaIntf.s          s_nvme_cmd_parsed,     // req_t
    metaIntf.s          s_nvme_info_rsp,   // nvme_info_rsp_t
    input logic [NVME_QUEUE_BITS-1:0] s_alloc_cid,
    output logic [NVME_QUEUE_BITS-1:0] m_cmd_cid,
    output logic [15:0] m_cmd_error,

    metaIntf.m          m_nvme_prp_req,    // nvme_prp_req_t
    metaIntf.m          m_nvme_cmd_dispatched      // nvme_cmd_dispatched_t
);

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_WAIT_INFO_RSP,
        ST_SEND_CMD_ERROR,
        ST_SEND_PRP_CMD
    } state_t;

    state_t          state_C, state_N;
    req_t  cmd_C, cmd_N;
    nvme_info_rsp_t  info_rsp_C, info_rsp_N;
    logic [NVME_QUEUE_BITS-1:0] cid_C;
    assign m_cmd_cid = cid_C;
    assign m_cmd_error = info_rsp_C.error;
    always_ff @(posedge aclk) begin
        if (!aresetn) cid_C <= '0;
        else if (s_nvme_info_rsp.valid && s_nvme_info_rsp.ready)
            cid_C <= (s_nvme_info_rsp.data.error == NVME_NO_ERROR) ? s_alloc_cid : '0;
    end

    // Fired registers: track which outputs have been accepted
    // in ST_SEND_PRP_CMD (dual handshake)
    logic prp_fired_C, prp_fired_N;
    logic cmd_fired_C, cmd_fired_N;

    // Temporaries (declared at module scope)
    nvme_prp_req_t   prp_req;
    nvme_cmd_dispatched_t    cmd_dispatched;

    // LBA-format shift exponent (4-bit)
    logic [3:0]      lbaf_shift;
    assign s_nvme_cmd_parsed.ready = (state_C == ST_IDLE);
    assign s_nvme_info_rsp.ready = (state_C == ST_WAIT_INFO_RSP);
    assign m_nvme_prp_req.valid = (state_C == ST_SEND_PRP_CMD) && !prp_fired_C;
    assign m_nvme_cmd_dispatched.valid = (state_C == ST_SEND_CMD_ERROR) ||
                                         ((state_C == ST_SEND_PRP_CMD) && !cmd_fired_C);

    always_comb begin
        // Defaults
        state_N     = state_C;
        cmd_N       = cmd_C;
        info_rsp_N  = info_rsp_C;
        prp_fired_N = prp_fired_C;
        cmd_fired_N = cmd_fired_C;

        m_nvme_prp_req.data   = '0;

        m_nvme_cmd_dispatched.data    = '0;

        prp_req    = '0;
        cmd_dispatched     = '0;
        lbaf_shift = '0;

        case (state_C)
            // State 1: Accept user command
            ST_IDLE: begin
                if (s_nvme_cmd_parsed.valid) begin
                    cmd_N   = s_nvme_cmd_parsed.data;
                    state_N = ST_WAIT_INFO_RSP;
                end
            end

            // State 2: Wait for and receive info table response
            ST_WAIT_INFO_RSP: begin
                if (s_nvme_info_rsp.valid) begin
                    info_rsp_N = s_nvme_info_rsp.data;
                    if (s_nvme_info_rsp.data.error != NVME_NO_ERROR) begin
                        state_N = ST_SEND_CMD_ERROR;
                    end
                    else begin
                        state_N     = ST_SEND_PRP_CMD;
                        prp_fired_N = 1'b0;
                        cmd_fired_N = 1'b0;
                    end
                end
            end

            // A rejected lookup owns no CID and issues no PRP request. It still
            // occupies its place in the ordered command/response stream.
            ST_SEND_CMD_ERROR: begin
                m_nvme_cmd_dispatched.data.vfid = cmd_C.vfid[N_REGIONS_BITS-1:0];
                m_nvme_cmd_dispatched.data.dev_id = cmd_C.dev_id;
                if (m_nvme_cmd_dispatched.ready) begin
                    state_N = ST_IDLE;
                end
            end

            // State 4: send PRP request and cmd_dispatched (success path only).
            // Each output is presented until accepted; transitions to ST_IDLE
            // once both have been accepted.
            ST_SEND_PRP_CMD: begin
                // Constrain shift amount to 4 bits
                lbaf_shift = info_rsp_C.lbaf[3:0];

                // Build PRP req
                prp_req           = '0;
                prp_req.vaddr     = cmd_C.vaddr;
                prp_req.len       = cmd_C.len;
                prp_req.dev_id    = cmd_C.dev_id;
                // Historical field name: PRP storage now belongs to CID,
                // independently of the command's physical SQ slot below.
                prp_req.sq_tail   = cid_C;
                prp_req.vfid      = cmd_C.vfid[N_REGIONS_BITS-1:0];
                prp_req.writeRead = cmd_C.writeRead;

                // Build cmd_dispatched
                cmd_dispatched            = '0;
                cmd_dispatched.writeRead  = cmd_C.writeRead;
                cmd_dispatched.dev_id     = cmd_C.dev_id;
                cmd_dispatched.nsid       = cmd_C.nsid;
                cmd_dispatched.sq_tail    = info_rsp_C.sq_tail;
                cmd_dispatched.sq_db_addr = info_rsp_C.sq_db_addr;
                cmd_dispatched.slba       = (info_rsp_C.lba_offset + cmd_C.naddr) >> lbaf_shift;
                cmd_dispatched.nlba       = (cmd_C.len >> lbaf_shift) - 1'b1;
                cmd_dispatched.vfid       = cmd_C.vfid[N_REGIONS_BITS-1:0];

                // Present prp_req until accepted
                m_nvme_prp_req.data  = prp_req;

                // Present cmd_dispatched until accepted
                m_nvme_cmd_dispatched.data   = cmd_dispatched;

                // Track acceptance
                if (~prp_fired_C && m_nvme_prp_req.ready)
                    prp_fired_N = 1'b1;
                if (~cmd_fired_C && m_nvme_cmd_dispatched.ready)
                    cmd_fired_N = 1'b1;

                // Both accepted (either this cycle or previously)?
                if ((prp_fired_C || (~prp_fired_C && m_nvme_prp_req.ready)) &&
                    (cmd_fired_C || (~cmd_fired_C && m_nvme_cmd_dispatched.ready))) begin
                    state_N     = ST_IDLE;
                    prp_fired_N = 1'b0;
                    cmd_fired_N = 1'b0;
                end
            end

            default: begin
                state_N = ST_IDLE;
            end
        endcase
    end

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            state_C     <= ST_IDLE;
            cmd_C       <= '0;
            info_rsp_C  <= '0;
            prp_fired_C <= 1'b0;
            cmd_fired_C <= 1'b0;
        end
        else begin
            state_C     <= state_N;
            cmd_C       <= cmd_N;
            info_rsp_C  <= info_rsp_N;
            prp_fired_C <= prp_fired_N;
            cmd_fired_C <= cmd_fired_N;
        end
    end

    // ILA Debug
// `define EN_ILA_NVME_S1
`ifdef EN_ILA_NVME_S1
    ila_nvme_s1 inst_ila_nvme_s1 (
        .clk    (aclk),
        .probe0 (s_nvme_cmd_parsed.valid),                  // 1
        .probe1 (s_nvme_cmd_parsed.ready),                  // 1
        .probe2 (s_nvme_info_rsp.valid),                // 1
        .probe3 (s_nvme_info_rsp.ready),                // 1
        .probe4 (s_nvme_info_rsp.data.error),           // 16
        .probe5 (s_nvme_info_rsp.data.lba_offset),      // 64
        .probe6 (m_nvme_cmd_dispatched.valid && (m_cmd_error != 0)), // rejected command VALID
        .probe7 (m_nvme_cmd_dispatched.ready),          // command READY (1)
        .probe8 (m_cmd_error),                         // local lookup error (16)
        .probe9 (m_nvme_prp_req.valid),                 // 1
        .probe10(m_nvme_prp_req.ready),                 // 1
        .probe11(m_nvme_cmd_dispatched.valid),                  // 1
        .probe12(m_nvme_cmd_dispatched.ready),                  // 1
        .probe13(m_nvme_cmd_dispatched.data.slba),              // 64
        .probe14(state_C),                              // 3
        .probe15(prp_fired_C),                          // 1
        .probe16(cmd_fired_C)                           // 1
    );
`endif

endmodule
