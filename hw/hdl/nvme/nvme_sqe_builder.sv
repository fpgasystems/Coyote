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
 * @brief   NVMe SQE builder
 *
 * Combines the dispatched command with the PRP response into the SQE and the
 * SQ doorbell request.
 */
module nvme_sqe_builder (
    input  logic        aclk,
    input  logic        aresetn,

    metaIntf.s          s_nvme_cmd_dispatched,   // nvme_cmd_dispatched_t
    metaIntf.s          s_nvme_prp_rsp,  // nvme_prp_rsp_t

    metaIntf.m          m_nvme_cmd_sqe,   // nvme_sqe_t
    metaIntf.m          m_sq_db_req      // sq_db_req_t
);

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_WAIT_PRP_RSP,
        ST_SEND_CMD_S2,
        ST_SEND_DB
    } state_t;

    state_t        state_C, state_N;
    nvme_cmd_dispatched_t  cmd_C, cmd_N;
    nvme_prp_rsp_t prp_rsp_C, prp_rsp_N;

    // Temporaries
    nvme_sqe_t  cmd_sqe;
    sq_db_req_t    db_req;

    always_comb begin
        // Defaults
        state_N   = state_C;
        cmd_N     = cmd_C;
        prp_rsp_N = prp_rsp_C;

        s_nvme_cmd_dispatched.ready  = 1'b0;
        s_nvme_prp_rsp.ready = 1'b0;

        m_nvme_cmd_sqe.valid  = 1'b0;
        m_nvme_cmd_sqe.data   = '0;

        m_sq_db_req.valid    = 1'b0;
        m_sq_db_req.data     = '0;

        cmd_sqe = '0;
        db_req = '0;

        case (state_C)
            // ST_IDLE: Accept cmd_dispatched
            ST_IDLE: begin
                s_nvme_cmd_dispatched.ready = 1'b1;
                if (s_nvme_cmd_dispatched.valid) begin
                    cmd_N   = s_nvme_cmd_dispatched.data;
                    state_N = ST_WAIT_PRP_RSP;
                end
            end

            // ST_WAIT_PRP_RSP: Wait for and receive PRP response
            ST_WAIT_PRP_RSP: begin
                s_nvme_prp_rsp.ready = 1'b1;
                if (s_nvme_prp_rsp.valid) begin
                    prp_rsp_N = s_nvme_prp_rsp.data;
                    state_N   = ST_SEND_CMD_S2;
                end
            end

            // ST_SEND_CMD_S2: Send cmd_sqe (SQE payload)
            ST_SEND_CMD_S2: begin
                // Build cmd_sqe
                cmd_sqe.writeRead = cmd_C.writeRead;
                cmd_sqe.dev_id    = cmd_C.dev_id;
                cmd_sqe.nsid      = cmd_C.nsid;
                cmd_sqe.slba      = cmd_C.slba;
                cmd_sqe.nlba      = cmd_C.nlba;
                cmd_sqe.prp1      = prp_rsp_C.prp1;
                cmd_sqe.prp2      = prp_rsp_C.prp2;
                cmd_sqe.entry     = {cmd_C.dev_id, cmd_C.sq_tail};

                m_nvme_cmd_sqe.valid = 1'b1;
                m_nvme_cmd_sqe.data  = cmd_sqe;

                if (m_nvme_cmd_sqe.ready) begin
                    state_N = ST_SEND_DB;
                end
            end

            // ST_SEND_DB: Send doorbell request
            ST_SEND_DB: begin
                db_req.sq_db_addr = cmd_C.sq_db_addr;
                db_req.sq_tail = cmd_C.sq_tail + 1'b1;

                m_sq_db_req.valid = 1'b1;
                m_sq_db_req.data  = db_req;

                if (m_sq_db_req.ready) begin
                    state_N = ST_IDLE;
                end
            end

            default: begin
                state_N = ST_IDLE;
            end
        endcase
    end

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            state_C   <= ST_IDLE;
            cmd_C     <= '0;
            prp_rsp_C <= '0;
        end
        else begin
            state_C   <= state_N;
            cmd_C     <= cmd_N;
            prp_rsp_C <= prp_rsp_N;
        end
    end

    // ILA Debug
// `define EN_ILA_NVME_S2
`ifdef EN_ILA_NVME_S2
    ila_nvme_s2 inst_ila_nvme_s2 (
        .clk    (aclk),
        .probe0 (s_nvme_cmd_dispatched.valid),                  // 1
        .probe1 (s_nvme_cmd_dispatched.ready),                  // 1
        .probe2 (s_nvme_prp_rsp.valid),                 // 1
        .probe3 (s_nvme_prp_rsp.ready),                 // 1
        .probe4 (m_nvme_cmd_sqe.valid),                  // 1
        .probe5 (m_nvme_cmd_sqe.ready),                  // 1
        .probe6 (m_nvme_cmd_sqe.data.dev_id),            // N_NVME_BITS (4)
        .probe7 (m_nvme_cmd_sqe.data.slba),              // 64
        .probe8 (m_nvme_cmd_sqe.data.nlba),              // 16
        .probe9 (m_sq_db_req.valid),                    // 1
        .probe10(m_sq_db_req.ready),                    // 1
        .probe11(m_sq_db_req.data.sq_db_addr),             // 64
        .probe12(state_C)                               // 2
    );
`endif

endmodule
