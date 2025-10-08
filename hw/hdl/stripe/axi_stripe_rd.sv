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

module axi_stripe_rd (
    input  logic                        aclk,
    input  logic                        aresetn,
    
    input  logic[AXI_ADDR_BITS-1:0]     s_axi_araddr,
    input  logic[1:0]		            s_axi_arburst,
    input  logic[3:0]		            s_axi_arcache,
    input  logic[AXI_ID_BITS-1:0]       s_axi_arid,
    input  logic[7:0]		            s_axi_arlen,
    input  logic[0:0]		            s_axi_arlock,
    input  logic[2:0]		            s_axi_arprot,
    input  logic[3:0]		            s_axi_arqos,
    input  logic[3:0]		            s_axi_arregion,
    input  logic[2:0]		            s_axi_arsize,
    output logic			            s_axi_arready,
    input  logic			            s_axi_arvalid,

    output  logic[AXI_ADDR_BITS-1:0]    m_axi_araddr,
    output  logic[1:0]		            m_axi_arburst,
    output  logic[3:0]		            m_axi_arcache,
    output  logic[AXI_ID_BITS-1:0]      m_axi_arid,
    output  logic[7:0]		            m_axi_arlen,
    output  logic[0:0]		            m_axi_arlock,
    output  logic[2:0]		            m_axi_arprot,
    output  logic[3:0]		            m_axi_arqos,
    output  logic[3:0]		            m_axi_arregion,
    output  logic[2:0]		            m_axi_arsize,
    input   logic			            m_axi_arready,
    output  logic			            m_axi_arvalid,

    output logic[AXI_DATA_BITS-1:0]     s_axi_rdata,
    output logic[AXI_ID_BITS-1:0]       s_axi_rid,
    output logic                        s_axi_rlast,
    output logic[1:0]                   s_axi_rresp,
    input  logic                        s_axi_rready,
    output logic                        s_axi_rvalid,

    input  logic[AXI_DATA_BITS-1:0]     m_axi_rdata,
    input  logic[AXI_ID_BITS-1:0]       m_axi_rid,
    input  logic                        m_axi_rlast,
    input  logic[1:0]                   m_axi_rresp,
    output logic                        m_axi_rready,
    input  logic                        m_axi_rvalid
);

localparam integer FRAG_LOG_BITS = $clog2(STRIPE_FRAG_SIZE);
localparam integer BEAT_LOG_BITS = $clog2(AXI_DATA_BITS/8);
localparam integer N_OUTSTANDING_STRIPE = 8 * N_OUTSTANDING;

// FSM
typedef enum logic[0:0] {ST_IDLE, ST_PARSE} state_t;
logic[0:0] state_C, state_N;

logic [AXI_ADDR_BITS-1:0] araddr_C, araddr_N;
logic [1:0] arburst_C, arburst_N;
logic [3:0] arcache_C, arcache_N;
logic [1:0] arid_C, arid_N;
logic [7:0] arlen_C, arlen_N;
logic [0:0] arlock_C, arlock_N;
logic [2:0] arprot_C, arprot_N;
logic [3:0] arqos_C, arqos_N;
logic [3:0] arregion_C, arregion_N;
logic [2:0] arsize_C, arsize_N;

logic [AXI_ADDR_BITS-1:0] paddr_C, paddr_N;
logic [7:0] plen_C, plen_N;
logic done_C, done_N;

logic [7:0] clen;
logic [7:0] slen;

logic [AXI_ADDR_BITS-1:0] araddr_remapped;

logic [AXI_ADDR_BITS-1:0] lsb_mask;
assign lsb_mask = (1 << FRAG_LOG_BITS) - 1;

logic [AXI_ADDR_BITS-1:0] msb_mask;
assign msb_mask = (~lsb_mask) << N_STRIPE_CHAN_BITS;

// REG
always_ff @(posedge aclk) begin
    if (aresetn == 1'b0) begin
        state_C <= ST_IDLE;

        araddr_C <= 'X;
        arburst_C <= 'X;
        arcache_C <= 'X;
        arid_C <= 'X;
        arlen_C <= 'X;
        arlock_C <= 'X;
        arprot_C <= 'X;
        arqos_C <= 'X;
        arregion_C <= 'X;
        arsize_C <= 'X;

        paddr_C <= 'X;
        plen_C <= 'X;
        done_C <= 1'b0;
    end else begin
        state_C <= state_N;

        araddr_C <= araddr_N;
        arburst_C <= arburst_N;
        arcache_C <= arcache_N;
        arid_C <= arid_N;
        arlen_C <= arlen_N;
        arlock_C <= arlock_N;
        arprot_C <= arprot_N;
        arqos_C <= arqos_N;
        arregion_C <= arregion_N;
        arsize_C <= arsize_N;

        paddr_C <= paddr_N;
        plen_C <= plen_N;
        done_C <= done_N;
    end
end

// NSL
always_comb begin
    unique case (state_C)
        ST_IDLE:
            state_N = s_axi_arvalid ? ST_PARSE : ST_IDLE;

        ST_PARSE:
            state_N = (done_C & m_axi_arvalid & m_axi_arready) ? ST_IDLE : ST_PARSE;
    endcase
end

// DP
always_comb begin
    araddr_N = araddr_C;
    arburst_N = arburst_C;
    arcache_N = arcache_C;
    arid_N = arid_C;
    arlen_N = arlen_C;
    arlock_N = arlock_C;
    arprot_N = arprot_C;
    arqos_N = arqos_C;
    arregion_N = arregion_C;
    arsize_N = arsize_C;

    paddr_N = paddr_C;
    plen_N = plen_C;
    done_N = done_C;

    slen = ((STRIPE_FRAG_SIZE >> BEAT_LOG_BITS) - (((s_axi_araddr - MEM_OFFSET) & lsb_mask) >> BEAT_LOG_BITS)) - 1;
    clen = ((STRIPE_FRAG_SIZE >> BEAT_LOG_BITS) - ((araddr_C & lsb_mask) >> BEAT_LOG_BITS)) - 1;

    s_axi_arready = 1'b0;
    m_axi_arvalid = 1'b0;

    unique case (state_C)
        ST_IDLE: begin
            if (s_axi_arvalid) begin
                s_axi_arready = 1'b1;

                arburst_N = s_axi_arburst;
                arcache_N = s_axi_arcache;
                arid_N = s_axi_arid;
                arlock_N = s_axi_arlock;
                arprot_N = s_axi_arprot;
                arqos_N = s_axi_arqos;
                arregion_N = s_axi_arregion;
                arsize_N = s_axi_arsize;

                araddr_remapped = s_axi_araddr - MEM_OFFSET;

                paddr_N = (araddr_remapped[FRAG_LOG_BITS+:N_STRIPE_CHAN_BITS] << MC_SIZE) | (araddr_remapped & lsb_mask) | ((araddr_remapped & msb_mask) >> N_STRIPE_CHAN_BITS) + MEM_OFFSET;
                araddr_N = ((araddr_remapped >> FRAG_LOG_BITS) << FRAG_LOG_BITS) + STRIPE_FRAG_SIZE;           
                
                if (slen < s_axi_arlen) begin
                    plen_N = slen;
                    arlen_N = s_axi_arlen - slen - 1;
                    done_N = 1'b0;
                end else begin
                    plen_N = s_axi_arlen;
                    arlen_N = 0;
                    done_N = 1'b1;
                end
            end
        end

        ST_PARSE: begin
            if (m_axi_arready) begin
                m_axi_arvalid = 1'b1;

                araddr_remapped = araddr_C;

                paddr_N = (araddr_remapped[FRAG_LOG_BITS+:N_STRIPE_CHAN_BITS] << MC_SIZE) | (araddr_remapped & lsb_mask) | ((araddr_remapped & msb_mask) >> N_STRIPE_CHAN_BITS) + MEM_OFFSET;
                araddr_N = ((araddr_remapped >> FRAG_LOG_BITS) << FRAG_LOG_BITS) + STRIPE_FRAG_SIZE; 

                if (clen < arlen_C) begin
                    plen_N = clen;
                    arlen_N = arlen_C - clen - 1;
                    done_N = 1'b0;
                end else begin
                    plen_N = arlen_C;
                    arlen_N = 0;
                    done_N = 1'b1;
                end
            end
        end        
    endcase
end

// AR
assign m_axi_araddr = paddr_C;
assign m_axi_arburst = arburst_C;
assign m_axi_arcache = arcache_C;
assign m_axi_arid = arid_C;
assign m_axi_arlen = plen_C;
assign m_axi_arlock = arlock_C;
assign m_axi_arprot = arprot_C;
assign m_axi_arqos = arqos_C;
assign m_axi_arregion = arregion_C;
assign m_axi_arsize = arsize_C;

// R
assign s_axi_rdata = m_axi_rdata;
assign s_axi_rid = m_axi_arid;
assign s_axi_rlast = seq_src.data;
assign s_axi_rresp = m_axi_rresp;
assign s_axi_rvalid = m_axi_rvalid;
assign m_axi_rready = s_axi_rready;

// SEQ
metaIntf #(.STYPE(logic)) seq_snk ();
metaIntf #(.STYPE(logic)) seq_src ();
queue_meta #(.QDEPTH(N_OUTSTANDING_STRIPE)) inst_seq_que (.aclk(aclk), .aresetn(aresetn), .s_meta(seq_snk), .m_meta(seq_src));

assign seq_snk.data = done_C;
assign seq_src.ready = m_axi_rvalid & s_axi_rready;
assign seq_snk.valid = m_axi_arvalid & m_axi_arready;

endmodule