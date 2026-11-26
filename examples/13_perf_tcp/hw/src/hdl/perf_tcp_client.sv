/**
 * This file is part of Coyote <https://github.com/fpgasystems/Coyote>
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
 * perf_tcp_client
 * @brief TCP benchmark client: sends requests of pkg_word_count * 64 B on its sessions, in round robin
 *
 * SW writes the session IDs (from cThread::openConnTcp()) before the start. The first round sends a one-beat probe
 * of zeros per session, because an iperf2 server reads the first bytes of a connection as option flags. Then the
 * timer (clk_freq * duration cycles) starts, and the client sends until it expires. The shell splits and retries
 * the requests; completions and their errors are ignored.
 */
module perf_tcp_client (
    input  logic        aclk,
    input  logic        aresetn,

    // Control (perf_tcp_axi_ctrl_parser)
    input  logic        start_client,
    input  logic [15:0] n_sessions,
    input  logic [31:0] pkg_word_count,
    input  logic [31:0] clk_freq,
    input  logic [31:0] duration,
    output logic [3:0]  client_state,

    input  logic        sess_id_valid,
    output logic        sess_id_ready,
    input  logic [15:0] sess_id_data,

    // TCP TX
    metaIntf.m          sq_wr,
    metaIntf.s          cq_wr,
    AXI4SR.m            axis_tcp_send
);

localparam integer SID_BITS = 10; // up to 1024 sessions, the TOE's limit

typedef enum logic [3:0] {ST_IDLE = 0, ST_REQ = 1, ST_DATA = 2} state_t;
state_t state_C, state_N;

logic [15:0]         sid_ram [2**SID_BITS];
logic [SID_BITS-1:0] n_ids_C;        // session IDs written since the last run
logic [15:0]         sid_C;

logic [15:0] idx_C, idx_N;           // session of the current request
logic        first_C, first_N;       // first round: one probe per session
logic [31:0] cnt_C, cnt_N;           // beats left - 1
logic [31:0] cyc_C, sec_C;           // timer: cycles in the current second, seconds
logic        expired;

assign sess_id_ready = 1'b1;
assign client_state  = state_C;
assign cq_wr.ready   = 1'b1;
assign expired       = !first_C && (sec_C >= duration);

always_ff @(posedge aclk) begin
    if (sess_id_valid) sid_ram[n_ids_C] <= sess_id_data;
    sid_C <= sid_ram[idx_N[SID_BITS-1:0]];
end

always_ff @(posedge aclk) begin
    if (!aresetn) begin
        state_C <= ST_IDLE;
        n_ids_C <= '0;
        idx_C   <= 'X;
        first_C <= 'X;
        cnt_C   <= 'X;
        cyc_C   <= 'X;
        sec_C   <= 'X;
    end else begin
        state_C <= state_N;
        idx_C   <= idx_N;
        first_C <= first_N;
        cnt_C   <= cnt_N;
        n_ids_C <= (state_C == ST_DATA && state_N == ST_IDLE) ? '0 : n_ids_C + sess_id_valid;

        // The timer runs once the first round is done
        cyc_C <= (first_C || (cyc_C == clk_freq - 1)) ? '0 : cyc_C + 1;
        sec_C <= first_C ? '0 : sec_C + (cyc_C == clk_freq - 1);
    end
end

always_comb begin
    state_N = state_C;
    idx_N   = idx_C;
    first_N = first_C;
    cnt_N   = cnt_C;

    sq_wr.valid     = (state_C == ST_REQ);
    sq_wr.data      = '0;
    sq_wr.data.strm = STRM_TCP;
    sq_wr.data.sid  = sid_C;
    sq_wr.data.len  = first_C ? 64 : pkg_word_count * 64;
    sq_wr.data.last = 1'b1;

    axis_tcp_send.tvalid = (state_C == ST_DATA);
    axis_tcp_send.tdata  = first_C ? '0 : {(AXI_DATA_BITS/64){64'h3736353433323130}};
    axis_tcp_send.tkeep  = '1;
    axis_tcp_send.tlast  = (cnt_C == 0);
    axis_tcp_send.tid    = '0;

    case (state_C)
        ST_IDLE: begin
            if (start_client && n_sessions != 0) begin
                idx_N   = 0;
                first_N = 1'b1;
                state_N = ST_REQ;
            end
        end

        ST_REQ: begin
            if (sq_wr.ready) begin
                cnt_N   = first_C ? 0 : pkg_word_count - 1;
                state_N = ST_DATA;
            end
        end

        ST_DATA: begin
            if (axis_tcp_send.tready) begin
                cnt_N = cnt_C - 1;
                if (cnt_C == 0) begin
                    idx_N   = (idx_C == n_sessions - 1) ? 0 : idx_C + 1;
                    first_N = first_C && (idx_C != n_sessions - 1);
                    state_N = expired ? ST_IDLE : ST_REQ;
                end
            end
        end

        default: state_N = ST_IDLE;
    endcase
end

endmodule
