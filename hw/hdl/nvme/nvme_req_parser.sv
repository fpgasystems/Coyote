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
 * @brief   NVMe request parser
 *
 * Parses the user request into an info-table lookup and forwards the command.
 */
module nvme_req_parser (
    input  logic        aclk,
    input  logic        aresetn,

    metaIntf.s          s_nvme_user_req,   // req_t (strm=STRM_NVME)
    metaIntf.m          m_nvme_info_req,   // nvme_info_req_t
    metaIntf.m          m_nvme_cmd_parsed      // req_t (passthrough)
);

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_SEND_TBL,
        ST_SEND_CMD
    } state_t;

    state_t  state_C, state_N;
    req_t    cmd_C, cmd_N;

    // Temporaries
    nvme_info_req_t tbl_req;

    always_comb begin
        // Defaults
        state_N = state_C;
        cmd_N   = cmd_C;

        s_nvme_user_req.ready = 1'b0;

        m_nvme_info_req.valid = 1'b0;
        m_nvme_info_req.data  = '0;

        m_nvme_cmd_parsed.valid   = 1'b0;
        m_nvme_cmd_parsed.data    = '0;

        tbl_req = '0;

        case (state_C)
            // ST_IDLE: Accept user request
            ST_IDLE: begin
                s_nvme_user_req.ready = 1'b1;
                if (s_nvme_user_req.valid) begin
                    cmd_N   = s_nvme_user_req.data;
                    state_N = ST_SEND_TBL;
                end
            end

            // ST_SEND_TBL: Send table lookup request
            ST_SEND_TBL: begin
                tbl_req.dev_id    = cmd_C.dev_id;
                tbl_req.nsid      = cmd_C.nsid;
                tbl_req.region_id = cmd_C.vfid[REGION_ID_BITS-1:0];
                tbl_req.naddr     = cmd_C.naddr;
                tbl_req.len       = cmd_C.len;

                m_nvme_info_req.valid = 1'b1;
                m_nvme_info_req.data  = tbl_req;

                if (m_nvme_info_req.ready) begin
                    state_N = ST_SEND_CMD;
                end
            end

            // ST_SEND_CMD: Forward entire command to next stage
            ST_SEND_CMD: begin
                m_nvme_cmd_parsed.valid = 1'b1;
                m_nvme_cmd_parsed.data  = cmd_C;

                if (m_nvme_cmd_parsed.ready) begin
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
            state_C <= ST_IDLE;
            cmd_C   <= '0;
        end
        else begin
            state_C <= state_N;
            cmd_C   <= cmd_N;
        end
    end

    // ILA Debug
// `define EN_ILA_NVME_S0
`ifdef EN_ILA_NVME_S0
    ila_nvme_s0 inst_ila_nvme_s0 (
        .clk    (aclk),
        .probe0 (s_nvme_user_req.valid),                // 1
        .probe1 (s_nvme_user_req.ready),                // 1
        .probe2 (m_nvme_info_req.valid),                // 1
        .probe3 (m_nvme_info_req.ready),                // 1
        .probe4 (m_nvme_info_req.data.dev_id),          // N_NVME_BITS (4)
        .probe5 (m_nvme_info_req.data.region_id),       // REGION_ID_BITS
        .probe6 (m_nvme_cmd_parsed.valid),                  // 1
        .probe7 (m_nvme_cmd_parsed.ready),                  // 1
        .probe8 (state_C)                               // 2
    );
`endif

endmodule
