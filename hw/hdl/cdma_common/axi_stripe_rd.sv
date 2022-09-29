/**
  * Copyright (c) 2021, Systems Group, ETH Zurich
  * All rights reserved.
  *
  * Redistribution and use in source and binary forms, with or without modification,
  * are permitted provided that the following conditions are met:
  *
  * 1. Redistributions of source code must retain the above copyright notice,
  * this list of conditions and the following disclaimer.
  * 2. Redistributions in binary form must reproduce the above copyright notice,
  * this list of conditions and the following disclaimer in the documentation
  * and/or other materials provided with the distribution.
  * 3. Neither the name of the copyright holder nor the names of its contributors
  * may be used to endorse or promote products derived from this software
  * without specific prior written permission.
  *
  * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
  * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
  * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
  * IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
  * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
  * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
  * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
  * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
  * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
  */

`timescale 1ns / 1ps

import lynxTypes::*;

module axi_stripe_rd (
    input  logic                        aclk,
    input  logic                        aresetn,
    
    // AR
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

    // R
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

`ifdef MULT_DDR_CHAN

localparam integer N_OUTSTANDING_STRIPE = 8 * N_OUTSTANDING;
localparam integer FRAG_LOG_BITS = $clog2(DDR_FRAG_SIZE);
localparam integer BEAT_LOG_BITS = $clog2(AXI_DATA_BITS/8);

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

logic [AXI_ADDR_BITS-1:0] lsb_mask;
assign lsb_mask = (1 << FRAG_LOG_BITS) - 1;
logic [AXI_ADDR_BITS-1:0] chan_mask;
always_comb begin
    chan_mask = 0;
    chan_mask[FRAG_LOG_BITS+:N_DDR_CHAN_BITS] = ~0;
end
logic [AXI_ADDR_BITS-1:0] msb_mask;
assign msb_mask = (~lsb_mask) << N_DDR_CHAN_BITS;

// REG
always_ff @(posedge aclk) begin
    if(~aresetn) begin
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
    end
    else begin
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
    state_N = state_C;

    case (state_C)
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

    slen = ((DDR_FRAG_SIZE >> BEAT_LOG_BITS) - ((s_axi_araddr & lsb_mask) >> BEAT_LOG_BITS)) - 1;
    clen = ((DDR_FRAG_SIZE >> BEAT_LOG_BITS) - ((araddr_C & lsb_mask) >> BEAT_LOG_BITS)) - 1;

    // Sink
    s_axi_arready = 1'b0;

    // Src
    m_axi_arvalid = 1'b0;

    case (state_C)
        ST_IDLE: begin
            if(s_axi_arvalid) begin
                s_axi_arready = 1'b1;

                araddr_N = s_axi_araddr;
                arburst_N = s_axi_arburst;
                arcache_N = s_axi_arcache;
                arid_N = s_axi_arid;
                arlock_N = s_axi_arlock;
                arprot_N = s_axi_arprot;
                arqos_N = s_axi_arqos;
                arregion_N = s_axi_arregion;
                arsize_N = s_axi_arsize;

                paddr_N = (s_axi_araddr[FRAG_LOG_BITS+:N_DDR_CHAN_BITS] << DDR_CHAN_SIZE) | (s_axi_araddr & lsb_mask) | ((s_axi_araddr & msb_mask) >> N_DDR_CHAN_BITS);
                araddr_N = ((s_axi_araddr >> FRAG_LOG_BITS) << FRAG_LOG_BITS) + DDR_FRAG_SIZE;           
                if(slen < s_axi_arlen) begin
                    plen_N = slen;
                    arlen_N = s_axi_arlen - slen - 1;
                    done_N = 1'b0;
                end
                else begin
                    plen_N = s_axi_arlen;
                    arlen_N = 0;
                    done_N = 1'b1;
                end
            end
        end

        ST_PARSE: begin
            m_axi_arvalid = 1'b1;
            if(m_axi_arready) begin
                paddr_N = (araddr_C[FRAG_LOG_BITS+:N_DDR_CHAN_BITS] << DDR_CHAN_SIZE) | (araddr_C & lsb_mask) | ((araddr_C & msb_mask) >> N_DDR_CHAN_BITS);
                araddr_N = ((araddr_C >> FRAG_LOG_BITS) << FRAG_LOG_BITS) + DDR_FRAG_SIZE; 
                if(clen < arlen_C) begin
                    plen_N = clen;
                    arlen_N = arlen_C - clen - 1;
                    done_N = 1'b0;
                end
                else begin
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

metaIntf #(.STYPE(logic)) seq_snk ();
metaIntf #(.STYPE(logic)) seq_src ();

assign seq_snk.valid = m_axi_arvalid & m_axi_arready;
assign seq_snk.data = done_C;

// SEQ
queue_meta #(.QDEPTH(N_OUTSTANDING_STRIPE)) inst_seq_que (.aclk(aclk), .aresetn(aresetn), .s_meta(seq_snk), .m_meta(seq_src));

// R
assign s_axi_rdata = m_axi_rdata;
assign s_axi_rid = m_axi_arid;
assign s_axi_rlast = seq_src.data;
assign s_axi_rresp = m_axi_rresp;
assign s_axi_rvalid = m_axi_rvalid;
assign m_axi_rready = s_axi_rready;

assign seq_src.ready = s_axi_rvalid & s_axi_rready;

/*
ila_rd inst_ila_rd (
    .clk(aclk),
    .probe0(araddr_C[39:0]), // 40
    .probe1(arlen_C), // 8
    .probe2(paddr_C[39:0]), // 40
    .probe3(plen_C), // 8
    .probe4(slen), // 8
    .probe5(clen), // 8
    .probe6(state_C), 
    .probe7(s_axi_araddr[39:0]), // 40
    .probe8(s_axi_arlen), // 8
    .probe9(s_axi_arvalid),
    .probe10(s_axi_arready),
    .probe11(m_axi_araddr[39:0]), // 40
    .probe12(m_axi_arlen), // 8
    .probe13(m_axi_arvalid),
    .probe14(m_axi_arready),
    .probe15(s_axi_rvalid),
    .probe16(s_axi_rready),
    .probe17(s_axi_rlast),
    .probe18(s_axi_rdata) // 512
);
*/

`else

assign m_axi_araddr 	= s_axi_araddr;	
assign m_axi_arburst 	= s_axi_arburst;
assign m_axi_arcache	= s_axi_arcache;
assign m_axi_arid		= s_axi_arid;	
assign m_axi_arlen		= s_axi_arlen;	
assign m_axi_arlock		= s_axi_arlock;	
assign m_axi_arprot		= s_axi_arprot;	
assign m_axi_arqos		= s_axi_arqos;	
assign m_axi_arregion	= s_axi_arregion;
assign m_axi_arsize		= s_axi_arsize;	
assign m_axi_arvalid 	= s_axi_arvalid;
assign s_axi_arready	= m_axi_arready;
assign s_axi_rdata		= m_axi_rdata;	
assign s_axi_rid 		= m_axi_rid;	
assign s_axi_rlast 		= m_axi_rlast;	
assign s_axi_rresp		= m_axi_rresp;	
assign m_axi_rready		= s_axi_rready;	
assign s_axi_rvalid 	= m_axi_rvalid;	

`endif

endmodule