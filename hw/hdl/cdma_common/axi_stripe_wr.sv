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

module axi_stripe_wr (
    input  logic                        aclk,
    input  logic                        aresetn,
    
    // AW
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

    // B
    output logic[AXI_ID_BITS-1:0]       s_axi_bid,
    output logic[1:0]                   s_axi_bresp,
    input  logic                        s_axi_bready,
    output logic                        s_axi_bvalid,

    input  logic[AXI_ID_BITS-1:0]       m_axi_bid,
    input  logic[1:0]                   m_axi_bresp,
    output logic                        m_axi_bready,
    input  logic                        m_axi_bvalid,

    // W
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

`ifdef MULT_DDR_CHAN

localparam integer N_OUTSTANDING_STRIPE = 8 * N_OUTSTANDING;
localparam integer FRAG_LOG_BITS = $clog2(DDR_FRAG_SIZE);
localparam integer BEAT_LOG_BITS = $clog2(AXI_DATA_BITS/8);

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
    end
    else begin
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
    end
end

// NSL
always_comb begin
    state_N = state_C;

    case (state_C)
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

    slen = ((DDR_FRAG_SIZE >> BEAT_LOG_BITS) - ((s_axi_awaddr & lsb_mask) >> BEAT_LOG_BITS)) - 1;
    clen = ((DDR_FRAG_SIZE >> BEAT_LOG_BITS) - ((awaddr_C & lsb_mask) >> BEAT_LOG_BITS)) - 1;

    // Sink
    s_axi_awready = 1'b0;

    // Src
    m_axi_awvalid = 1'b0;

    case (state_C)
        ST_IDLE: begin
            if(s_axi_awvalid) begin
                s_axi_awready = 1'b1;

                awaddr_N = s_axi_awaddr;
                awburst_N = s_axi_awburst;
                awcache_N = s_axi_awcache;
                awid_N = s_axi_awid;
                awlock_N = s_axi_awlock;
                awprot_N = s_axi_awprot;
                awqos_N = s_axi_awqos;
                awregion_N = s_axi_awregion;
                awsize_N = s_axi_awsize;

                paddr_N = (s_axi_awaddr[FRAG_LOG_BITS+:N_DDR_CHAN_BITS] << DDR_CHAN_SIZE) | (s_axi_awaddr & lsb_mask) | ((s_axi_awaddr & msb_mask) >> N_DDR_CHAN_BITS);
                awaddr_N = ((s_axi_awaddr >> FRAG_LOG_BITS) << FRAG_LOG_BITS) + DDR_FRAG_SIZE;           
                if(slen < s_axi_awlen) begin
                    plen_N = slen;
                    awlen_N = s_axi_awlen - slen - 1;
                    done_N = 1'b0;
                end
                else begin
                    plen_N = s_axi_awlen;
                    awlen_N = 0;
                    done_N = 1'b1;
                end
            end
        end

        ST_PARSE: begin
            m_axi_awvalid = 1'b1;
            if(m_axi_awready) begin
                paddr_N = (awaddr_C[FRAG_LOG_BITS+:N_DDR_CHAN_BITS] << DDR_CHAN_SIZE) | (awaddr_C & lsb_mask) | ((awaddr_C & msb_mask) >> N_DDR_CHAN_BITS);
                awaddr_N = ((awaddr_C >> FRAG_LOG_BITS) << FRAG_LOG_BITS) + DDR_FRAG_SIZE; 
                if(clen < awlen_C) begin
                    plen_N = clen;
                    awlen_N = awlen_C - clen - 1;
                    done_N = 1'b0;
                end
                else begin
                    plen_N = awlen_C;
                    awlen_N = 0;
                    done_N = 1'b1;
                end
            end
        end        

    endcase
end

// AR
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

metaIntf #(.STYPE(logic)) seq_snk ();
metaIntf #(.STYPE(logic)) seq_src ();

assign seq_snk.valid = m_axi_awvalid & m_axi_awready;
assign seq_snk.data = done_C;

// SEQ
queue_meta #(.QDEPTH(N_OUTSTANDING_STRIPE)) inst_seq_que (.aclk(aclk), .aresetn(aresetn), .s_meta(seq_snk), .m_meta(seq_src));

// B
assign s_axi_bid = m_axi_bid;
assign s_axi_bresp = m_axi_bresp;
assign s_axi_bvalid = seq_src.data ? m_axi_bvalid : 1'b0;
assign m_axi_bready = seq_src.data ? s_axi_bready : 1'b1;

assign seq_src.ready = s_axi_bvalid & s_axi_bready;

// W
assign m_axi_wdata = s_axi_wdata;
assign m_axi_wlast = s_axi_wlast;
assign m_axi_wstrb = s_axi_wstrb;
assign m_axi_wvalid = s_axi_wvalid;
assign s_axi_wready = m_axi_wready;

/*
ila_wr inst_ila_wr (
    .clk(aclk),
    .probe0(awaddr_C[39:0]), // 40
    .probe1(awlen_C), // 8
    .probe2(paddr_C[39:0]), // 40
    .probe3(plen_C), // 8
    .probe4(slen), // 8
    .probe5(clen), // 8
    .probe6(state_C), 
    .probe7(s_axi_awaddr[39:0]), // 40
    .probe8(s_axi_awlen), // 8
    .probe9(s_axi_awvalid),
    .probe10(s_axi_awready),
    .probe11(m_axi_awaddr[39:0]), // 40
    .probe12(m_axi_awlen), // 8
    .probe13(m_axi_awvalid),
    .probe14(m_axi_awready),
    .probe15(s_axi_wvalid),
    .probe16(s_axi_wready),
    .probe17(s_axi_wstrb), // 64
    .probe18(s_axi_wdata), // 512
    .probe19(s_axi_bvalid),
    .probe20(s_axi_bready)
);
*/

`else

assign m_axi_awaddr 	= s_axi_awaddr;	
assign m_axi_awburst 	= s_axi_awburst;
assign m_axi_awcache	= s_axi_awcache;
assign m_axi_awid		= s_axi_awid;	
assign m_axi_awlen		= s_axi_awlen;	
assign m_axi_awlock		= s_axi_awlock;	
assign m_axi_awprot		= s_axi_awprot;	
assign m_axi_awqos		= s_axi_awqos;	
assign m_axi_awregion	= s_axi_awregion;
assign m_axi_awsize		= s_axi_awsize;	
assign m_axi_awvalid 	= s_axi_awvalid;
assign s_axi_awready	= m_axi_awready;
assign m_axi_wdata		= s_axi_wdata;	
assign m_axi_wlast		= s_axi_wlast;	
assign m_axi_wstrb		= s_axi_wstrb;	
assign s_axi_wready		= m_axi_wready;	
assign m_axi_wvalid		= s_axi_wvalid;	
assign s_axi_bid		= m_axi_bid;	
assign s_axi_bresp		= m_axi_bresp;	
assign m_axi_bready		= s_axi_bready;	
assign s_axi_bvalid		= m_axi_bvalid;	

`endif

endmodule