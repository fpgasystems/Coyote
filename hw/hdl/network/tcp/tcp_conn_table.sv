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
 * @brief   TCP connection table
 * 
 * Arbitrates between open requests from vFPGAs.
 *
 */
module tcp_conn_table (
    input  logic 									aclk,
	input  logic 									aresetn,

    metaIntf.s                                      s_open_req [N_REGIONS],
    metaIntf.m                                      m_open_req,

    metaIntf.s                                      s_close_req [N_REGIONS],
    metaIntf.m                                      m_close_req,

    metaIntf.s                                      s_open_rsp,
    metaIntf.m                                      m_open_rsp [N_REGIONS]
);

`ifdef MULT_REGIONS

// -- Constants
localparam integer H_SIZE = 8;
localparam integer H_DATA_BITS = 8;
localparam integer KEY_BITS = 48;

// -- Regs and signals
typedef enum logic[3:0] {ST_IDLE, ST_HASH_REQ, ST_HASH_RSP, ST_LUP_REQ, ST_LUP_RSP, ST_CHECK, 
                         ST_SEND, ST_RSP_COL, ST_RSP_WAIT} state_t;
logic [3:0] state_C, state_N;

logic [15:0] port_C, port_N;
logic [31:0] addr_C, addr_N;
logic [H_SIZE-1:0] hash_C, hash_N;
logic [N_REGIONS_BITS-1:0] vfid_C, vfid_N;

logic [H_SIZE-1:0] hash_out;

logic [H_DATA_BITS/8-1:0] a_we;
logic [H_DATA_BITS-1:0] a_data_out;
logic [H_DATA_BITS-1:0] b_data_out;
logic b_en;
logic [3:0] entry_val;

logic [N_REGIONS_BITS-1:0] vfid_open_arb;
logic [N_REGIONS_BITS-1:0] vfid_close_arb;

logic hit;
logic [N_REGIONS_BITS-1:0] vfid;

// Arbitration open requests
metaIntf #(.STYPE(tcp_open_req_t)) open_req_arb ();

meta_arbiter #(
    .DATA_BITS($bits(tcp_open_req_t))
) inst_tcp_open_req_arb_in (
    .aclk(aclk), 
    .aresetn(aresetn), 
    .s_meta(s_open_req), 
    .m_meta(open_req_arb), 
    .id_out(vfid_open_arb)
);

// Arbitration close requests
meta_arbiter #(
    .DATA_BITS($bits(tcp_close_req_t))
) inst_tcp_close_req_arb_in (
    .aclk(aclk), 
    .aresetn(aresetn), 
    .s_meta(s_close_req), 
    .m_meta(m_close_req), 
    .id_out(vfid_close_arb)
);

// REG
always_ff @( posedge aclk ) begin : REG
    if(aresetn == 1'b0) begin
        state_C <= ST_IDLE;

        port_C <= 'X;
        addr_C <= 'X;
        hash_C <= 'X;
        vfid_C <= 'X;
    else begin
        state_C <= state_N;

        port_C <= port_N;
        addr_C <= addr_N;
        hash_C <= hash_N;
        vfid_C <= vfid_N;
end

// NSL
always_comb begin : NSL
    state_N = state_C;

    case (state_C)
        ST_IDLE:
            if(s_open_rsp.valid)
                state_N = ST_HASH_RSP;
            if(open_req_arb.valid)
                state_N = ST_HASH_REQ;

        ST_HASH_REQ:
            state_N = ST_LUP_REQ;
        ST_LUP_REQ: 
            state_N = ST_CHECK;
        ST_CHECK:
            if(hit) 
                state_N = ST_RSP_COL;
            else
                state_N = ST_SEND;
        ST_SEND:
            state_N = m_open_req.ready ? ST_IDLE : ST_SEND;

        ST_HASH_RSP:
            state_N = ST_LUP_RSP;
        ST_LUP_RSP: 
            state_N = ST_RSP_WAIT;
        ST_RSP_WAIT: 
            state_N = m_open_rsp[vfid_C].ready ? ST_IDLE : ST_RSP_WAIT;

        ST_RSP_COL:
            state_N = m_open_rsp[vfid_C].ready ? ST_IDLE : ST_RSP_COL;
    endcase
end

// DP
always_comb begin : DP
    port_N = port_C;
    addr_N = addr_C;
    hash_N = hash_C;
    vfid_N = vfid_C;

    open_req_arb.ready = 1'b0;

    m_open_req.valid = 1'b0;
    m_open_req.data.ip_port = port_C;
    m_open_req.data.ip_address = addr_C;

    for(int i = 0; i < N_REGIONS; i++) begin
        m_open_rsp[i].valid = 1'b0;
        m_open_rsp[i].data = 0;
    end

    a_we = 0;
    entry_val = 0;

    case (state_C)
        ST_IDLE: begin
            if(s_open_rsp.valid) begin
                s_open_rsp.ready = 1'b1;
                port_N = s_open_rsp.data.ip_port;
                addr_N = s_open_rsp.data.ip_address;
            end
            else if(open_req_arb.valid) begin
                open_req_arb.ready = 1'b1;
                port_N = open_req_arb.data.ip_port;
                addr_N = open_req_arb.data.ip_address;
                vfid_N = vfid_arb;
            end   
            else if(open_req_arb.valid) begin
                open_req_arb.ready = 1'b1;
                port_N = open_req_arb.data;
                vfid_N = vfid_arb;
            end

        end 

        ST_HASH_REQ: begin 
            hash_N = hash_out_req;
        end

        ST_CHECK: begin
            if(!hit) begin
                a_we = ~0;
                entry_val = 4'b8;
            end 
        end

        ST_HASH_RSP: begin
            hash_N = hash_out_rsp;
        end

        ST_RSP_COL: begin
            m_open_rsp[vfid_C].valid = 1'b1;
        end

        ST_SEND: begin
            m_open_req.valid = 1'b1;
        end

        ST_RSP_WAIT: begin
            s_open_rsp.ready = m_open_rsp[vfid].ready;
            m_open_rsp[vfid].valid = s_open_rsp.valid;
            m_open_rsp[vfid].data = s_open_rsp.data;

            if(s_open_rsp.valid & s_open_rsp.ready) begin
                a_we = ~0;
            end
        end

        default: 
    endcase

end

// Hit
assign hit = a_data_out[H_DATA_BITS-1] == 1'b1;
assign vfid = a_data_out[N_REGIONS_BITS-1:0];

// Hash function
tcp_hash_48 inst_tcp_hash_function_req (.key_in({addr_c, port_C}), .hash_out(hash_out_req));
tcp_hash_48 inst_tcp_hash_function_rsp (.key_in({addr_c, port_C}), .hash_out(hash_out_rsp));

// Hash table
ram_tp_nc #(
    .ADDR_BITS(H_SIZE),
    .DATA_BITS(H_DATA_BITS)
) inst_tcp_port_hash (
    .clk(aclk),
    .a_en(1'b1),
    .a_we(a_we),
    .a_addr(hash_C),
    .b_en(1'b1),
    .b_addr(hash_C),
    .a_data_in({entry_val, vfid_C}),
    .a_data_out(a_data_out),
    .b_data_out(b_data_out)
);

`else

`META_ASSIGN(s_open_req[0], m_open_req)
`META_ASSIGN(s_close_req[0], m_close_req)
`META_ASSIGN(s_open_rsp, m_open_rsp[0])

`endif


endmodule