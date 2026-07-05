/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2021-2025, Systems Group, ETH Zurich
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

`timescale 1ns / 1ps

import lynxTypes::*;

module axi_stripe_wr (
    input  logic                        aclk,
    input  logic                        aresetn,
    
    input  logic[AXI_ADDR_BITS-1:0]     s_axi_awaddr,
    input  logic[1:0]		            s_axi_awburst,
    input  logic[3:0]		            s_axi_awcache,
    input  logic[AXI_ID_BITS-1:0]       s_axi_awid,
    input  logic[7:0]		            s_axi_awlen,
    input  logic[0:0]		            s_axi_awlock,
    input  logic[2:0]		            s_axi_awprot,
    input  logic[3:0]		            s_axi_awqos,
    input  logic[3:0]		            s_axi_awregion,
    input  logic[2:0]		            s_axi_awsize,
    output logic			            s_axi_awready,
    input  logic			            s_axi_awvalid,

    output logic[AXI_ADDR_BITS-1:0]     m_axi_awaddr,
    output logic[1:0]		            m_axi_awburst,
    output logic[3:0]		            m_axi_awcache,
    output logic[AXI_ID_BITS-1:0]       m_axi_awid,
    output logic[7:0]		            m_axi_awlen,
    output logic[0:0]		            m_axi_awlock,
    output logic[2:0]		            m_axi_awprot,
    output logic[3:0]		            m_axi_awqos,
    output logic[3:0]		            m_axi_awregion,
    output logic[2:0]		            m_axi_awsize,
    input  logic			            m_axi_awready,
    output logic			            m_axi_awvalid,

    output logic[AXI_ID_BITS-1:0]       s_axi_bid,
    output logic[1:0]                   s_axi_bresp,
    input  logic                        s_axi_bready,
    output logic                        s_axi_bvalid,

    input  logic[AXI_ID_BITS-1:0]       m_axi_bid,
    input  logic[1:0]                   m_axi_bresp,
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

localparam integer FRAG_LOG_BITS = $clog2(STRIPE_FRAG_SIZE);
localparam integer BEAT_LOG_BITS = $clog2(AXI_DATA_BITS/8);
localparam integer N_OUTSTANDING_STRIPE = 8 * N_OUTSTANDING;

localparam integer FRAG_BEATS = $ceil(STRIPE_FRAG_SIZE/(AXI_DATA_BITS/8));
localparam integer FRAG_BEATS_BITS = $clog2(FRAG_BEATS) + 1;

// FSM
typedef enum logic[0:0] {ST_IDLE, ST_PARSE} state_t;
logic[0:0] state_C, state_N;

logic [AXI_ADDR_BITS-1:0] awaddr_C, awaddr_N;
logic [1:0] awburst_C, awburst_N;
logic [3:0] awcache_C, awcache_N;
logic [1:0] awid_C, awid_N;
logic [7:0] awlen_C, awlen_N;
logic [0:0] awlock_C, awlock_N;
logic [2:0] awprot_C, awprot_N;
logic [3:0] awqos_C, awqos_N;
logic [3:0] awregion_C, awregion_N;
logic [2:0] awsize_C, awsize_N;

logic [AXI_ADDR_BITS-1:0] paddr_C, paddr_N;
logic [7:0] plen_C, plen_N;
logic done_C, done_N;

logic [7:0] clen;
logic [7:0] slen;

logic [AXI_ADDR_BITS-1:0] awaddr_remapped;

logic [AXI_ADDR_BITS-1:0] lsb_mask;
assign lsb_mask = (1 << FRAG_LOG_BITS) - 1;

logic [AXI_ADDR_BITS-1:0] msb_mask;
assign msb_mask = (~lsb_mask) << N_STRIPE_CHAN_BITS;

logic [FRAG_BEATS_BITS-1:0] cnt_W;

// REG
always_ff @(posedge aclk) begin
    if (aresetn == 1'b0) begin
        state_C <= ST_IDLE;

        awaddr_C <= 'X;
        awburst_C <= 'X;
        awcache_C <= 'X;
        awid_C <= 'X;
        awlen_C <= 'X;
        awlock_C <= 'X;
        awprot_C <= 'X;
        awqos_C <= 'X;
        awregion_C <= 'X;
        awsize_C <= 'X;

        paddr_C <= 'X;
        plen_C <= 'X;
        done_C <= 1'b0;

        cnt_W <= 0;
    end else begin
        state_C <= state_N;

        awaddr_C <= awaddr_N;
        awburst_C <= awburst_N;
        awcache_C <= awcache_N;
        awid_C <= awid_N;
        awlen_C <= awlen_N;
        awlock_C <= awlock_N;
        awprot_C <= awprot_N;
        awqos_C <= awqos_N;
        awregion_C <= awregion_N;
        awsize_C <= awsize_N;

        paddr_C <= paddr_N;
        plen_C <= plen_N;
        done_C <= done_N;

        if (m_axi_wlast && m_axi_wvalid && m_axi_wready) begin
            cnt_W <= 0;
        end else if (m_axi_wvalid && m_axi_wready) begin
            cnt_W <= cnt_W + 1'b1;
        end
    end
end

// NSL
always_comb begin
    unique case (state_C)
        ST_IDLE:
            state_N = s_axi_awvalid ? ST_PARSE : ST_IDLE;

        ST_PARSE:
            state_N = (done_C & m_axi_awvalid & m_axi_awready) ? ST_IDLE : ST_PARSE;
    endcase
end

// DP
always_comb begin
    awaddr_N = awaddr_C;
    awburst_N = awburst_C;
    awcache_N = awcache_C;
    awid_N = awid_C;
    awlen_N = awlen_C;
    awlock_N = awlock_C;
    awprot_N = awprot_C;
    awqos_N = awqos_C;
    awregion_N = awregion_C;
    awsize_N = awsize_C;

    paddr_N = paddr_C;
    plen_N = plen_C;
    done_N = done_C;

    slen = ((STRIPE_FRAG_SIZE >> BEAT_LOG_BITS) - (((s_axi_awaddr - MEM_OFFSET) & lsb_mask) >> BEAT_LOG_BITS)) - 1;
    clen = ((STRIPE_FRAG_SIZE >> BEAT_LOG_BITS) - ((awaddr_C & lsb_mask) >> BEAT_LOG_BITS)) - 1;

    s_axi_awready = 1'b0;
    m_axi_awvalid = 1'b0;

    unique case (state_C)
        ST_IDLE: begin
            if (s_axi_awvalid) begin
                s_axi_awready = 1'b1;

                awburst_N = s_axi_awburst;
                awcache_N = s_axi_awcache;
                awid_N = s_axi_awid;
                awlock_N = s_axi_awlock;
                awprot_N = s_axi_awprot;
                awqos_N = s_axi_awqos;
                awregion_N = s_axi_awregion;
                awsize_N = s_axi_awsize;

                awaddr_remapped = s_axi_awaddr - MEM_OFFSET;

                paddr_N = (awaddr_remapped[FRAG_LOG_BITS+:N_STRIPE_CHAN_BITS] << MC_SIZE) | (awaddr_remapped & lsb_mask) | ((awaddr_remapped & msb_mask) >> N_STRIPE_CHAN_BITS) + MEM_OFFSET;
                awaddr_N = ((awaddr_remapped >> FRAG_LOG_BITS) << FRAG_LOG_BITS) + STRIPE_FRAG_SIZE;           

                if (slen < s_axi_awlen) begin
                    plen_N = slen;
                    awlen_N = s_axi_awlen - slen - 1;
                    done_N = 1'b0;
                end else begin
                    plen_N = s_axi_awlen;
                    awlen_N = 0;
                    done_N = 1'b1;
                end
            end
        end

        ST_PARSE: begin
            if (m_axi_awready) begin
                m_axi_awvalid = 1'b1;

                awaddr_remapped = awaddr_C;

                paddr_N = (awaddr_remapped[FRAG_LOG_BITS+:N_STRIPE_CHAN_BITS] << MC_SIZE) | (awaddr_remapped & lsb_mask) | ((awaddr_remapped & msb_mask) >> N_STRIPE_CHAN_BITS) + MEM_OFFSET;
                awaddr_N = ((awaddr_remapped >> FRAG_LOG_BITS) << FRAG_LOG_BITS) + STRIPE_FRAG_SIZE; 
    
                if (clen < awlen_C) begin
                    plen_N = clen;
                    awlen_N = awlen_C - clen - 1;
                    done_N = 1'b0;
                end else begin
                    plen_N = awlen_C;
                    awlen_N = 0;
                    done_N = 1'b1;
                end
            end
        end        
    endcase
end

// AW
assign m_axi_awaddr = paddr_C;
assign m_axi_awburst = awburst_C;
assign m_axi_awcache = awcache_C;
assign m_axi_awid = awid_C;
assign m_axi_awlen = plen_C;
assign m_axi_awlock = awlock_C;
assign m_axi_awprot = awprot_C;
assign m_axi_awqos = awqos_C;
assign m_axi_awregion = awregion_C;
assign m_axi_awsize = awsize_C;

// B
assign s_axi_bid = m_axi_bid;
assign s_axi_bresp = m_axi_bresp;
assign s_axi_bvalid = seq_src.data ? m_axi_bvalid : 1'b0;
assign m_axi_bready = seq_src.data ? s_axi_bready : 1'b1;

// W
assign m_axi_wdata = s_axi_wdata;
assign m_axi_wstrb = s_axi_wstrb;
assign m_axi_wvalid = s_axi_wvalid;
assign s_axi_wready = m_axi_wready;
assign m_axi_wlast = (s_axi_wlast || (cnt_W == FRAG_BEATS - 1));

// SEQ
metaIntf #(.STYPE(logic)) seq_snk ();
metaIntf #(.STYPE(logic)) seq_src ();
queue_meta #(.QDEPTH(N_OUTSTANDING_STRIPE)) inst_seq_que (.aclk(aclk), .aresetn(aresetn), .s_meta(seq_snk), .m_meta(seq_src));

assign seq_snk.data = done_C;
assign seq_src.ready = m_axi_bvalid & s_axi_bready;
assign seq_snk.valid = m_axi_awvalid & m_axi_awready;

endmodule