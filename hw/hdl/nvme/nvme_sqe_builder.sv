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
 * SQ doorbell request. Emits one ordered assignment/error response per command.
 */
module nvme_sqe_builder (
    input  logic        aclk,
    input  logic        aresetn,

    metaIntf.s          s_nvme_cmd_dispatched,   // nvme_cmd_dispatched_t
    metaIntf.s          s_nvme_prp_rsp,  // nvme_prp_rsp_t
    input logic [NVME_QUEUE_BITS-1:0] s_cmd_cid,
    input logic [15:0] s_cmd_error,
    input logic s_prp_fault,
    output logic [NVME_QUEUE_BITS-1:0] m_sqe_cid,
    output logic abort_valid,
    output logic [N_NVME_BITS-1:0] abort_dev,
    metaIntf.m          m_nvme_user_rsp, // packed assignment/error in the existing 16-bit field

    metaIntf.m          m_nvme_cmd_sqe,   // nvme_sqe_t
    metaIntf.m          m_sq_db_req      // sq_db_req_t
);

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_WAIT_PRP_RSP,
        ST_SEND_CMD_S2,
        ST_SEND_DB,
        ST_SEND_RSP
    } state_t;

    state_t        state_C, state_N;
    nvme_cmd_dispatched_t  cmd_C, cmd_N;
    nvme_prp_rsp_t prp_rsp_C, prp_rsp_N;
    logic [NVME_QUEUE_BITS-1:0] cid_C;
    logic [15:0] error_C, error_N;
    logic abort_C, abort_N;
    assign m_sqe_cid = cid_C;
    assign abort_dev = cmd_C.dev_id;
    assign abort_valid = m_nvme_user_rsp.valid && m_nvme_user_rsp.ready && abort_C;
    always_ff @(posedge aclk) begin
        if (!aresetn) cid_C <= '0;
        else if (s_nvme_cmd_dispatched.valid && s_nvme_cmd_dispatched.ready) cid_C <= s_cmd_cid;
    end

    // Temporaries
    nvme_sqe_t  cmd_sqe;
    assign s_nvme_cmd_dispatched.ready = (state_C == ST_IDLE);
    assign s_nvme_prp_rsp.ready = (state_C == ST_WAIT_PRP_RSP);
    assign m_sq_db_req.valid = (state_C == ST_SEND_DB);
    assign m_sq_db_req.data.sq_db_addr = cmd_C.sq_db_addr;
    assign m_sq_db_req.data.sq_tail = cmd_C.sq_tail + 1'b1;
    assign m_nvme_user_rsp.valid = (state_C == ST_SEND_RSP);
    assign m_nvme_user_rsp.data.vfid = cmd_C.vfid;
    assign m_nvme_user_rsp.data.dev_id = cmd_C.dev_id;
    // Preserve shared types/ports: the historical error field carries
    // {device[15:12], CID[11:4], error[3:0]} at every queue depth. The CID is
    // zero-extended to 8 bits and valid only on success.
    assign m_nvme_user_rsp.data.error =
        {cmd_C.dev_id,
         ((error_C == 0) ? NVME_RSP_CID_BITS'(cid_C) : {NVME_RSP_CID_BITS{1'b0}}),
         error_C[NVME_RSP_ERROR_BITS-1:0]};

`ifndef SYNTHESIS
    initial assert (N_NVME_BITS == 4 && NVME_RSP_CID_BITS == 8 && NVME_RSP_ERROR_BITS == 4 &&
                    NVME_QUEUE_BITS >= 6 && NVME_QUEUE_BITS <= NVME_RSP_CID_BITS)
        else $fatal(1, "NVMe assignment response requires 4-bit device, 8-bit CID and 4-bit error fields");
    always @(posedge aclk)
        if (aresetn && m_nvme_user_rsp.valid)
            assert (error_C[15:NVME_RSP_ERROR_BITS] == 0)
                else $fatal(1, "NVMe local error does not fit the response field");
`endif

    always_comb begin
        // Defaults
        state_N   = state_C;
        cmd_N     = cmd_C;
        prp_rsp_N = prp_rsp_C;
        error_N   = error_C;
        abort_N   = abort_C;

        m_nvme_cmd_sqe.valid  = 1'b0;
        m_nvme_cmd_sqe.data   = '0;

        cmd_sqe = '0;

        case (state_C)
            // ST_IDLE: Accept cmd_dispatched
            ST_IDLE: begin
                if (s_nvme_cmd_dispatched.valid) begin
                    cmd_N   = s_nvme_cmd_dispatched.data;
                    error_N = s_cmd_error;
                    abort_N = 1'b0;
                    state_N = (s_cmd_error == 0) ? ST_WAIT_PRP_RSP : ST_SEND_RSP;
                end
            end

            // ST_WAIT_PRP_RSP: Wait for and receive PRP response
            ST_WAIT_PRP_RSP: begin
                if (s_nvme_prp_rsp.valid) begin
                    prp_rsp_N = s_nvme_prp_rsp.data;
                    state_N   = s_prp_fault ? ST_SEND_RSP : ST_SEND_CMD_S2;
                    if (s_prp_fault) begin
                        error_N = 16'h0003;
                        abort_N = 1'b1;
                    end
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
                    state_N = ST_SEND_RSP;
                end
            end

            // Publish the assignment to the existing response FIFO before
            // doorbelling the SQE. User response/completion drains are independent.
            ST_SEND_RSP: begin
                if (m_nvme_user_rsp.ready)
                    state_N = (error_C == 0) ? ST_SEND_DB : ST_IDLE;
            end

            // ST_SEND_DB: Send doorbell request
            ST_SEND_DB: begin
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
            error_C   <= '0;
            abort_C   <= 1'b0;
        end
        else begin
            state_C   <= state_N;
            cmd_C     <= cmd_N;
            prp_rsp_C <= prp_rsp_N;
            error_C   <= error_N;
            abort_C   <= abort_N;
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
        .probe12(state_C)                               // 3
    );
`endif

endmodule
