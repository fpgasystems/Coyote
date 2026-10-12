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

`timescale 1ns / 1ps

import lynxTypes::*;

/**
 * NVMe-safe read half of the HBM stripe mapper.
 *
 * Full-width INCR bursts are split at STRIPE_FRAG_SIZE boundaries. Physical
 * fragment RLASTs are suppressed and a single RLAST is returned at the end of
 * each original burst. Requests with one ID may remain outstanding together;
 * a different ID is accepted after all responses for the active ID complete.
 */
module axi_stripe_nvme_rd (
    input  logic                        aclk,
    input  logic                        aresetn,

    input  logic [AXI_ADDR_BITS-1:0]    s_axi_araddr,
    input  logic [1:0]                  s_axi_arburst,
    input  logic [3:0]                  s_axi_arcache,
    input  logic [AXI_ID_BITS-1:0]      s_axi_arid,
    input  logic [7:0]                  s_axi_arlen,
    input  logic [0:0]                  s_axi_arlock,
    input  logic [2:0]                  s_axi_arprot,
    input  logic [3:0]                  s_axi_arqos,
    input  logic [3:0]                  s_axi_arregion,
    input  logic [2:0]                  s_axi_arsize,
    output logic                        s_axi_arready,
    input  logic                        s_axi_arvalid,

    output logic [AXI_ADDR_BITS-1:0]    m_axi_araddr,
    output logic [1:0]                  m_axi_arburst,
    output logic [3:0]                  m_axi_arcache,
    output logic [AXI_ID_BITS-1:0]      m_axi_arid,
    output logic [7:0]                  m_axi_arlen,
    output logic [0:0]                  m_axi_arlock,
    output logic [2:0]                  m_axi_arprot,
    output logic [3:0]                  m_axi_arqos,
    output logic [3:0]                  m_axi_arregion,
    output logic [2:0]                  m_axi_arsize,
    input  logic                        m_axi_arready,
    output logic                        m_axi_arvalid,

    output logic [AXI_DATA_BITS-1:0]    s_axi_rdata,
    output logic [AXI_ID_BITS-1:0]      s_axi_rid,
    output logic                        s_axi_rlast,
    output logic [1:0]                  s_axi_rresp,
    input  logic                        s_axi_rready,
    output logic                        s_axi_rvalid,

    input  logic [AXI_DATA_BITS-1:0]    m_axi_rdata,
    input  logic [AXI_ID_BITS-1:0]      m_axi_rid,
    input  logic                        m_axi_rlast,
    input  logic [1:0]                  m_axi_rresp,
    output logic                        m_axi_rready,
    input  logic                        m_axi_rvalid
);

localparam integer BEAT_BYTES      = AXI_DATA_BITS / 8;
localparam integer BEAT_LOG_BITS   = $clog2(BEAT_BYTES);
localparam integer FRAG_LOG_BITS   = $clog2(STRIPE_FRAG_SIZE);
localparam integer FRAG_BEATS      = STRIPE_FRAG_SIZE / BEAT_BYTES;
localparam integer FRAG_BEAT_BITS  = $clog2(FRAG_BEATS);
localparam integer META_DEPTH      = 8 * N_OUTSTANDING;
localparam integer META_PTR_BITS   = $clog2(META_DEPTH);
localparam integer META_COUNT_BITS = $clog2(META_DEPTH + 1);

localparam logic [AXI_ADDR_BITS-1:0] MEM_BASE = MEM_OFFSET;
localparam logic [AXI_ADDR_BITS-1:0] FRAG_MASK =
    AXI_ADDR_BITS'(STRIPE_FRAG_SIZE) - 1'b1;
localparam logic [AXI_ADDR_BITS-1:0] CHAN_MASK =
    AXI_ADDR_BITS'(N_STRIPE_CHAN) - 1'b1;
localparam logic [8:0] FRAG_BEATS_VALUE = 9'(FRAG_BEATS);
localparam logic [META_COUNT_BITS-1:0] META_DEPTH_VALUE =
    META_COUNT_BITS'(META_DEPTH);

function automatic logic [AXI_ADDR_BITS-1:0] stripe_addr(
    input logic [AXI_ADDR_BITS-1:0] logical_addr
);
    logic [AXI_ADDR_BITS-1:0] relative_addr;
    logic [AXI_ADDR_BITS-1:0] fragment_index;
    logic [AXI_ADDR_BITS-1:0] channel_index;
    logic [AXI_ADDR_BITS-1:0] channel_fragment;
    begin
        relative_addr   = logical_addr - MEM_BASE;
        fragment_index  = relative_addr >> FRAG_LOG_BITS;
        channel_index   = fragment_index & CHAN_MASK;
        channel_fragment = fragment_index >> N_STRIPE_CHAN_BITS;

        stripe_addr = MEM_BASE
                    + (channel_index << MC_SIZE)
                    + (channel_fragment << FRAG_LOG_BITS)
                    + (relative_addr & FRAG_MASK);
    end
endfunction

function automatic logic [AXI_ADDR_BITS-1:0] beats_to_bytes(
    input logic [8:0] beats
);
    logic [AXI_ADDR_BITS-1:0] widened_beats;
    begin
        widened_beats = '0;
        widened_beats[8:0] = beats;
        beats_to_bytes = widened_beats << BEAT_LOG_BITS;
    end
endfunction

function automatic logic [META_COUNT_BITS-1:0] fragment_count(
    input logic [AXI_ADDR_BITS-1:0] logical_addr,
    input logic [8:0]               beats
);
    logic [AXI_ADDR_BITS-1:0] relative_addr;
    logic [8:0] offset_beats;
    logic [9:0] rounded_beats;
    begin
        relative_addr = logical_addr - MEM_BASE;
        offset_beats = 9'((relative_addr & FRAG_MASK) >> BEAT_LOG_BITS);
        rounded_beats = 10'(offset_beats) + 10'(beats)
                      + 10'(FRAG_BEATS - 1);
        fragment_count = META_COUNT_BITS'(
            rounded_beats >> FRAG_BEAT_BITS
        );
    end
endfunction

// Only one original address is being expanded at a time. Responses from
// already-expanded requests may continue in parallel.
logic                         issue_active_q;
logic [AXI_ADDR_BITS-1:0]     logical_addr_q;
logic [8:0]                   beats_left_q;
logic [1:0]                   arburst_q;
logic [3:0]                   arcache_q;
logic [AXI_ID_BITS-1:0]       arid_q;
logic [0:0]                   arlock_q;
logic [2:0]                   arprot_q;
logic [3:0]                   arqos_q;
logic [3:0]                   arregion_q;
logic [2:0]                   arsize_q;

logic [AXI_ADDR_BITS-1:0]     relative_addr_c;
logic [8:0]                   offset_beats_c;
logic [8:0]                   boundary_beats_c;
logic [8:0]                   fragment_beats_c;
logic                         fragment_final_c;
logic [META_COUNT_BITS-1:0]   incoming_fragments_c;

always_comb begin
    relative_addr_c  = logical_addr_q - MEM_BASE;
    offset_beats_c   = 9'((relative_addr_c & FRAG_MASK) >> BEAT_LOG_BITS);
    boundary_beats_c = FRAG_BEATS_VALUE - offset_beats_c;
    fragment_beats_c = (beats_left_q < boundary_beats_c)
                     ? beats_left_q : boundary_beats_c;
    fragment_final_c = (fragment_beats_c == beats_left_q);

    incoming_fragments_c = fragment_count(
        s_axi_araddr, {1'b0, s_axi_arlen} + 9'd1
    );
end

// All concurrently outstanding requests use one ID. This retains full
// pipelining on the PL-NVMe path (whose bridge ID is zero) while preventing
// cross-ID response reordering from invalidating the ordered marker FIFO.
logic                         active_id_valid_q;
logic [AXI_ID_BITS-1:0]       active_id_q;
logic [META_COUNT_BITS-1:0]   original_count_q;

// One marker is stored per emitted physical fragment.
logic                         final_meta [META_DEPTH];
logic [META_PTR_BITS-1:0]     meta_wr_ptr_q;
logic [META_PTR_BITS-1:0]     meta_rd_ptr_q;
logic [META_COUNT_BITS-1:0]   meta_count_q;

logic                         source_ar_fire;
logic                         mapped_ar_fire;
logic                         meta_push;
logic                         meta_pop;
logic                         response_fire;
logic                         original_response_done;
logic                         id_available;
logic                         metadata_available;
logic                         meta_final_head;

always_comb begin
    meta_final_head = 1'b0;
    if (meta_count_q != 0)
        meta_final_head = final_meta[meta_rd_ptr_q];
end

assign id_available = !active_id_valid_q || (s_axi_arid == active_id_q);
assign metadata_available =
    meta_count_q <= (META_DEPTH_VALUE - incoming_fragments_c);

assign s_axi_arready = !issue_active_q && id_available && metadata_available;
assign source_ar_fire = s_axi_arvalid && s_axi_arready;

assign m_axi_araddr   = stripe_addr(logical_addr_q);
assign m_axi_arburst  = arburst_q;
assign m_axi_arcache  = arcache_q;
assign m_axi_arid     = arid_q;
assign m_axi_arlen    = fragment_beats_c[7:0] - 1'b1;
assign m_axi_arlock   = arlock_q;
assign m_axi_arprot   = arprot_q;
assign m_axi_arqos    = arqos_q;
assign m_axi_arregion = arregion_q;
assign m_axi_arsize   = arsize_q;
assign m_axi_arvalid  = issue_active_q && (meta_count_q < META_DEPTH_VALUE);
assign mapped_ar_fire = m_axi_arvalid && m_axi_arready;
assign meta_push      = mapped_ar_fire;

always_ff @(posedge aclk) begin
    if (!aresetn) begin
        issue_active_q <= 1'b0;
        logical_addr_q <= '0;
        beats_left_q   <= '0;
        arburst_q      <= '0;
        arcache_q      <= '0;
        arid_q         <= '0;
        arlock_q       <= '0;
        arprot_q       <= '0;
        arqos_q        <= '0;
        arregion_q     <= '0;
        arsize_q       <= '0;
    end else begin
        if (source_ar_fire) begin
            issue_active_q <= 1'b1;
            logical_addr_q <= s_axi_araddr;
            beats_left_q   <= {1'b0, s_axi_arlen} + 9'd1;
            arburst_q      <= s_axi_arburst;
            arcache_q      <= s_axi_arcache;
            arid_q         <= s_axi_arid;
            arlock_q       <= s_axi_arlock;
            arprot_q       <= s_axi_arprot;
            arqos_q        <= s_axi_arqos;
            arregion_q     <= s_axi_arregion;
            arsize_q       <= s_axi_arsize;
        end

        if (mapped_ar_fire) begin
            if (fragment_final_c) begin
                issue_active_q <= 1'b0;
                beats_left_q   <= '0;
            end else begin
                logical_addr_q <= logical_addr_q
                                + beats_to_bytes(fragment_beats_c);
                beats_left_q   <= beats_left_q - fragment_beats_c;
            end
        end
    end
end

// A fragment marker remains at the FIFO head for every beat of that fragment
// and is consumed only with the physical RLAST handshake.
assign s_axi_rdata  = m_axi_rdata;
assign s_axi_rid    = m_axi_rid;
assign s_axi_rresp  = m_axi_rresp;
assign s_axi_rvalid = m_axi_rvalid && (meta_count_q != 0);
assign s_axi_rlast  = m_axi_rlast && meta_final_head;
assign m_axi_rready = s_axi_rready && (meta_count_q != 0);

assign response_fire = m_axi_rvalid && m_axi_rready;
assign meta_pop = response_fire && m_axi_rlast;
assign original_response_done = response_fire && m_axi_rlast
                              && meta_final_head;

always_ff @(posedge aclk) begin
    if (!aresetn) begin
        meta_wr_ptr_q <= '0;
        meta_rd_ptr_q <= '0;
        meta_count_q  <= '0;
    end else begin
        if (meta_push) begin
            final_meta[meta_wr_ptr_q] <= fragment_final_c;
            meta_wr_ptr_q <= meta_wr_ptr_q + 1'b1;
        end

        if (meta_pop)
            meta_rd_ptr_q <= meta_rd_ptr_q + 1'b1;

        unique case ({meta_push, meta_pop})
            2'b10: meta_count_q <= meta_count_q + 1'b1;
            2'b01: meta_count_q <= meta_count_q - 1'b1;
            default: meta_count_q <= meta_count_q;
        endcase
    end
end

always_ff @(posedge aclk) begin
    if (!aresetn) begin
        active_id_valid_q <= 1'b0;
        active_id_q       <= '0;
        original_count_q  <= '0;
    end else begin
        if (source_ar_fire && !active_id_valid_q) begin
            active_id_valid_q <= 1'b1;
            active_id_q       <= s_axi_arid;
        end

        unique case ({source_ar_fire, original_response_done})
            2'b10: original_count_q <= original_count_q + 1'b1;
            2'b01: original_count_q <= original_count_q - 1'b1;
            default: original_count_q <= original_count_q;
        endcase

        if (original_response_done && (original_count_q == 1)
                && !source_ar_fire)
            active_id_valid_q <= 1'b0;
    end
end

endmodule
