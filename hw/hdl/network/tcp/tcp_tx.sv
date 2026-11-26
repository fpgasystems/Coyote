/**
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

`timescale 1ns / 1ps

import lynxTypes::*;

/**
 * @brief   TCP TX: sends the vFPGAs' chunks to the TOE
 *
 * Each vFPGA has one head chunk. The request FSM picks a head in round robin, checks it (len != 0, sid owned by
 * the vFPGA) and sends one meta at a time to the TOE. On NOSPACE the chunk stays and its next meta is cut to the
 * space the TOE reported, and the round robin moves on. Each sent or dropped part goes into the send queue; the
 * data FSM moves its beats with its own tlast and tkeep, so the next meta overlaps the previous data. A completion
 * (last = 1) follows the chunk's last beat into the vFPGA's completion queue; a vFPGA is only picked while that
 * queue has room for all its completions in flight. The rules for sq_wr are in docs/agents/services/network.md.
 */
module tcp_tx #(
    parameter integer CQ_DEPTH   = 8,
    parameter integer SEND_DEPTH = 4
) (
    input  logic                        aclk,
    input  logic                        aresetn,

    // TOE
    metaIntf.m                          m_tx_meta,
    metaIntf.s                          s_tx_stat,
    AXI4S.m                             m_axis_tx,

    // Owner lookup (tcp_conn_table)
    output logic [TCP_SESSION_BITS-1:0] lup_sid,
    input  logic                        lup_valid,
    input  logic [N_REGIONS_BITS-1:0]   lup_vfid,

    // vFPGAs
    metaIntf.s                          s_sq_wr [N_REGIONS],
    metaIntf.m                          m_cq_wr [N_REGIONS],
    AXI4S.s                             s_axis_tx [N_REGIONS]
);

localparam integer TX_NO_ERROR = 0;
localparam integer TX_NOSPACE  = 2;

// Send queue entry: len bytes of a vFPGA's stream, sent to the TOE or dropped, then an optional completion
typedef struct packed {
    logic [N_REGIONS_BITS-1:0] vfid;
    logic [TCP_LEN_BITS-1:0]   len;
    logic                      drop;
    logic                      cq;
    ack_t                      ack;
} send_t;

typedef enum logic [2:0] {S_IDLE, S_LOOKUP, S_LOOKUP_2, S_CHECK, S_META, S_STATUS} state_t;

// Head chunk per vFPGA
logic [N_REGIONS-1:0]          head_vld;
req_t                          head      [N_REGIONS];
logic [TCP_LEN_BITS-1:0]       head_left [N_REGIONS]; // bytes not sent yet
logic [TCP_LEN_BITS-1:0]       head_next [N_REGIONS]; // bytes for the next meta
logic [$clog2(CQ_DEPTH+1)-1:0] cq_cnt    [N_REGIONS]; // completions queued or in flight
logic [N_REGIONS-1:0]          eligible;

// vFPGA interface signals
logic [N_REGIONS-1:0]                   sq_valid, cq_pop, cq_push, tx_valid, tx_ready;
req_t                                   sq_data [N_REGIONS];
logic [N_REGIONS-1:0][AXI_NET_BITS-1:0] tx_data;

// Request FSM
state_t                        state_C, state_N;
logic [N_REGIONS_BITS-1:0]     sel_C, sel_N;        // selected vFPGA
logic [N_REGIONS_BITS-1:0]     rr_C, rr_N;          // first vFPGA to try next
logic [3:0]                    err;                 // error of the dropped chunk
logic                          pick_vld;
logic [N_REGIONS_BITS-1:0]     pick;
req_t                          sel_head;
logic [TCP_LEN_BITS-1:0]       sel_left, sel_next, left_N, next_N;
logic [TCP_REM_SPACE_BITS-1:0] space;               // remaining space reported by the TOE, in whole beats
logic                          head_upd, head_done, cq_book;

// Send queue and data FSM
logic                    send_in_vld, send_in_rdy, send_out_vld, send_out_rdy;
send_t                   send_in, send_out;
logic                    cur_vld_C;                 // an entry is being moved
send_t                   cur_C;
logic [TCP_LEN_BITS-1:0] beats_C;                   // beats left - 1
logic                    has_data, beat, cur_done;

// ---------------------------------------------------------------------------------------------------
// vFPGAs: head chunk and completion queue
// ---------------------------------------------------------------------------------------------------
for (genvar i = 0; i < N_REGIONS; i++) begin : GEN_REGION
    assign s_sq_wr[i].ready = !head_vld[i];
    assign sq_valid[i]      = s_sq_wr[i].valid;
    assign sq_data[i]       = s_sq_wr[i].data;
    assign eligible[i]      = head_vld[i] && (cq_cnt[i] < CQ_DEPTH);

    // Never full: see eligible
    assign cq_push[i] = cur_done && cur_C.cq && (cur_C.vfid == i);
    assign cq_pop[i]  = m_cq_wr[i].valid && m_cq_wr[i].ready;

    queue_stream #(
        .QTYPE(ack_t),
        .QDEPTH(CQ_DEPTH)
    ) inst_cq_q (
        .aclk(aclk),
        .aresetn(aresetn),
        .val_snk(cq_push[i]),
        .rdy_snk(),
        .data_snk(cur_C.ack),
        .val_src(m_cq_wr[i].valid),
        .rdy_src(m_cq_wr[i].ready),
        .data_src(m_cq_wr[i].data)
    );

    assign tx_valid[i]         = s_axis_tx[i].tvalid;
    assign tx_data[i]          = s_axis_tx[i].tdata;
    assign s_axis_tx[i].tready = tx_ready[i];
end

always_ff @(posedge aclk) begin
    for (int i = 0; i < N_REGIONS; i++) begin
        if (!aresetn) begin
            head_vld[i]  <= 1'b0;
            head[i]      <= 'X;
            head_left[i] <= 'X;
            head_next[i] <= 'X;
            cq_cnt[i]    <= '0;
        end else begin
            if (!head_vld[i]) begin
                head_vld[i]  <= sq_valid[i];
                head[i]      <= sq_data[i];
                head_left[i] <= sq_data[i].len;
                head_next[i] <= sq_data[i].len;
            end else if (sel_C == i) begin
                if (head_done) head_vld[i] <= 1'b0;
                if (head_upd) begin
                    head_left[i] <= left_N;
                    head_next[i] <= next_N;
                end
            end
            cq_cnt[i] <= cq_cnt[i] + (cq_book && (sel_C == i)) - cq_pop[i];
        end
    end
end

// ---------------------------------------------------------------------------------------------------
// Request FSM: one chunk at a time, one meta at a time at the TOE
// ---------------------------------------------------------------------------------------------------
assign sel_head = head[sel_C];
assign sel_left = head_left[sel_C];
assign sel_next = head_next[sel_C];
assign space    = {s_tx_stat.data.remaining_space[TCP_REM_SPACE_BITS-1:BEAT_LOG_BITS], {BEAT_LOG_BITS{1'b0}}};
assign lup_sid  = sel_head.sid;

// Round robin over the eligible vFPGAs, starting at rr_C
always_comb begin
    pick_vld = 1'b0;
    pick     = '0;
    for (int k = N_REGIONS-1; k >= 0; k--) begin
        int idx;
        idx = rr_C + k;
        if (idx >= N_REGIONS) idx = idx - N_REGIONS;
        if (eligible[idx]) begin
            pick_vld = 1'b1;
            pick     = idx;
        end
    end
end

always_ff @(posedge aclk) begin
    if (!aresetn) begin
        state_C <= S_IDLE;
        sel_C   <= '0;
        rr_C    <= '0;
    end else begin
        state_C <= state_N;
        sel_C   <= sel_N;
        rr_C    <= rr_N;
    end
end

always_comb begin
    state_N = state_C;
    sel_N   = sel_C;
    rr_N    = rr_C;
    err     = 0;

    head_upd  = 1'b0;
    head_done = 1'b0;
    cq_book   = 1'b0;
    left_N    = sel_left - sel_next;
    next_N    = sel_left - sel_next;

    m_tx_meta.valid    = (state_C == S_META);
    m_tx_meta.data     = '0;
    m_tx_meta.data.sid = sel_head.sid;
    m_tx_meta.data.len = sel_next;
    s_tx_stat.ready    = 1'b0;

    // Default entry: drop the rest of the chunk
    send_in_vld        = 1'b0;
    send_in.vfid       = sel_C;
    send_in.len        = sel_left;
    send_in.drop       = 1'b1;
    send_in.cq         = sel_head.last;
    send_in.ack        = '0;
    send_in.ack.opcode = sel_head.opcode;
    send_in.ack.strm   = sel_head.strm;
    send_in.ack.host   = sel_head.host;
    send_in.ack.dest   = sel_head.dest;
    send_in.ack.pid    = sel_head.pid;
    send_in.ack.vfid   = sel_head.vfid;

    case (state_C)
        S_IDLE: begin
            if (pick_vld) begin
                sel_N   = pick;
                rr_N    = (pick == N_REGIONS-1) ? 0 : pick + 1;
                state_N = S_LOOKUP;
            end
        end

        // Owner lookup, two cycles
        S_LOOKUP:   state_N = S_LOOKUP_2;
        S_LOOKUP_2: state_N = S_CHECK;

        S_CHECK: begin
            if ((sel_head.len == 0) || !lup_valid || (lup_vfid != sel_C)) begin
                err         = (sel_head.len == 0) ? TCP_ERR_BAD_REQ : TCP_ERR_NOT_OWNER;
                send_in_vld = 1'b1;
                if (send_in_rdy) begin
                    head_done = 1'b1;
                    cq_book   = sel_head.last;
                    state_N   = S_IDLE;
                end
            end else begin
                state_N = S_META;
            end
        end

        S_META: begin
            if (m_tx_meta.ready) state_N = S_STATUS;
        end

        S_STATUS: begin
            if (s_tx_stat.valid) begin
                if (s_tx_stat.data.error == TX_NO_ERROR) begin
                    // Accepted: send head_next bytes
                    send_in_vld     = 1'b1;
                    send_in.len     = sel_next;
                    send_in.drop    = 1'b0;
                    send_in.cq      = sel_head.last && (sel_next == sel_left);
                    s_tx_stat.ready = send_in_rdy;
                    if (send_in_rdy) begin
                        head_upd  = 1'b1;
                        head_done = (sel_next == sel_left);
                        cq_book   = head_done && sel_head.last;
                        state_N   = S_IDLE;
                    end
                end else if (s_tx_stat.data.error == TX_NOSPACE) begin
                    // Retry later, with at most the remaining space (if there is a whole beat of it)
                    s_tx_stat.ready = 1'b1;
                    head_upd        = 1'b1;
                    left_N          = sel_left;
                    next_N          = (space == 0) ? sel_next : ((space < sel_left) ? space : sel_left);
                    state_N         = S_IDLE;
                end else begin
                    // Not established: drop the rest
                    err             = TCP_ERR_NOT_ESTABLISHED;
                    send_in_vld     = 1'b1;
                    s_tx_stat.ready = send_in_rdy;
                    if (send_in_rdy) begin
                        head_done = 1'b1;
                        cq_book   = sel_head.last;
                        state_N   = S_IDLE;
                    end
                end
            end
        end

        default: state_N = S_IDLE;
    endcase

    send_in.ack.rsrvd = err;
end

queue_stream #(
    .QTYPE(send_t),
    .QDEPTH(SEND_DEPTH)
) inst_send_q (
    .aclk(aclk),
    .aresetn(aresetn),
    .val_snk(send_in_vld),
    .rdy_snk(send_in_rdy),
    .data_snk(send_in),
    .val_src(send_out_vld),
    .rdy_src(send_out_rdy),
    .data_src(send_out)
);

// ---------------------------------------------------------------------------------------------------
// Data FSM: ceil(len/64) beats per entry, sent or dropped; the next entry is loaded with the last beat
// ---------------------------------------------------------------------------------------------------
assign has_data     = cur_vld_C && (cur_C.len != 0);
assign beat         = has_data && tx_valid[cur_C.vfid] && (cur_C.drop || m_axis_tx.tready);
assign cur_done     = cur_vld_C && (!has_data || (beat && (beats_C == 0)));
assign send_out_rdy = !cur_vld_C || cur_done;

always_comb begin
    for (int i = 0; i < N_REGIONS; i++) begin
        tx_ready[i] = has_data && (cur_C.vfid == i) && (cur_C.drop || m_axis_tx.tready);
    end
end

assign m_axis_tx.tvalid = has_data && !cur_C.drop && tx_valid[cur_C.vfid];
assign m_axis_tx.tdata  = tx_data[cur_C.vfid];
assign m_axis_tx.tkeep  = ((beats_C == 0) && (cur_C.len[BEAT_LOG_BITS-1:0] != 0)) ?
                          ~('1 << cur_C.len[BEAT_LOG_BITS-1:0]) : '1;
assign m_axis_tx.tlast  = (beats_C == 0);

always_ff @(posedge aclk) begin
    if (!aresetn) begin
        cur_vld_C <= 1'b0;
        cur_C     <= 'X;
        beats_C   <= 'X;
    end else begin
        if (send_out_rdy) begin
            cur_vld_C <= send_out_vld;
            cur_C     <= send_out;
            beats_C   <= (send_out.len - 1) >> BEAT_LOG_BITS;
        end else if (beat) begin
            beats_C <= beats_C - 1;
        end
    end
end

endmodule
