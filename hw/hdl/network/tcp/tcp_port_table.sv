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

/**
 * @brief   Arbitration of incoming port listen requests
 *
 * Arbitrates between listen requests coming from all vFPGAs. 
 * Also forwards the incoming notifications to the appropriate vFPGA.
 *
 */
module tcp_port_table (
    input  logic 									aclk,
	input  logic 									aresetn,

    metaIntf.s                                      s_listen_req [N_REGIONS],
    metaIntf.m                                      m_listen_req,

    metaIntf.s                                      s_listen_rsp,
    metaIntf.m                                      m_listen_rsp [N_REGIONS],

    metaIntf.s                                      s_notify,
    metaIntf.m                                      m_notify [N_REGIONS]
);

`ifdef MULT_REGIONS

// -- Constants
localparam integer H_ORDER = 8;
localparam integer H_SIZE = 2 ** H_ORDER;
localparam integer H_DATA_BITS = 8;
localparam integer KEY_BITS = 16;

// -- Regs and signals
typedef enum logic[2:0] {ST_IDLE, ST_HASH, ST_LUP, ST_CHECK, 
                         ST_RSP_COL, ST_SEND, ST_RSP_WAIT} state_t;
logic [2:0] state_C, state_N;

logic [KEY_BITS-1:0] port_C, port_N;
logic [H_ORDER-1:0] hash_C, hash_N;
logic [N_REGIONS_BITS-1:0] vfid_C, vfid_N;

logic [H_ORDER-1:0] hash_out_req;

logic [H_DATA_BITS/8-1:0] a_we;
logic [H_DATA_BITS-1:0] a_data_out;
logic [H_DATA_BITS-1:0] b_data_out;
logic b_en;

logic [N_REGIONS_BITS-1:0] vfid_arb;

logic hit;

// Requests -------------------------------------------------------------------------
// ----------------------------------------------------------------------------------

// Arbitration
metaIntf #(.STYPE(tcp_listen_req_t)) listen_req_arb ();

meta_arbiter #(
    .DATA_BITS($bits(tcp_listen_req_t))
) inst_tcp_port_arb_in (
    .aclk(aclk), 
    .aresetn(aresetn), 
    .s_meta(s_listen_req), 
    .m_meta(listen_req_arb), 
    .id_out(vfid_arb)
);

// REG
always_ff @( posedge aclk ) begin : REG_LISTEN
    if(aresetn == 1'b0) begin
        state_C <= ST_IDLE;

        port_C <= 'X;
        hash_C <= 'X;
        vfid_C <= 'X;
    else begin
        state_C <= state_N;

        port_C <= port_N;
        hash_C <= hash_N;
        vfid_C <= vfid_N;
    end
end

// NSL
always_comb begin : NSL_LISTEN
    state_N = state_C;

    case (state_C)
        ST_IDLE:
            state_N = listen_req_arb.valid ? ST_HASH : ST_IDLE;
        
        ST_HASH: 
            state_N = ST_LUP;
        ST_LUP:
            state_N = ST_CHECK;
        ST_CHECK:
            if(hit)
                state_N = ST_RSP_COL;
            else
                state_N = ST_SEND;
                
        ST_RSP_COL:
            state_N = m_listen_rsp[vfid_C].ready ? ST_IDLE : ST_RSP_COL;
        ST_SEND:
            state_N = m_listen_req.ready ? ST_RSP_WAIT : ST_SEND;
        ST_RSP_WAIT:
            state_N = (s_listen_rsp.valid & s_listen_rsp.ready) ? ST_IDLE : ST_RSP_WAIT;
    endcase
end

// DP
always_comb begin : DP_LISTEN
    port_N = port_C;
    hash_N = hash_C;
    vfid_N = vfid_C;

    listen_req_arb.ready = 1'b0;

    m_listen_req.valid = 1'b0;
    m_listen_req.data = port_C;

    s_listen_rsp.ready = 1'b0;

    for(int i = 0; i < N_REGIONS; i++) begin
        m_listen_rsp[i].valid = 1'b0;
        m_listen_rsp[i].data = 0;
    end

    a_we = 0;

    case (state_C)
        ST_IDLE: begin
            if(listen_req_arb.valid) begin
                listen_req_arb.ready = 1'b1;
                port_N = s_listen_req.data.ip_port;
                vfid_N = vfid_arb;
            end    
        end 

        ST_HASH: begin 
            hash_N = hash_out_req;
        end

        ST_RSP_COL: begin
            m_listen_rsp[vfid_C].valid = 1'b1;
            m_listen_rsp[vfid_C].data = 1;
        end

        ST_SEND: begin
            m_listen_req.valid = 1'b1;
        end

        ST_RSP_WAIT: begin
            s_listen_rsp.ready = m_listen_rsp[vfid_C].ready;
            m_listen_rsp[vfid_C].valid = s_listen_rsp.valid;
            m_listen_rsp[vfid_C].data = s_listen_rsp.data;

            if(s_listen_rsp.valid & s_listen_rsp.ready) begin
                if(s_listen_rsp.data[0]) begin
                     a_we = ~0;
                end
            end
        end

        default: 
    endcase

end

// Hit
assign hit = a_data_out[H_DATA_BITS-1] == 1'b1;

// Hash function
tcp_hash_16 inst_tcp_hash_16_req (.key_in(port_C), .hash_out(hash_out_req));

// Notifications --------------------------------------------------------------------
// ----------------------------------------------------------------------------------
logic stall;
logic [H_ORDER-1:0] hash_out_not;
metaIntf #(.STYPE(tcp_notify_t)) notify_s [4] ();
logic [N_REGIONS_BITS-1:0] not_que_vfid;

// REG
always_ff @( posedge aclk ) begin : REG_NOT
    if(aresetn == 1'b0) begin
        for(int i = 0; i < 3; i++) begin
            notify_s[i].valid <= 1'b0;
            notify_s[i].data <= 'X;
        end
    else begin
        if(~stall) begin
            notify_s[0].valid <= s_notify.valid;
            notify_s[0].data <= s_notify.data;

            notify_s[1].valid <= notify_s[0].valid;
            notify_s[1].data <= hash_out_not;

            notify_s[2].valid <= notify_s[1].valid;
            notify_s[2].data <= notify_s[1].data;
        end
    end
end

tcp_hash_16 inst_tcp_hash_16_not (.key_in(s_notify.data.ip_port), .hash_out(hash_out_not));

assign stall = ~m_notify.ready;
assign s_notify.ready = ~stall;

// Notify queue
queue_stream #(
    .QTYPE(logic [N_REGIONS_BITS+$bits(tcp_notify_t)]),
    .QDEPTH(N_OUTSTANDING)
) inst_not_que (
    .aclk(aclk),
    .aresetn(aresetn),
    .val_snk(notify_s[2].valid),
    .rdy_snk(notify_s[2].ready),
    .data_snk({b_data_out[N_REGIONS_BITS-1:0], notify_s[2].data}),
    .val_src(notify_s[3].valid),
    .rdy_src(notify_s[3].ready),
    .data_src({not_que_vfid, notify_s[3].data})
);

// DP
always_comb begin : DP_NOT
    for(int i = 0; i < N_REGIONS; i++) begin
        m_notify[i].valid = 1'b0;
        m_notify[i].data = notify_s[3].data;
    end

    m_notify[not_que_vfid].valid = notify_s[3].valid;
    notify_s[3].ready = m_notify[not_que_vfid].ready;
end

// Hash table -----------------------------------------------------------------------
// ----------------------------------------------------------------------------------
ram_tp_nc #(
    .ADDR_BITS(H_ORDER),
    .DATA_BITS(H_DATA_BITS)
) inst_tcp_port_hash (
    .clk(aclk),
    .a_en(1'b1),
    .a_we(a_we),
    .a_addr(hash_C),
    .b_en(~stall),
    .b_addr(notify_s[1].data.dst_port),
    .a_data_in(vfid_C),
    .a_data_out(a_data_out),
    .b_data_out(b_data_out)
);

`else

`META_ASSIGN(s_listen_req[0], m_listen_req)
`META_ASSIGN(s_listen_rsp, m_listen_rsp[0])
`META_ASSIGN(s_notify, m_notify[0])

`endif


endmodule