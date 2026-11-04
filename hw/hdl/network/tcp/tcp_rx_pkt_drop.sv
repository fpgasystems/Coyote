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
 * @brief   Whole-packet dropper in front of a consumer that may stall for a long time (the TOE)
 *
 * The upstream side is never back-pressured (tready = 1): a packet is either stored completely in a
 * store-and-forward packet FIFO or dropped completely when the FIFO is (almost) full at its first
 * beat. Dropped TCP segments are retransmitted by the peer, while back-pressuring the IP handler would
 * head-of-line block every other protocol behind it (RDMA, ARP, ICMP) and overflow the CMAC RX FIFO.
 *
 * Space for a whole packet (MAX_PKT_BEATS) + MARGIN_BEATS (latency of the prog_full flag) is reserved
 * when a packet is admitted, so an admitted packet always fits. Packets longer than MAX_PKT_BEATS
 * (not legitimate, larger than any jumbo frame) are truncated (tlast forced, rest dropped).
 */
module tcp_rx_pkt_drop #(
    parameter integer   FIFO_DEPTH      = 1024, // beats of AXI_NET_BITS
    parameter integer   MAX_PKT_BEATS   = 160,  // 10 KB with 512 bit beats (covers 9 KB jumbo frames)
    parameter integer   MARGIN_BEATS    = 16
) (
    input  logic        aclk,
    input  logic        aresetn,

    AXI4S.s             s_axis,
    AXI4S.m             m_axis
);

localparam integer PROG_FULL_THRESH = FIFO_DEPTH - MAX_PKT_BEATS - MARGIN_BEATS;
localparam integer CNT_BITS = $clog2(MAX_PKT_BEATS + 1);

// FIFO
logic                       fifo_wr_valid;
logic                       fifo_wr_ready;
logic                       fifo_wr_last;
logic                       fifo_prog_full;

xpm_fifo_axis #(
    .CLOCKING_MODE      ("common_clock"),
    .FIFO_MEMORY_TYPE   ("auto"),
    .PACKET_FIFO        ("true"),
    .FIFO_DEPTH         (FIFO_DEPTH),
    .TDATA_WIDTH        (AXI_NET_BITS),
    .TID_WIDTH          (1),
    .TDEST_WIDTH        (1),
    .TUSER_WIDTH        (1),
    .USE_ADV_FEATURES   ("1002"), // prog_full
    .PROG_FULL_THRESH   (PROG_FULL_THRESH),
    .CDC_SYNC_STAGES    (2)
) inst_fifo (
    .s_aresetn          (aresetn),
    .s_aclk             (aclk),
    .m_aclk             (aclk),

    .s_axis_tvalid      (fifo_wr_valid),
    .s_axis_tready      (fifo_wr_ready),
    .s_axis_tdata       (s_axis.tdata),
    .s_axis_tstrb       ('1),
    .s_axis_tkeep       (s_axis.tkeep),
    .s_axis_tlast       (fifo_wr_last),
    .s_axis_tid         (1'b0),
    .s_axis_tdest       (1'b0),
    .s_axis_tuser       (1'b0),

    .m_axis_tvalid      (m_axis.tvalid),
    .m_axis_tready      (m_axis.tready),
    .m_axis_tdata       (m_axis.tdata),
    .m_axis_tstrb       (),
    .m_axis_tkeep       (m_axis.tkeep),
    .m_axis_tlast       (m_axis.tlast),
    .m_axis_tid         (),
    .m_axis_tdest       (),
    .m_axis_tuser       (),

    .prog_full_axis     (fifo_prog_full),
    .wr_data_count_axis (),
    .almost_full_axis   (),
    .prog_empty_axis    (),
    .rd_data_count_axis (),
    .almost_empty_axis  (),

    .injectsbiterr_axis (1'b0),
    .injectdbiterr_axis (1'b0),
    .sbiterr_axis       (),
    .dbiterr_axis       ()
);

// Admission FSM
typedef enum logic[1:0] {ST_IDLE, ST_FWD, ST_DROP} state_t;
state_t state_C, state_N;
logic [CNT_BITS-1:0] cnt_C, cnt_N; // beats of the current packet written to the FIFO

always_ff @(posedge aclk) begin
    if (!aresetn) begin
        state_C  <= ST_IDLE;
        cnt_C    <= '0;
    end else begin
        state_C  <= state_N;
        cnt_C    <= cnt_N;
    end
end

always_comb begin
    state_N = state_C;
    cnt_N   = cnt_C;

    s_axis.tready = 1'b1; // never back-pressure the IP handler
    fifo_wr_valid = 1'b0;
    fifo_wr_last  = s_axis.tlast;

    case (state_C)
        ST_IDLE: begin
            if (s_axis.tvalid) begin
                if (fifo_prog_full || !fifo_wr_ready) begin
                    // Not enough room reserved for a whole packet: drop it
                    state_N = s_axis.tlast ? ST_IDLE : ST_DROP;
                end else begin
                    fifo_wr_valid = 1'b1;
                    if (!s_axis.tlast) begin
                        state_N = ST_FWD;
                        cnt_N   = 1;
                    end
                end
            end
        end

        ST_FWD: begin
            if (s_axis.tvalid) begin
                fifo_wr_valid = 1'b1;
                if (s_axis.tlast) begin
                    state_N = ST_IDLE;
                    cnt_N   = '0;
                end else if (cnt_C == MAX_PKT_BEATS - 1) begin
                    // Over-long packet: truncate, drop the rest
                    fifo_wr_last = 1'b1;
                    state_N = ST_DROP;
                    cnt_N   = '0;
                end else begin
                    cnt_N = cnt_C + 1;
                end
            end
        end

        ST_DROP: begin
            if (s_axis.tvalid && s_axis.tlast) state_N = ST_IDLE;
        end

        default: state_N = ST_IDLE;
    endcase
end

endmodule
