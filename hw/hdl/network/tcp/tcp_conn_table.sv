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

`include "axi_macros.svh"
`include "lynx_macros.svh"

/**
 * @brief   TCP connection table
 * 
 * Arbitrates between open requests from vFPGAs.
 *
 */
module tcp_conn_table (
    input  logic 									aclk,
	input  logic 									aresetn,

    metaIntf.s                                      s_open_req,
    metaIntf.m                                      m_open_req,
    metaIntf.m                                      m_close_req,

    metaIntf.s                                      s_open_rsp,
    metaIntf.m                                      m_open_rsp,

    metaIntf.s                                      s_notify_opened,
    output logic [TCP_PORT_ORDER-1:0]               port_addr,
    input  logic [TCP_PORT_TABLE_DATA_BITS-1:0]     rsid_in,

    metaIntf.s                                      s_rx_meta,
    metaIntf.m                                      m_rx_meta_r,
    AXI4S.s                                         s_axis_rx,
    AXI4S.m                                         m_axis_rx_r,

    metaIntf.s                                      s_tx_meta_r,
    metaIntf.m                                      m_tx_meta,
    AXI4S.s                                         s_axis_tx_r,
    AXI4S.m                                         m_axis_tx
);


// -- Regs and signals
typedef enum logic[3:0] {ST_IDLE, ST_LUP_PORT, ST_CLOSE, ST_LUP_OPEN,
                         ST_LUP_PORT_WAIT, ST_PORT_RSP,
                         ST_OPEN_RSP_WAIT, ST_OPEN, ST_OPEN_RSP_FAIL, ST_OPEN_RSP_SUCCESS} state_t;
logic [3:0] state_C, state_N;

logic [TCP_IP_PORT_BITS-1:0] port_C, port_N;
logic [TCP_SID_BITS-1:0] sid_C, sid_N;
logic [DEST_BITS-1:0] vfid_C, vfid_N;
logic [PID_BITS-1:0] pid_C, pid_N;
logic [DEST_BITS-1:0] dest_C, dest_N;
logic [TCP_IP_PORT_BITS-1:0] ip_port_C, ip_port_N;
logic [TCP_IP_ADDRESS_BITS-1:0] ip_address_C, ip_address_N;

// Tables
logic [1:0] rx_wr;
logic [TCP_SID_BITS-1:0] rx_addr;
logic rx_en;
logic [DEST_BITS+PID_BITS+DEST_BITS-1:0] rx_data;
logic [DEST_BITS+PID_BITS+DEST_BITS-1:0] rx_data_out;
logic [DEST_BITS+PID_BITS+DEST_BITS-1:0] rx_rsid;

logic [1:0] tx_wr;
logic [DEST_BITS+PID_BITS] tx_addr;
logic tx_en;
logic [TCP_SID_BITS-1:0] tx_data;
logic [TCP_SID_BITS-1:0] tx_data_out;
logic [TCP_SID_BITS-1:0] tx_data_sid;

// REG
always_ff @( posedge aclk ) begin : REG_LISTEN
    if(aresetn == 1'b0) begin
        state_C <= ST_IDLE;

        port_C <= 'X;
        sid_C <= 'X;
        vfid_C <= 'X;
        pid_C <= 'X;
        dest_C <= 'X;
        ip_port_C <= 'X;
        ip_address_C <= 'X;
    else begin
        state_C <= state_N;

        port_C <= port_N;
        sid_C <= sid_N;
        vfid_C <= vfid_N;
        pid_C <= pid_N;
        dest_C <= dest_N;
        ip_port_C <= ip_port_N;
        ip_address_C <= ip_address_N;
    end
end

// NSL
always_comb begin : NSL
    state_N = state_C;

    case (state_C)
        ST_IDLE: begin
            if(s_notify_opened.valid) begin
                state_N = ST_LUP_PORT;
            end
            else if(s_open_req.valid) begin
                if(s_open_req.data.close)
                    state_N = ST_CLOSE;
                else
                    state_N = ST_LUP_OPEN;
            end
        end

        ST_LUP_PORT:
            state_N = ST_LUP_PORT_WAIT;
        ST_LUP_PORT_WAIT: 
            state_N = ST_PORT_RSP;
        ST_PORT_RSP:
            state_N = m_rx_meta_q.ready && m_tx_meta_q.ready ? ST_PORT_RSP : ST_IDLE;

        ST_CLOSE:
            state_N = m_close_req.ready ? ST_IDLE : ST_CLOSE;

        ST_LUP_OPEN:
            state_N = m_open_req.ready ? ST_OPEN_RSP_WAIT : ST_LUP_OPEN;
        ST_OPEN_RSP_WAIT:
            state_N = s_open_rsp.valid ? (s_open_rsp.data.success ? ST_OPEN : ST_OPEN_RSP_FAIL) : ST_OPEN_RSP_WAIT;
        ST_OPEN:
            state_N = ST_OPEN_RSP_SUCCESS;
        ST_OPEN_RSP_SUCCESS | ST_OPEN_RSP_FAIL:
            if(m_open_rsp.ready) state_N = ST_IDLE;
    endcase
end

// DP
always_comb begin : DP
    port_N = port_C;
    sid_N = sid_C;
    vfid_N = vfid_C;
    pid_N = pid_C;
    dest_N = dest_C;
    ip_port_N = ip_port_C;
    ip_address_N = ip_address_C;

    s_notify_opened.ready = 1'b0;

    s_open_req.ready = 1'b0;

    m_close_req.valid = 1'b0;
    m_close_req.data = 0;
    m_close_req.data.sid = tx_data_out;

    m_open_req.valid = 1'b0;
    m_open_req.data = 0;
    m_open_req.data.ip_port = ip_port_C;
    m_open_req.data.ip_address = ip_address_C;

    s_open_rsp.ready = 1'b0;
    m_open_rsp.valid = 1'b0;
    m_open_rsp.data = 0;
    m_open_rsp.data.vfid = vfid_C;
    m_open_rsp.data.pid = pid_C;
    m_open_rsp.data.success = 1'b0;

    rx_addr = 0;
    rx_data = 0;
    rx_wr = 0;

    tx_addr = 0;
    tx_data = 0;
    tx_wr = 0;


    port_addr = port_C[TCP_PORT_ORDER-1:0];

    case (state_C)
        ST_IDLE: begin
            if(s_notify_opened.valid) begin
                s_notify_opened.ready = 1'b1;

                port_N = s_notify_opened.data.dst_port - TCP_PORT_OFFS;
                sid_N = s_notify_opened.data.sid;
            end
            else if(s_open_req.valid) begin
                s_open_req.ready = 1'b1;

                vfid_N = s_open_req.data.vfid;
                pid_N = s_open_req.data.pid;
                dest_N = s_open_req.data.dest;
                ip_port_N = s_open_req.data.ip_port;
                ip_address_N = s_open_req.data.ip_address;
            end
        end

        ST_PORT_RSP: begin
            rx_addr = sid_C[TCP_SID_BITS];
            rx_data[0+:DEST_BITS+PID_BITS+DEST_BITS] = rsid_in[0+:DEST_BITS+PID_BITS+DEST_BITS];

            tx_addr = rsid_in[DEST_BITS+:PID_BITS+DEST_BITS];
            tx_data = sid_C[TCP_SID_BITS];

            if(rsid_in[TCP_RSESSION_BITS-1]) begin
                tx_wr = ~0;
                rx_wr = ~0;
            end
        end

        ST_CLOSE: begin
            m_close_req.valid = 1'b1;
        end

        ST_LUP_OPEN: begin
            m_open_req.valid = 1'b1;
        end

        ST_OPEN_RSP_WAIT: begin
            s_open_rsp.ready = 1'b1;
            sid_N = s_open_rsp.data.sid;
        end

        ST_OPEN: begin
            rx_addr = sid_C[TCP_SID_BITS];
            rx_data[0+:PID_BITS+DEST_BITS] = {vfid_C, pid_C, dest_C};

            tx_addr = {vfid_C, pid_C};
            tx_data = sid_C[TCP_SID_BITS];

            tx_wr = ~0;
            rx_wr = ~0;
        end

        ST_OPEN_RSP_FAIL: begin
            m_open_rsp.valid = 1'b1;
            m_open_rsp.data.success = 1'b0;
        end

        ST_OPEN_RSP_SUCCESS: begin
            m_open_rsp.valid = 1'b1;
            m_open_rsp.data.success = 1'b1;
        end

    endcase
end

// RX table
ram_tp_nc #(
    .ADDR_BITS(TCP_SID_BITS),
    .DATA_BITS(16)
) isnt_rx_conn (
    .clk(aclk),
    .a_en(1'b1),
    .a_we(rx_wr),
    .a_addr(rx_addr),
    .b_en(rx_en),
    .b_addr(s_rx_meta.data.sid),
    .a_data_in(rx_data),
    .a_data_out(rx_data_out),
    .b_data_out(rx_rsid)
);

// TX table
ram_tp_nc #(
    .ADDR_BITS(DEST_BITS+PID_BITS),
    .DATA_BITS(16)
) isnt_tx_conn (
    .clk(aclk),
    .a_en(1'b1),
    .a_we(tx_wr),
    .a_addr(tx_addr),
    .b_en(tx_en),
    .b_addr({s_tx_meta_r.data.vfid, s_tx_meta_r.data.pid}),
    .a_data_in(tx_data),
    .a_data_out(tx_data_out),
    .b_data_out(tx_sid)
);

metaIntf #(.STYPE(tcp_meta_r_t)) rx_meta_q ();
metaIntf #(.STYPE(tcp_meta_t)) tx_meta_q ();

always_ff @(posedge aclk) begin
    if (~aresetn) begin
        rx_meta_q.valid <= 1'b0;
        tx_meta_q.valid <= 1'b0;

        rx_meta_q.data <= 0;
        tx_meta_q.data <= 0;
    end
    else begin
        if(rx_meta_q.ready) begin
            rx_meta_q.valid <= s_rx_meta.valid;

            rx_meta_q.data.len <= s_rx_meta.data.len;
            rx_meta_q.data.dest <= rx_rsid[0+:DEST_BITS];
            rx_meta_q.data.pid <= rx_rsid[DEST_BITS+:PID_BITS];
            rx_meta_q.data.vfid <= rx_rsid[DEST_BITS+PID_BITS+:DEST_BITS];
        end

        if(tx_meta_q.ready) begin
            tx_meta_q.valid <= s_tx_meta_r.valid;

            tx_meta_q.data.len <= s_tx_meta_r.data.len;
            tx_meta_q.data.sid <= tx_sid;
        end       
    end
end

queue_meta #(.QDEPTH(16)) inst_rx_q (.aclk(aclk), .aresetn(aresetn), .s_meta(rx_meta_q), .m_meta(m_rx_meta_r));
queue_meta #(.QDEPTH(16)) inst_tx_q (.aclk(aclk), .aresetn(aresetn), .s_meta(tx_meta_q), .m_meta(m_tx_meta));

assign rx_en = rx_meta_q_ready;
assign tx_en = tx_meta_q_ready;

`AXIS_ASSIGN(s_axis_rx, m_axis_rx_r)
`AXIS_ASSIGN(s_axis_tx_r, m_axis_tx)


endmodule