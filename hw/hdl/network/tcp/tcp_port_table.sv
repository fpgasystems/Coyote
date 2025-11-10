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
 * @brief   Port opening
 *
 *
 */
module tcp_port_table (
    input  logic 									aclk,
	input  logic 									aresetn,

    metaIntf.s                                      s_listen_req,
    metaIntf.m                                      m_listen_req,

    metaIntf.s                                      s_listen_rsp,
    metaIntf.m                                      m_listen_rsp,

    input  logic [TCP_PORT_ORDER-1:0]               port_addr,
    output logic [TCP_PORT_TABLE_DATA_BITS-1:0]     rsid_out
);

// -- Constants
localparam integer KEY_BITS = 16;
localparam integer TCP_PORT_TABLE_DATA_BITS = 16;

// -- Regs and signals
typedef enum logic[2:0] {ST_IDLE, ST_LUP, ST_WAIT, ST_CHECK, 
                         ST_RSP_COL, ST_SEND, ST_RSP_WAIT} state_t;
logic [2:0] state_C, state_N;

logic [TCP_IP_PORT_BITS-1:0] port_C, port_N;
logic [TCP_PORT_REQ_BITS-1:0] port_lup_C, port_lup_N;
logic [TCP_RSESSION_BITS-1:0:0] rsid_C, rsid_N;
logic [DEST_BITS-1:0] vfid_C, vfid_N;

logic [TCP_PORT_TABLE_DATA_BITS/8-1:0] a_we;
logic [TCP_PORT_TABLE_DATA_BITS-1:0] a_data_out;
logic [TCP_PORT_TABLE_DATA_BITS-1:0] b_data_out;
logic b_en;

logic hit;

// Requests -------------------------------------------------------------------------
// ----------------------------------------------------------------------------------

// REG
always_ff @( posedge aclk ) begin : REG_LISTEN
    if(aresetn == 1'b0) begin
        state_C <= ST_IDLE;

        port_C <= 'X;
        port_lup_C <= 'X;
        rsid_C <= 'X;
        vfid_C <= 'X;
    else begin
        state_C <= state_N;

        port_C <= port_N;
        port_lup_C <= port_lup_n;
        rsid_C <= rsid_N;
        vfid_C <= vfid_N;
    end
end

// NSL
always_comb begin : NSL_LISTEN
    state_N = state_C;

    case (state_C)
        ST_IDLE:
            state_N = s_listen_req.valid ? ST_LUP : ST_IDLE;
        
        ST_LUP:
            state_N = ST_WAIT;
        ST_WAIT:
            state_N = ST_CHECK;
        ST_CHECK:
            if(hit)
                state_N = ST_RSP_COL;
            else
                state_N = ST_SEND;
                
        ST_RSP_COL:
            state_N = m_listen_rsp.ready ? ST_IDLE : ST_RSP_COL;
        ST_SEND:
            state_N = m_listen_req.ready ? ST_RSP_WAIT : ST_SEND;
        ST_RSP_WAIT:
            state_N = (s_listen_rsp.valid & s_listen_rsp.ready) ? ST_IDLE : ST_RSP_WAIT;
    endcase
end

// DP
always_comb begin : DP_LISTEN
    port_N = port_C;
    port_lup_N = port_lup_C;
    rsid_N = rsid_C;
    vfid_N = vfid_C;

    s_listen_req.ready = 1'b0;

    m_listen_req.valid = 1'b0;
    m_listen_req.data.ip_port = port_C;

    s_listen_rsp.ready = 1'b0;

    m_listen_rsp.valid = 1'b0;
    m_listen_rsp.data = 0;
    m_listen_rsp.data.vfid = vfid_C;

    a_we = 0;

    case (state_C)
        ST_IDLE: begin
            if(s_listen_req.valid) begin
                s_listen_req.ready = 1'b1;
                port_lup_N = s_listen_req.data.ip_port - TCP_PORT_OFFS;
                
                port_N = s_listen_req.data.ip_port;
                rsid_N = {s_listen_req.data.vfid, s_listen_req.data.pid, s_listen_req.data.dest};
                vfid_N = s_listen_req.data.vfid;
            end    
        end

        ST_RSP_COL: begin
            m_listen_rsp.valid = 1'b1;
            m_listen_rsp.data.open_port_success = 0;
        end

        ST_SEND: begin
            m_listen_req.valid = 1'b1;
        end

        ST_RSP_WAIT: begin
            s_listen_rsp.ready = m_listen_rsp.ready;
            m_listen_rsp.valid = s_listen_rsp.valid;
            m_listen_rsp.data.open_port_success = s_listen_rsp.data.open_port_success;

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
assign hit = a_data_out[TCP_RSESSION_BITS] == 1'b1;

// Port table
ram_tp_c #(
    .ADDR_BITS(TCP_PORT_ORDER),
    .DATA_BITS(TCP_PORT_TABLE_DATA_BITS)
) inst_tcp_port_table (
    .clk(aclk),
    .a_en(1'b1),
    .a_we(a_we),
    .a_addr(port_lup_C[TCP_PORT_ORDER-1:0]),
    .b_en(1'b1),
    .b_addr(port_addr),
    .a_data_in({2'b01, rsid_C}),
    .a_data_out(a_data_out),
    .b_data_out(rsid_out)
);

endmodule