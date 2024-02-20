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

module axi_stripe_a (
    input  logic                        aclk,
    input  logic                        aresetn,
    
    // AR
    input  logic[AXI_ADDR_BITS-1:0]     s_axi_aaddr,
    input  logic[1:0]		            s_axi_aburst,
    input  logic[3:0]		            s_axi_acache,
    input  logic[AXI_ID_BITS-1:0]       s_axi_aid,
    input  logic[7:0]		            s_axi_alen,
    input  logic[0:0]		            s_axi_alock,
    input  logic[2:0]		            s_axi_aprot,
    input  logic[3:0]		            s_axi_aqos,
    input  logic[3:0]		            s_axi_aregion,
    input  logic[2:0]		            s_axi_asize,
    output logic			            s_axi_aready,
    input  logic			            s_axi_avalid,

    output  logic[AXI_ADDR_BITS-1:0]    m_axi_aaddr,
    output  logic[1:0]		            m_axi_aburst,
    output  logic[3:0]		            m_axi_acache,
    output  logic[AXI_ID_BITS-1:0]      m_axi_aid,
    output  logic[7:0]		            m_axi_alen,
    output  logic[0:0]		            m_axi_alock,
    output  logic[2:0]		            m_axi_aprot,
    output  logic[3:0]		            m_axi_aqos,
    output  logic[3:0]		            m_axi_aregion,
    output  logic[2:0]		            m_axi_asize,
    input   logic			            m_axi_aready,
    output  logic			            m_axi_avalid,

    // Mux 
    metaIntf.m                         mux
);

localparam integer N_OUTSTANDING_STRIPE = 8 * N_OUTSTANDING;
localparam integer FRAG_LOG_BITS = $clog2(DDR_FRAG_SIZE);
localparam integer BEAT_LOG_BITS = $clog2(AXI_DATA_BITS/8);
localparam integer BLEN_BITS = LEN_BITS - BEAT_LOG_BITS;

// FSM
typedef enum logic[0:0] {ST_IDLE, ST_PARSE} state_t;
logic[0:0] state_C, state_N;

logic [AXI_ADDR_BITS-1:0] aaddr_C, aaddr_N;
logic [1:0] aburst_C, aburst_N;
logic [3:0] acache_C, acache_N;
logic [N_DDR_CHAN_BITS-1:0] aid_C, aid_N;
logic [7:0] alen_C, alen_N;
logic [0:0] alock_C, alock_N;
logic [2:0] aprot_C, aprot_N;
logic [3:0] aqos_C, aqos_N;
logic [3:0] aregion_C, aregion_N;
logic [2:0] asize_C, asize_N;

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

metaIntf #(.STYPE(logic[1+N_DDR_CHAN_BITS+8-1:0])) seq_snk (); // ctl, id, len

// REG
always_ff @(posedge aclk) begin
    if(~aresetn) begin
        state_C <= ST_IDLE;

        aaddr_C <= 'X;
        aburst_C <= 'X;
        acache_C <= 'X;
        aid_C <= 'X;
        alen_C <= 'X;
        alock_C <= 'X;
        aprot_C <= 'X;
        aqos_C <= 'X;
        aregion_C <= 'X;
        asize_C <= 'X;

        paddr_C <= 'X;
        plen_C <= 'X;
        done_C <= 1'b0;
    end
    else begin
        state_C <= state_N;

        aaddr_C <= aaddr_N;
        aburst_C <= aburst_N;
        acache_C <= acache_N;
        aid_C <= aid_N;
        alen_C <= alen_N;
        alock_C <= alock_N;
        aprot_C <= aprot_N;
        aqos_C <= aqos_N;
        aregion_C <= aregion_N;
        asize_C <= asize_N;

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
            state_N = s_axi_avalid ? ST_PARSE : ST_IDLE;

        ST_PARSE:
            state_N = (done_C & m_axi_aready & seq_snk.ready) ? ST_IDLE : ST_PARSE;
        
    endcase
end

// DP
always_comb begin
    aaddr_N = aaddr_C;
    aburst_N = aburst_C;
    acache_N = acache_C;
    aid_N = aid_C;
    alen_N = alen_C;
    alock_N = alock_C;
    aprot_N = aprot_C;
    aqos_N = aqos_C;
    aregion_N = aregion_C;
    asize_N = asize_C;

    paddr_N = paddr_C;
    plen_N = plen_C;
    done_N = done_C;

    slen = ((DDR_FRAG_SIZE >> BEAT_LOG_BITS) - ((s_axi_aaddr & lsb_mask) >> BEAT_LOG_BITS)) - 1;
    clen = ((DDR_FRAG_SIZE >> BEAT_LOG_BITS) - ((aaddr_C & lsb_mask) >> BEAT_LOG_BITS)) - 1;

    // Sink
    s_axi_aready = 1'b0;

    // Src
    m_axi_avalid = 1'b0;

    // Seq
    seq_snk.valid = 1'b0;
    seq_snk.data = {done_C, aid_C, plen_C};

    case (state_C)
        ST_IDLE: begin
            if(s_axi_avalid) begin
                s_axi_aready = 1'b1;

                aaddr_N = s_axi_aaddr;
                aburst_N = s_axi_aburst;
                acache_N = s_axi_acache;
                aid_N = s_axi_aid;
                alock_N = s_axi_alock;
                aprot_N = s_axi_aprot;
                aqos_N = s_axi_aqos;
                aregion_N = s_axi_aregion;
                asize_N = s_axi_asize;

                paddr_N = (s_axi_aaddr[FRAG_LOG_BITS+:N_DDR_CHAN_BITS] << DDR_CHAN_SIZE) | (s_axi_aaddr & lsb_mask) | ((s_axi_aaddr & msb_mask) >> N_DDR_CHAN_BITS);
                aaddr_N = ((s_axi_aaddr >> FRAG_LOG_BITS) << FRAG_LOG_BITS) + DDR_FRAG_SIZE;           
                if(slen < s_axi_alen) begin
                    plen_N = slen;
                    alen_N = s_axi_alen - slen - 1;
                    aid_N = s_axi_aaddr[FRAG_LOG_BITS+:N_DDR_CHAN_BITS];
                    done_N = 1'b0;
                end
                else begin
                    plen_N = s_axi_alen;
                    alen_N = 0;
                    aid_N = s_axi_aaddr[FRAG_LOG_BITS+:N_DDR_CHAN_BITS];
                    done_N = 1'b1;
                end
            end
        end

        ST_PARSE: begin
            if(m_axi_aready && seq_snk.ready) begin
                m_axi_avalid = 1'b1;
                seq_snk.valid = 1'b1;

                paddr_N = (aaddr_C[FRAG_LOG_BITS+:N_DDR_CHAN_BITS] << DDR_CHAN_SIZE) | (aaddr_C & lsb_mask) | ((aaddr_C & msb_mask) >> N_DDR_CHAN_BITS);
                aaddr_N = ((aaddr_C >> FRAG_LOG_BITS) << FRAG_LOG_BITS) + DDR_FRAG_SIZE; 
                if(clen < alen_C) begin
                    plen_N = clen;
                    alen_N = alen_C - clen - 1;
                    aid_N = aaddr_C[FRAG_LOG_BITS+:N_DDR_CHAN_BITS];
                    done_N = 1'b0;
                end
                else begin
                    plen_N = alen_C;
                    alen_N = 0;
                    aid_N = aaddr_C[FRAG_LOG_BITS+:N_DDR_CHAN_BITS];
                    done_N = 1'b1;
                end
            end
        end        

    endcase
end

// AR
assign m_axi_aaddr = paddr_C;
assign m_axi_aburst = aburst_C;
assign m_axi_acache = acache_C;
assign m_axi_aid = aid_C;
assign m_axi_alen = plen_C;
assign m_axi_alock = alock_C;
assign m_axi_aprot = aprot_C;
assign m_axi_aqos = aqos_C;
assign m_axi_aregion = aregion_C;
assign m_axi_asize = asize_C;

// SEQ
queue_meta #(.QDEPTH(N_OUTSTANDING_STRIPE)) inst_seq_que (.aclk(aclk), .aresetn(aresetn), .s_meta(seq_snk), .m_meta(mux));

/*
ila_rd inst_ila_rd (
    .clk(aclk),
    .probe0(aaddr_C[39:0]), // 40
    .probe1(alen_C), // 8
    .probe2(paddr_C[39:0]), // 40
    .probe3(plen_C), // 8
    .probe4(slen), // 8
    .probe5(clen), // 8
    .probe6(state_C), 
    .probe7(s_axi_aaddr[39:0]), // 40
    .probe8(s_axi_alen), // 8
    .probe9(s_axi_avalid),
    .probe10(s_axi_aready),
    .probe11(m_axi_aaddr[39:0]), // 40
    .probe12(m_axi_alen), // 8
    .probe13(m_axi_avalid),
    .probe14(m_axi_aready)
);
*/

endmodule