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
 * NVMe-safe write half of the HBM stripe mapper.
 *
 * Full-width INCR bursts are split at STRIPE_FRAG_SIZE boundaries. A W
 * descriptor records every emitted physical AW, so partial first fragments
 * and W-before-AW backpressure are handled correctly. One B is consumed per
 * fragment and exactly one combined response is returned per original burst.
 */
module axi_stripe_nvme_wr (
    input  logic                        aclk,
    input  logic                        aresetn,

    input  logic [AXI_ADDR_BITS-1:0]    s_axi_awaddr,
    input  logic [1:0]                  s_axi_awburst,
    input  logic [3:0]                  s_axi_awcache,
    input  logic [AXI_ID_BITS-1:0]      s_axi_awid,
    input  logic [7:0]                  s_axi_awlen,
    input  logic [0:0]                  s_axi_awlock,
    input  logic [2:0]                  s_axi_awprot,
    input  logic [3:0]                  s_axi_awqos,
    input  logic [3:0]                  s_axi_awregion,
    input  logic [2:0]                  s_axi_awsize,
    output logic                        s_axi_awready,
    input  logic                        s_axi_awvalid,

    output logic [AXI_ADDR_BITS-1:0]    m_axi_awaddr,
    output logic [1:0]                  m_axi_awburst,
    output logic [3:0]                  m_axi_awcache,
    output logic [AXI_ID_BITS-1:0]      m_axi_awid,
    output logic [7:0]                  m_axi_awlen,
    output logic [0:0]                  m_axi_awlock,
    output logic [2:0]                  m_axi_awprot,
    output logic [3:0]                  m_axi_awqos,
    output logic [3:0]                  m_axi_awregion,
    output logic [2:0]                  m_axi_awsize,
    input  logic                        m_axi_awready,
    output logic                        m_axi_awvalid,

    output logic [AXI_ID_BITS-1:0]      s_axi_bid,
    output logic [1:0]                  s_axi_bresp,
    input  logic                        s_axi_bready,
    output logic                        s_axi_bvalid,

    input  logic [AXI_ID_BITS-1:0]      m_axi_bid,
    input  logic [1:0]                  m_axi_bresp,
    output logic                        m_axi_bready,
    input  logic                        m_axi_bvalid,

    input  logic [AXI_DATA_BITS-1:0]    s_axi_wdata,
    input  logic                        s_axi_wlast,
    input  logic [AXI_DATA_BITS/8-1:0]  s_axi_wstrb,
    output logic                        s_axi_wready,
    input  logic                        s_axi_wvalid,

    output logic [AXI_DATA_BITS-1:0]    m_axi_wdata,
    output logic                        m_axi_wlast,
    output logic [AXI_DATA_BITS/8-1:0]  m_axi_wstrb,
    input  logic                        m_axi_wready,
    output logic                        m_axi_wvalid
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
        relative_addr    = logical_addr - MEM_BASE;
        fragment_index   = relative_addr >> FRAG_LOG_BITS;
        channel_index    = fragment_index & CHAN_MASK;
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

function automatic logic [1:0] merge_bresp(
    input logic [1:0] accumulated,
    input logic [1:0] current
);
    begin
        // DECERR > SLVERR > EXOKAY > OKAY.
        if ((accumulated == 2'b11) || (current == 2'b11))
            merge_bresp = 2'b11;
        else if ((accumulated == 2'b10) || (current == 2'b10))
            merge_bresp = 2'b10;
        else if ((accumulated == 2'b01) || (current == 2'b01))
            merge_bresp = 2'b01;
        else
            merge_bresp = 2'b00;
    end
endfunction

// Address expansion state. Already-emitted write data and responses may
// continue while the next original address is being expanded.
logic                         issue_active_q;
logic [AXI_ADDR_BITS-1:0]     logical_addr_q;
logic [8:0]                   beats_left_q;
logic [1:0]                   awburst_q;
logic [3:0]                   awcache_q;
logic [AXI_ID_BITS-1:0]       awid_q;
logic [0:0]                   awlock_q;
logic [2:0]                   awprot_q;
logic [3:0]                   awqos_q;
logic [3:0]                   awregion_q;
logic [2:0]                   awsize_q;

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
        s_axi_awaddr, {1'b0, s_axi_awlen} + 9'd1
    );
end

// Concurrent transactions are allowed for one ID. The PL-NVMe bridge uses ID
// zero, so this preserves its normal address/data pipelining while remaining
// correct if another integration supplies nonzero IDs.
logic                         active_id_valid_q;
logic [AXI_ID_BITS-1:0]       active_id_q;
logic [META_COUNT_BITS-1:0]   original_count_q;

// W descriptors are in global AW order (AXI4 has no WID).
logic [8:0]                   w_beats_meta [META_DEPTH];
logic [META_PTR_BITS-1:0]     w_wr_ptr_q;
logic [META_PTR_BITS-1:0]     w_rd_ptr_q;
logic [META_COUNT_BITS-1:0]   w_count_q;
logic [8:0]                   w_beat_index_q;

// B markers are ordered because only one ID is active at a time.
logic                         b_final_meta [META_DEPTH];
logic [META_PTR_BITS-1:0]     b_wr_ptr_q;
logic [META_PTR_BITS-1:0]     b_rd_ptr_q;
logic [META_COUNT_BITS-1:0]   b_count_q;
logic [1:0]                   bresp_accum_q;

logic                         source_aw_fire;
logic                         mapped_aw_fire;
logic                         w_meta_push;
logic                         w_meta_pop;
logic                         b_meta_push;
logic                         b_meta_pop;
logic                         w_fire;
logic                         b_fire;
logic                         original_response_done;
logic                         id_available;
logic                         metadata_available;
logic                         w_meta_valid;
logic                         b_meta_valid;
logic                         b_meta_final;
logic [8:0]                   w_meta_beats_head;

logic                         fifo_wvalid;
logic                         fifo_wready;
logic [AXI_DATA_BITS-1:0]     fifo_wdata;
logic [AXI_DATA_BITS/8-1:0]   fifo_wstrb;
logic                         fifo_wlast;

always_comb begin
    w_meta_beats_head = 9'd1;
    if (w_count_q != 0)
        w_meta_beats_head = w_beats_meta[w_rd_ptr_q];

    b_meta_final = 1'b0;
    if (b_count_q != 0)
        b_meta_final = b_final_meta[b_rd_ptr_q];
end

assign id_available = !active_id_valid_q || (s_axi_awid == active_id_q);
assign metadata_available =
    (w_count_q <= (META_DEPTH_VALUE - incoming_fragments_c))
    && (b_count_q <= (META_DEPTH_VALUE - incoming_fragments_c));

assign s_axi_awready = !issue_active_q && id_available && metadata_available;
assign source_aw_fire = s_axi_awvalid && s_axi_awready;

assign m_axi_awaddr   = stripe_addr(logical_addr_q);
assign m_axi_awburst  = awburst_q;
assign m_axi_awcache  = awcache_q;
assign m_axi_awid     = awid_q;
assign m_axi_awlen    = fragment_beats_c[7:0] - 1'b1;
assign m_axi_awlock   = awlock_q;
assign m_axi_awprot   = awprot_q;
assign m_axi_awqos    = awqos_q;
assign m_axi_awregion = awregion_q;
assign m_axi_awsize   = awsize_q;
assign m_axi_awvalid  = issue_active_q
                      && (w_count_q < META_DEPTH_VALUE)
                      && (b_count_q < META_DEPTH_VALUE);
assign mapped_aw_fire = m_axi_awvalid && m_axi_awready;
assign w_meta_push = mapped_aw_fire;
assign b_meta_push = mapped_aw_fire;

always_ff @(posedge aclk) begin
    if (!aresetn) begin
        issue_active_q <= 1'b0;
        logical_addr_q <= '0;
        beats_left_q   <= '0;
        awburst_q      <= '0;
        awcache_q      <= '0;
        awid_q         <= '0;
        awlock_q       <= '0;
        awprot_q       <= '0;
        awqos_q        <= '0;
        awregion_q     <= '0;
        awsize_q       <= '0;
    end else begin
        if (source_aw_fire) begin
            issue_active_q <= 1'b1;
            logical_addr_q <= s_axi_awaddr;
            beats_left_q   <= {1'b0, s_axi_awlen} + 9'd1;
            awburst_q      <= s_axi_awburst;
            awcache_q      <= s_axi_awcache;
            awid_q         <= s_axi_awid;
            awlock_q       <= s_axi_awlock;
            awprot_q       <= s_axi_awprot;
            awqos_q        <= s_axi_awqos;
            awregion_q     <= s_axi_awregion;
            awsize_q       <= s_axi_awsize;
        end

        if (mapped_aw_fire) begin
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

// Accept W independently of physical-AW expansion. This keeps the upstream
// path ready across the deterministic stripe mapping latency; the FIFO output
// remains parked until a physical AW descriptor is available.
axis_data_fifo_nvme_w inst_w_fifo (
    .s_axis_aresetn(aresetn),
    .s_axis_aclk   (aclk),
    .s_axis_tvalid (s_axi_wvalid),
    .s_axis_tready (s_axi_wready),
    .s_axis_tdata  (s_axi_wdata),
    .s_axis_tstrb  (s_axi_wstrb),
    .s_axis_tlast  (s_axi_wlast),
    .m_axis_tvalid (fifo_wvalid),
    .m_axis_tready (fifo_wready),
    .m_axis_tdata  (fifo_wdata),
    .m_axis_tstrb  (fifo_wstrb),
    .m_axis_tlast  (fifo_wlast)
);

// W data is released only after its corresponding physical AW has been
// accepted. The descriptor length, rather than the buffered source WLAST,
// places WLAST correctly for partial first and final physical fragments.
assign w_meta_valid = (w_count_q != 0);
assign fifo_wready  = m_axi_wready && w_meta_valid;
assign m_axi_wdata  = fifo_wdata;
assign m_axi_wstrb  = fifo_wstrb;
assign m_axi_wvalid = fifo_wvalid && w_meta_valid;
assign m_axi_wlast  = w_meta_valid
                    && (w_beat_index_q == (w_meta_beats_head - 1'b1));
assign w_fire = m_axi_wvalid && m_axi_wready;
assign w_meta_pop = w_fire && m_axi_wlast;

always_ff @(posedge aclk) begin
    if (!aresetn) begin
        w_wr_ptr_q     <= '0;
        w_rd_ptr_q     <= '0;
        w_count_q      <= '0;
        w_beat_index_q <= '0;
    end else begin
        if (w_meta_push) begin
            w_beats_meta[w_wr_ptr_q] <= fragment_beats_c;
            w_wr_ptr_q <= w_wr_ptr_q + 1'b1;
        end

        if (w_meta_pop) begin
            w_rd_ptr_q     <= w_rd_ptr_q + 1'b1;
            w_beat_index_q <= '0;
        end else if (w_fire) begin
            w_beat_index_q <= w_beat_index_q + 1'b1;
        end

        unique case ({w_meta_push, w_meta_pop})
            2'b10: w_count_q <= w_count_q + 1'b1;
            2'b01: w_count_q <= w_count_q - 1'b1;
            default: w_count_q <= w_count_q;
        endcase
    end
end

// Intermediate fragment responses are consumed independently of upstream
// BREADY. The final response is held at the downstream interface until the
// original requester accepts the single combined response.
assign b_meta_valid = (b_count_q != 0);
assign s_axi_bid    = m_axi_bid;
assign s_axi_bresp  = merge_bresp(bresp_accum_q, m_axi_bresp);
assign s_axi_bvalid = m_axi_bvalid && b_meta_valid && b_meta_final;
assign m_axi_bready = b_meta_valid && (b_meta_final ? s_axi_bready : 1'b1);
assign b_fire = m_axi_bvalid && m_axi_bready;
assign b_meta_pop = b_fire;
assign original_response_done = b_fire && b_meta_final;

always_ff @(posedge aclk) begin
    if (!aresetn) begin
        b_wr_ptr_q    <= '0;
        b_rd_ptr_q    <= '0;
        b_count_q     <= '0;
        bresp_accum_q <= 2'b00;
    end else begin
        if (b_meta_push) begin
            b_final_meta[b_wr_ptr_q] <= fragment_final_c;
            b_wr_ptr_q <= b_wr_ptr_q + 1'b1;
        end

        if (b_meta_pop)
            b_rd_ptr_q <= b_rd_ptr_q + 1'b1;

        if (b_fire) begin
            if (b_meta_final)
                bresp_accum_q <= 2'b00;
            else
                bresp_accum_q <= merge_bresp(bresp_accum_q, m_axi_bresp);
        end

        unique case ({b_meta_push, b_meta_pop})
            2'b10: b_count_q <= b_count_q + 1'b1;
            2'b01: b_count_q <= b_count_q - 1'b1;
            default: b_count_q <= b_count_q;
        endcase
    end
end

always_ff @(posedge aclk) begin
    if (!aresetn) begin
        active_id_valid_q <= 1'b0;
        active_id_q       <= '0;
        original_count_q  <= '0;
    end else begin
        if (source_aw_fire && !active_id_valid_q) begin
            active_id_valid_q <= 1'b1;
            active_id_q       <= s_axi_awid;
        end

        unique case ({source_aw_fire, original_response_done})
            2'b10: original_count_q <= original_count_q + 1'b1;
            2'b01: original_count_q <= original_count_q - 1'b1;
            default: original_count_q <= original_count_q;
        endcase

        if (original_response_done && (original_count_q == 1)
                && !source_aw_fire)
            active_id_valid_q <= 1'b0;
    end
end

// s_axi_wlast is intentionally not used to form physical WLAST. AXI AWLEN is
// the authoritative length, and a compliant source presents matching WLAST.

endmodule
