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
 * @brief   TCP/IP instantiation
 *
 * TCP/IP stack
 */
module tcp_stack #(
    parameter RX_DDR_BYPASS_EN = 1
) (
    input wire                  nclk,
    input wire                  nresetn,
    
    // Network interface streams
    AXI4S.s                     s_axis_rx,
    AXI4S.m                     m_axis_tx,    
    
    // Application interface streams
    metaIntf.s                  s_tcp_listen_req,
    metaIntf.m                  m_tcp_listen_rsp,
    metaIntf.s                  s_tcp_open_req,
    metaIntf.m                  m_tcp_open_rsp,
    metaIntf.s                  s_tcp_close_req,
    metaIntf.m                  m_tcp_notify,
    metaIntf.s                  s_tcp_rd_pkg,
    metaIntf.m                  m_tcp_rx_meta,
    metaIntf.s                  s_tcp_tx_meta,
    metaIntf.m                  m_tcp_tx_stat,

    AXI4S.s                     s_axis_tcp_tx,
    AXI4S.m                     m_axis_tcp_rx,

    // IP
    input wire[31:0]            local_ip_address,

    // Memory
    metaIntf.m                  m_tcp_mem_rd_cmd [N_TCP_CHANNELS],
    metaIntf.m                  m_tcp_mem_wr_cmd [N_TCP_CHANNELS],
    metaIntf.s                  s_tcp_mem_rd_sts [N_TCP_CHANNELS],
    metaIntf.s                  s_tcp_mem_wr_sts [N_TCP_CHANNELS],
    AXI4S.s                     s_axis_tcp_mem_rd [N_TCP_CHANNELS],
    AXI4S.m                     m_axis_tcp_mem_wr [N_TCP_CHANNELS],

    output logic                session_count_valid,
    output logic[15:0]          session_count_data
 );

localparam ddrPortNetworkRx = 1;
localparam ddrPortNetworkTx = 0;

generate

// Hash Table signals
`ifdef VITIS_HLS
metaIntf #(.STYPE(logic[96-1:0])) axis_ht_lup_req (.aclk(nclk), .aresetn(nresetn));
metaIntf #(.STYPE(logic[120-1:0])) axis_ht_lup_rsp (.aclk(nclk), .aresetn(nresetn));
metaIntf #(.STYPE(logic[144-1:0])) axis_ht_upd_req (.aclk(nclk), .aresetn(nresetn));
metaIntf #(.STYPE(logic[152-1:0])) axis_ht_upd_rsp (.aclk(nclk), .aresetn(nresetn));
`else 
metaIntf #(.STYPE(logic[72-1:0])) axis_ht_lup_req (.aclk(nclk), .aresetn(nresetn));
metaIntf #(.STYPE(logic[88-1:0])) axis_ht_lup_rsp (.aclk(nclk), .aresetn(nresetn));
metaIntf #(.STYPE(logic[88-1:0])) axis_ht_upd_req (.aclk(nclk), .aresetn(nresetn));
metaIntf #(.STYPE(logic[88-1:0])) axis_ht_upd_rsp (.aclk(nclk), .aresetn(nresetn));
`endif 

// Signals for registering
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_rxwrite_data (.aclk(nclk), .aresetn(nresetn));
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_rxread_data (.aclk(nclk), .aresetn(nresetn));
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_txwrite_data (.aclk(nclk), .aresetn(nresetn));
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_txread_data (.aclk(nclk), .aresetn(nresetn));

metaIntf #(.STYPE(logic[TCP_PORT_REQ_BITS-1:0])) axis_listen_port (.aclk(nclk), .aresetn(nresetn));
metaIntf #(.STYPE(logic[TCP_PORT_RSP_BITS-1:0]))  axis_listen_port_status (.aclk(nclk), .aresetn(nresetn));
metaIntf #(.STYPE(logic[TCP_OPEN_CONN_REQ_BITS-1:0])) axis_open_connection (.aclk(nclk), .aresetn(nresetn));
metaIntf #(.STYPE(logic[TCP_OPEN_CONN_RSP_BITS-1:0])) axis_open_status (.aclk(nclk), .aresetn(nresetn));
metaIntf #(.STYPE(logic[TCP_CLOSE_CONN_REQ_BITS-1:0])) axis_close_connection (.aclk(nclk), .aresetn(nresetn));

metaIntf #(.STYPE(logic[TCP_NOTIFY_BITS-1:0])) axis_notifications (.aclk(nclk), .aresetn(nresetn));
metaIntf #(.STYPE(logic[TCP_RD_PKG_REQ_BITS-1:0])) axis_read_package (.aclk(nclk), .aresetn(nresetn));
metaIntf #(.STYPE(logic[TCP_RX_META_BITS-1:0])) axis_rx_metadata (.aclk(nclk), .aresetn(nresetn));
metaIntf #(.STYPE(logic[TCP_TX_META_BITS-1:0])) axis_tx_metadata (.aclk(nclk), .aresetn(nresetn));
metaIntf #(.STYPE(logic[TCP_TX_STAT_BITS-1:0])) axis_tx_status (.aclk(nclk), .aresetn(nresetn));

wire[31:0] rx_buffer_data_count;
reg[15:0] rx_buffer_data_count_reg;
reg[15:0] rx_buffer_data_count_reg2;
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_rxbuffer2app (.aclk(nclk), .aresetn(nresetn));
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_tcp2rxbuffer (.aclk(nclk), .aresetn(nresetn));

if (RX_DDR_BYPASS_EN == 0) begin
    assign s_tcp_mem_rd_sts[ddrPortNetworkRx].ready = 1'b1;
end
assign s_tcp_mem_rd_sts[ddrPortNetworkTx].ready = 1'b1;


//
wire[71:0] axis_write_cmd_data [1:0];
wire[71:0] axis_read_cmd_data [1:0];
if (RX_DDR_BYPASS_EN == 0) begin
    assign m_tcp_mem_wr_cmd[ddrPortNetworkRx].data[0+:64] = {32'h0000_0000, axis_write_cmd_data[ddrPortNetworkRx][63:32]};
    assign m_tcp_mem_wr_cmd[ddrPortNetworkRx].data[64+:32] = {9'h00, axis_write_cmd_data[ddrPortNetworkRx][22:0]};
    assign m_tcp_mem_rd_cmd[ddrPortNetworkRx].data[0+:64] = {32'h0000_0000, axis_read_cmd_data[ddrPortNetworkRx][63:32]};
    assign m_tcp_mem_rd_cmd[ddrPortNetworkRx].data[64+:32] = {9'h00, axis_read_cmd_data[ddrPortNetworkRx][22:0]};
end
assign m_tcp_mem_wr_cmd[ddrPortNetworkTx].data[0+:64] = {32'h0000_0000, axis_write_cmd_data[ddrPortNetworkTx][63:32]};
assign m_tcp_mem_wr_cmd[ddrPortNetworkTx].data[64+:32] = {9'h00, axis_write_cmd_data[ddrPortNetworkTx][22:0]};
assign m_tcp_mem_rd_cmd[ddrPortNetworkTx].data[0+:64] = {32'h0000_0000, axis_read_cmd_data[ddrPortNetworkTx][63:32]};
assign m_tcp_mem_rd_cmd[ddrPortNetworkTx].data[64+:32] = {9'h00, axis_read_cmd_data[ddrPortNetworkTx][22:0]};


//TOE Module with RX_DDR_BYPASS disabled
if (RX_DDR_BYPASS_EN == 0) begin
toe_ip toe_inst_nb (

`ifdef VITIS_HLS
// Data output
.m_axis_tcp_data_TVALID(m_axis_tx.tvalid),
.m_axis_tcp_data_TREADY(m_axis_tx.tready),
.m_axis_tcp_data_TDATA(m_axis_tx.tdata), // output [63 : 0] AXI_M_Stream_TDATA
.m_axis_tcp_data_TKEEP(m_axis_tx.tkeep),
.m_axis_tcp_data_TLAST(m_axis_tx.tlast),
// Data input
.s_axis_tcp_data_TVALID(s_axis_rx.tvalid),
.s_axis_tcp_data_TREADY(s_axis_rx.tready),
.s_axis_tcp_data_TDATA(s_axis_rx.tdata),
.s_axis_tcp_data_TKEEP(s_axis_rx.tkeep),
.s_axis_tcp_data_TLAST(s_axis_rx.tlast),

// rx read commands
.m_axis_rxread_cmd_TVALID(m_tcp_mem_rd_cmd[ddrPortNetworkRx].valid),
.m_axis_rxread_cmd_TREADY(m_tcp_mem_rd_cmd[ddrPortNetworkRx].ready),
.m_axis_rxread_cmd_TDATA(axis_read_cmd_data[ddrPortNetworkRx]),
// rx write commands
.m_axis_rxwrite_cmd_TVALID(m_tcp_mem_wr_cmd[ddrPortNetworkRx].valid),
.m_axis_rxwrite_cmd_TREADY(m_tcp_mem_wr_cmd[ddrPortNetworkRx].ready),
.m_axis_rxwrite_cmd_TDATA(axis_write_cmd_data[ddrPortNetworkRx]),
// rx write status
.s_axis_rxwrite_sts_TVALID(s_tcp_mem_wr_sts[ddrPortNetworkRx].valid),
.s_axis_rxwrite_sts_TREADY(s_tcp_mem_wr_sts[ddrPortNetworkRx].ready),
.s_axis_rxwrite_sts_TDATA(s_tcp_mem_wr_sts[ddrPortNetworkRx].data),
// rx buffer read path
.s_axis_rxread_data_TVALID(axis_rxread_data.tvalid),
.s_axis_rxread_data_TREADY(axis_rxread_data.tready),
.s_axis_rxread_data_TDATA(axis_rxread_data.tdata),
.s_axis_rxread_data_TKEEP(axis_rxread_data.tkeep),
.s_axis_rxread_data_TLAST(axis_rxread_data.tlast),
// rx buffer write path
.m_axis_rxwrite_data_TVALID(axis_rxwrite_data.tvalid),
.m_axis_rxwrite_data_TREADY(axis_rxwrite_data.tready),
.m_axis_rxwrite_data_TDATA(axis_rxwrite_data.tdata),
.m_axis_rxwrite_data_TKEEP(axis_rxwrite_data.tkeep),
.m_axis_rxwrite_data_TLAST(axis_rxwrite_data.tlast),

// tx read commands
.m_axis_txread_cmd_TVALID(m_tcp_mem_rd_cmd[ddrPortNetworkTx].valid),
.m_axis_txread_cmd_TREADY(m_tcp_mem_rd_cmd[ddrPortNetworkTx].ready),
.m_axis_txread_cmd_TDATA(axis_read_cmd_data[ddrPortNetworkTx]),
//tx write commands
.m_axis_txwrite_cmd_TVALID(m_tcp_mem_wr_cmd[ddrPortNetworkTx].valid),
.m_axis_txwrite_cmd_TREADY(m_tcp_mem_wr_cmd[ddrPortNetworkTx].ready),
.m_axis_txwrite_cmd_TDATA(axis_write_cmd_data[ddrPortNetworkTx]),
// tx write status
.s_axis_txwrite_sts_TVALID(s_tcp_mem_wr_sts[ddrPortNetworkTx].valid),
.s_axis_txwrite_sts_TREADY(s_tcp_mem_wr_sts[ddrPortNetworkTx].ready),
.s_axis_txwrite_sts_TDATA(s_tcp_mem_wr_sts[ddrPortNetworkTx].data),
// tx read path
.s_axis_txread_data_TVALID(axis_txread_data.tvalid),
.s_axis_txread_data_TREADY(axis_txread_data.tready),
.s_axis_txread_data_TDATA(axis_txread_data.tdata),
.s_axis_txread_data_TKEEP(axis_txread_data.tkeep),
.s_axis_txread_data_TLAST(axis_txread_data.tlast),
// tx write path
.m_axis_txwrite_data_TVALID(axis_txwrite_data.tvalid),
.m_axis_txwrite_data_TREADY(axis_txwrite_data.tready),
.m_axis_txwrite_data_TDATA(axis_txwrite_data.tdata),
.m_axis_txwrite_data_TKEEP(axis_txwrite_data.tkeep),
.m_axis_txwrite_data_TLAST(axis_txwrite_data.tlast),
/// SmartCAM I/F ///
.m_axis_session_upd_req_TVALID(axis_ht_upd_req.valid),
.m_axis_session_upd_req_TREADY(axis_ht_upd_req.ready),
.m_axis_session_upd_req_TDATA(axis_ht_upd_req.data),

.s_axis_session_upd_rsp_TVALID(axis_ht_upd_rsp.valid),
.s_axis_session_upd_rsp_TREADY(axis_ht_upd_rsp.ready),
.s_axis_session_upd_rsp_TDATA(axis_ht_upd_rsp.data),

.m_axis_session_lup_req_TVALID(axis_ht_lup_req.valid),
.m_axis_session_lup_req_TREADY(axis_ht_lup_req.ready),
.m_axis_session_lup_req_TDATA(axis_ht_lup_req.data),
.s_axis_session_lup_rsp_TVALID(axis_ht_lup_rsp.valid),
.s_axis_session_lup_rsp_TREADY(axis_ht_lup_rsp.ready),
.s_axis_session_lup_rsp_TDATA(axis_ht_lup_rsp.data),

/* Application Interface */
// listen&close port
.s_axis_listen_port_req_TVALID(axis_listen_port.valid),
.s_axis_listen_port_req_TREADY(axis_listen_port.ready),
.s_axis_listen_port_req_TDATA(axis_listen_port.data),
.m_axis_listen_port_rsp_TVALID(axis_listen_port_status.valid),
.m_axis_listen_port_rsp_TREADY(axis_listen_port_status.ready),
.m_axis_listen_port_rsp_TDATA(axis_listen_port_status.data),

// notification & read request
.m_axis_notification_TVALID(axis_notifications.valid),
.m_axis_notification_TREADY(axis_notifications.ready),
.m_axis_notification_TDATA(axis_notifications.data),
.s_axis_rx_data_req_TVALID(axis_read_package.valid),
.s_axis_rx_data_req_TREADY(axis_read_package.ready),
.s_axis_rx_data_req_TDATA(axis_read_package.data),

// open&close connection
.s_axis_open_conn_req_TVALID(axis_open_connection.valid),
.s_axis_open_conn_req_TREADY(axis_open_connection.ready),
.s_axis_open_conn_req_TDATA(axis_open_connection.data),
.m_axis_open_conn_rsp_TVALID(axis_open_status.valid),
.m_axis_open_conn_rsp_TREADY(axis_open_status.ready),
.m_axis_open_conn_rsp_TDATA(axis_open_status.data),
.s_axis_close_conn_req_TVALID(axis_close_connection.valid),
.s_axis_close_conn_req_TREADY(axis_close_connection.ready),
.s_axis_close_conn_req_TDATA(axis_close_connection.data),

// rx data
.m_axis_rx_data_rsp_metadata_TVALID(axis_rx_metadata.valid),
.m_axis_rx_data_rsp_metadata_TREADY(axis_rx_metadata.ready),
.m_axis_rx_data_rsp_metadata_TDATA(axis_rx_metadata.data),
.m_axis_rx_data_rsp_TVALID(m_axis_tcp_rx.tvalid),
.m_axis_rx_data_rsp_TREADY(m_axis_tcp_rx.tready),
.m_axis_rx_data_rsp_TDATA(m_axis_tcp_rx.tdata),
.m_axis_rx_data_rsp_TKEEP(m_axis_tcp_rx.tkeep),
.m_axis_rx_data_rsp_TLAST(m_axis_tcp_rx.tlast),

// tx data
.s_axis_tx_data_req_metadata_TVALID(axis_tx_metadata.valid),
.s_axis_tx_data_req_metadata_TREADY(axis_tx_metadata.ready),
.s_axis_tx_data_req_metadata_TDATA(axis_tx_metadata.data),
.s_axis_tx_data_req_TVALID(s_axis_tcp_tx.tvalid),
.s_axis_tx_data_req_TREADY(s_axis_tcp_tx.tready),
.s_axis_tx_data_req_TDATA(s_axis_tcp_tx.tdata),
.s_axis_tx_data_req_TKEEP(s_axis_tcp_tx.tkeep),
.s_axis_tx_data_req_TLAST(s_axis_tcp_tx.tlast),
.m_axis_tx_data_rsp_TVALID(axis_tx_status.valid),
.m_axis_tx_data_rsp_TREADY(axis_tx_status.ready),
.m_axis_tx_data_rsp_TDATA(axis_tx_status.data),

.myIpAddress(local_ip_address),
.regSessionCount(session_count_data),
.regSessionCount_ap_vld(session_count_valid),
.ap_clk(nclk),                                                        // input aclk
.ap_rst_n(nresetn) 
`else 
// Data output
.m_axis_tcp_data_TVALID(m_axis_tx.tvalid),
.m_axis_tcp_data_TREADY(m_axis_tx.tready),
.m_axis_tcp_data_TDATA(m_axis_tx.tdata), // output [63 : 0] AXI_M_Stream_TDATA
.m_axis_tcp_data_TKEEP(m_axis_tx.tkeep),
.m_axis_tcp_data_TLAST(m_axis_tx.tlast),
// Data input
.s_axis_tcp_data_TVALID(s_axis_rx.tvalid),
.s_axis_tcp_data_TREADY(s_axis_rx.tready),
.s_axis_tcp_data_TDATA(s_axis_rx.tdata),
.s_axis_tcp_data_TKEEP(s_axis_rx.tkeep),
.s_axis_tcp_data_TLAST(s_axis_rx.tlast),

// rx read commands
.m_axis_rxread_cmd_V_TVALID(m_tcp_mem_rd_cmd[ddrPortNetworkRx].valid),
.m_axis_rxread_cmd_V_TREADY(m_tcp_mem_rd_cmd[ddrPortNetworkRx].ready),
.m_axis_rxread_cmd_V_TDATA(axis_read_cmd_data[ddrPortNetworkRx]),
// rx write commands
.m_axis_rxwrite_cmd_V_TVALID(m_tcp_mem_wr_cmd[ddrPortNetworkRx].valid),
.m_axis_rxwrite_cmd_V_TREADY(m_tcp_mem_wr_cmd[ddrPortNetworkRx].ready),
.m_axis_rxwrite_cmd_V_TDATA(axis_write_cmd_data[ddrPortNetworkRx]),
// rx write status
.s_axis_rxwrite_sts_V_TVALID(s_tcp_mem_wr_sts[ddrPortNetworkRx].valid),
.s_axis_rxwrite_sts_V_TREADY(s_tcp_mem_wr_sts[ddrPortNetworkRx].ready),
.s_axis_rxwrite_sts_V_TDATA(s_tcp_mem_wr_sts[ddrPortNetworkRx].data),
// rx buffer read path
.s_axis_rxread_data_TVALID(axis_rxread_data.tvalid),
.s_axis_rxread_data_TREADY(axis_rxread_data.tready),
.s_axis_rxread_data_TDATA(axis_rxread_data.tdata),
.s_axis_rxread_data_TKEEP(axis_rxread_data.tkeep),
.s_axis_rxread_data_TLAST(axis_rxread_data.tlast),
// rx buffer write path
.m_axis_rxwrite_data_TVALID(axis_rxwrite_data.tvalid),
.m_axis_rxwrite_data_TREADY(axis_rxwrite_data.tready),
.m_axis_rxwrite_data_TDATA(axis_rxwrite_data.tdata),
.m_axis_rxwrite_data_TKEEP(axis_rxwrite_data.tkeep),
.m_axis_rxwrite_data_TLAST(axis_rxwrite_data.tlast),

// tx read commands
.m_axis_txread_cmd_V_TVALID(m_tcp_mem_rd_cmd[ddrPortNetworkTx].valid),
.m_axis_txread_cmd_V_TREADY(m_tcp_mem_rd_cmd[ddrPortNetworkTx].ready),
.m_axis_txread_cmd_V_TDATA(axis_read_cmd_data[ddrPortNetworkTx]),
//tx write commands
.m_axis_txwrite_cmd_V_TVALID(m_tcp_mem_wr_cmd[ddrPortNetworkTx].valid),
.m_axis_txwrite_cmd_V_TREADY(m_tcp_mem_wr_cmd[ddrPortNetworkTx].ready),
.m_axis_txwrite_cmd_V_TDATA(axis_write_cmd_data[ddrPortNetworkTx]),
// tx write status
.s_axis_txwrite_sts_V_TVALID(s_tcp_mem_wr_sts[ddrPortNetworkTx].valid),
.s_axis_txwrite_sts_V_TREADY(s_tcp_mem_wr_sts[ddrPortNetworkTx].ready),
.s_axis_txwrite_sts_V_TDATA(s_tcp_mem_wr_sts[ddrPortNetworkTx].data),
// tx read path
.s_axis_txread_data_TVALID(axis_txread_data.tvalid),
.s_axis_txread_data_TREADY(axis_txread_data.tready),
.s_axis_txread_data_TDATA(axis_txread_data.tdata),
.s_axis_txread_data_TKEEP(axis_txread_data.tkeep),
.s_axis_txread_data_TLAST(axis_txread_data.tlast),
// tx write path
.m_axis_txwrite_data_TVALID(axis_txwrite_data.tvalid),
.m_axis_txwrite_data_TREADY(axis_txwrite_data.tready),
.m_axis_txwrite_data_TDATA(axis_txwrite_data.tdata),
.m_axis_txwrite_data_TKEEP(axis_txwrite_data.tkeep),
.m_axis_txwrite_data_TLAST(axis_txwrite_data.tlast),
/// SmartCAM I/F ///
.m_axis_session_upd_req_V_TVALID(axis_ht_upd_req.valid),
.m_axis_session_upd_req_V_TREADY(axis_ht_upd_req.ready),
.m_axis_session_upd_req_V_TDATA(axis_ht_upd_req.data),

.s_axis_session_upd_rsp_V_TVALID(axis_ht_upd_rsp.valid),
.s_axis_session_upd_rsp_V_TREADY(axis_ht_upd_rsp.ready),
.s_axis_session_upd_rsp_V_TDATA(axis_ht_upd_rsp.data),

.m_axis_session_lup_req_V_TVALID(axis_ht_lup_req.valid),
.m_axis_session_lup_req_V_TREADY(axis_ht_lup_req.ready),
.m_axis_session_lup_req_V_TDATA(axis_ht_lup_req.data),
.s_axis_session_lup_rsp_V_TVALID(axis_ht_lup_rsp.valid),
.s_axis_session_lup_rsp_V_TREADY(axis_ht_lup_rsp.ready),
.s_axis_session_lup_rsp_V_TDATA(axis_ht_lup_rsp.data),

/* Application Interface */
// listen&close port
.s_axis_listen_port_req_V_V_TVALID(axis_listen_port.valid),
.s_axis_listen_port_req_V_V_TREADY(axis_listen_port.ready),
.s_axis_listen_port_req_V_V_TDATA(axis_listen_port.data),
.m_axis_listen_port_rsp_V_TVALID(axis_listen_port_status.valid),
.m_axis_listen_port_rsp_V_TREADY(axis_listen_port_status.ready),
.m_axis_listen_port_rsp_V_TDATA(axis_listen_port_status.data),

// notification & read request
.m_axis_notification_V_TVALID(axis_notifications.valid),
.m_axis_notification_V_TREADY(axis_notifications.ready),
.m_axis_notification_V_TDATA(axis_notifications.data),
.s_axis_rx_data_req_V_TVALID(axis_read_package.valid),
.s_axis_rx_data_req_V_TREADY(axis_read_package.ready),
.s_axis_rx_data_req_V_TDATA(axis_read_package.data),

// open&close connection
.s_axis_open_conn_req_V_TVALID(axis_open_connection.valid),
.s_axis_open_conn_req_V_TREADY(axis_open_connection.ready),
.s_axis_open_conn_req_V_TDATA(axis_open_connection.data),
.m_axis_open_conn_rsp_V_TVALID(axis_open_status.valid),
.m_axis_open_conn_rsp_V_TREADY(axis_open_status.ready),
.m_axis_open_conn_rsp_V_TDATA(axis_open_status.data),
.s_axis_close_conn_req_V_V_TVALID(axis_close_connection.valid),
.s_axis_close_conn_req_V_V_TREADY(axis_close_connection.ready),
.s_axis_close_conn_req_V_V_TDATA(axis_close_connection.data),

// rx data
.m_axis_rx_data_rsp_metadata_V_V_TVALID(axis_rx_metadata.valid),
.m_axis_rx_data_rsp_metadata_V_V_TREADY(axis_rx_metadata.ready),
.m_axis_rx_data_rsp_metadata_V_V_TDATA(axis_rx_metadata.data),
.m_axis_rx_data_rsp_TVALID(m_axis_tcp_rx.tvalid),
.m_axis_rx_data_rsp_TREADY(m_axis_tcp_rx.tready),
.m_axis_rx_data_rsp_TDATA(m_axis_tcp_rx.tdata),
.m_axis_rx_data_rsp_TKEEP(m_axis_tcp_rx.tkeep),
.m_axis_rx_data_rsp_TLAST(m_axis_tcp_rx.tlast),

// tx data
.s_axis_tx_data_req_metadata_V_TVALID(axis_tx_metadata.valid),
.s_axis_tx_data_req_metadata_V_TREADY(axis_tx_metadata.ready),
.s_axis_tx_data_req_metadata_V_TDATA(axis_tx_metadata.data),
.s_axis_tx_data_req_TVALID(s_axis_tcp_tx.tvalid),
.s_axis_tx_data_req_TREADY(s_axis_tcp_tx.tready),
.s_axis_tx_data_req_TDATA(s_axis_tcp_tx.tdata),
.s_axis_tx_data_req_TKEEP(s_axis_tcp_tx.tkeep),
.s_axis_tx_data_req_TLAST(s_axis_tcp_tx.tlast),
.m_axis_tx_data_rsp_V_TVALID(axis_tx_status.valid),
.m_axis_tx_data_rsp_V_TREADY(axis_tx_status.ready),
.m_axis_tx_data_rsp_V_TDATA(axis_tx_status.data),

.myIpAddress_V(local_ip_address),
.regSessionCount_V(session_count_data),
.regSessionCount_V_ap_vld(session_count_valid),
.ap_clk(nclk),                                                        // input aclk
.ap_rst_n(nresetn) 
`endif                                                  // input aresetn
);
end
else begin //RX_DDR_BYPASS_EN == 1

//TOE Module with RX_DDR_BYPASS enabled
toe_ip toe_inst_b (

`ifdef VITIS_HLS
// Data output
.m_axis_tcp_data_TVALID(m_axis_tx.tvalid),
.m_axis_tcp_data_TREADY(m_axis_tx.tready),
.m_axis_tcp_data_TDATA(m_axis_tx.tdata), // output [63 : 0] AXI_M_Stream_TDATA
.m_axis_tcp_data_TKEEP(m_axis_tx.tkeep),
.m_axis_tcp_data_TLAST(m_axis_tx.tlast),
// Data input
.s_axis_tcp_data_TVALID(s_axis_rx.tvalid),
.s_axis_tcp_data_TREADY(s_axis_rx.tready),
.s_axis_tcp_data_TDATA(s_axis_rx.tdata),
.s_axis_tcp_data_TKEEP(s_axis_rx.tkeep),
.s_axis_tcp_data_TLAST(s_axis_rx.tlast),

// rx buffer read path
.s_axis_rxread_data_TVALID(axis_rxbuffer2app.tvalid),
.s_axis_rxread_data_TREADY(axis_rxbuffer2app.tready),
.s_axis_rxread_data_TDATA(axis_rxbuffer2app.tdata),
.s_axis_rxread_data_TKEEP(axis_rxbuffer2app.tkeep),
.s_axis_rxread_data_TLAST(axis_rxbuffer2app.tlast),
// rx buffer write path
.m_axis_rxwrite_data_TVALID(axis_tcp2rxbuffer.tvalid),
.m_axis_rxwrite_data_TREADY(axis_tcp2rxbuffer.tready),
.m_axis_rxwrite_data_TDATA(axis_tcp2rxbuffer.tdata),
.m_axis_rxwrite_data_TKEEP(axis_tcp2rxbuffer.tkeep),
.m_axis_rxwrite_data_TLAST(axis_tcp2rxbuffer.tlast),

// tx read commands
.m_axis_txread_cmd_TVALID(m_tcp_mem_rd_cmd[ddrPortNetworkTx].valid),
.m_axis_txread_cmd_TREADY(m_tcp_mem_rd_cmd[ddrPortNetworkTx].ready),
.m_axis_txread_cmd_TDATA(axis_read_cmd_data[ddrPortNetworkTx]),
//tx write commands
.m_axis_txwrite_cmd_TVALID(m_tcp_mem_wr_cmd[ddrPortNetworkTx].valid),
.m_axis_txwrite_cmd_TREADY(m_tcp_mem_wr_cmd[ddrPortNetworkTx].ready),
.m_axis_txwrite_cmd_TDATA(axis_write_cmd_data[ddrPortNetworkTx]),
// tx write status
.s_axis_txwrite_sts_TVALID(s_tcp_mem_wr_sts[ddrPortNetworkTx].valid),
.s_axis_txwrite_sts_TREADY(s_tcp_mem_wr_sts[ddrPortNetworkTx].ready),
.s_axis_txwrite_sts_TDATA(s_tcp_mem_wr_sts[ddrPortNetworkTx].data),
// tx read path
.s_axis_txread_data_TVALID(axis_txread_data.tvalid),
.s_axis_txread_data_TREADY(axis_txread_data.tready),
.s_axis_txread_data_TDATA(axis_txread_data.tdata),
.s_axis_txread_data_TKEEP(axis_txread_data.tkeep),
.s_axis_txread_data_TLAST(axis_txread_data.tlast),
// tx write path
.m_axis_txwrite_data_TVALID(axis_txwrite_data.tvalid),
.m_axis_txwrite_data_TREADY(axis_txwrite_data.tready),
.m_axis_txwrite_data_TDATA(axis_txwrite_data.tdata),
.m_axis_txwrite_data_TKEEP(axis_txwrite_data.tkeep),
.m_axis_txwrite_data_TLAST(axis_txwrite_data.tlast),
/// SmartCAM I/F ///
.m_axis_session_upd_req_TVALID(axis_ht_upd_req.valid),
.m_axis_session_upd_req_TREADY(axis_ht_upd_req.ready),
.m_axis_session_upd_req_TDATA(axis_ht_upd_req.data),

.s_axis_session_upd_rsp_TVALID(axis_ht_upd_rsp.valid),
.s_axis_session_upd_rsp_TREADY(axis_ht_upd_rsp.ready),
.s_axis_session_upd_rsp_TDATA(axis_ht_upd_rsp.data),

.m_axis_session_lup_req_TVALID(axis_ht_lup_req.valid),
.m_axis_session_lup_req_TREADY(axis_ht_lup_req.ready),
.m_axis_session_lup_req_TDATA(axis_ht_lup_req.data),
.s_axis_session_lup_rsp_TVALID(axis_ht_lup_rsp.valid),
.s_axis_session_lup_rsp_TREADY(axis_ht_lup_rsp.ready),
.s_axis_session_lup_rsp_TDATA(axis_ht_lup_rsp.data),

/* Application Interface */
// listen&close port
.s_axis_listen_port_req_TVALID(axis_listen_port.valid),
.s_axis_listen_port_req_TREADY(axis_listen_port.ready),
.s_axis_listen_port_req_TDATA(axis_listen_port.data),
.m_axis_listen_port_rsp_TVALID(axis_listen_port_status.valid),
.m_axis_listen_port_rsp_TREADY(axis_listen_port_status.ready),
.m_axis_listen_port_rsp_TDATA(axis_listen_port_status.data),

// notification & read request
.m_axis_notification_TVALID(axis_notifications.valid),
.m_axis_notification_TREADY(axis_notifications.ready),
.m_axis_notification_TDATA(axis_notifications.data),
.s_axis_rx_data_req_TVALID(axis_read_package.valid),
.s_axis_rx_data_req_TREADY(axis_read_package.ready),
.s_axis_rx_data_req_TDATA(axis_read_package.data),

// open&close connection
.s_axis_open_conn_req_TVALID(axis_open_connection.valid),
.s_axis_open_conn_req_TREADY(axis_open_connection.ready),
.s_axis_open_conn_req_TDATA(axis_open_connection.data),
.m_axis_open_conn_rsp_TVALID(axis_open_status.valid),
.m_axis_open_conn_rsp_TREADY(axis_open_status.ready),
.m_axis_open_conn_rsp_TDATA(axis_open_status.data),
.s_axis_close_conn_req_TVALID(axis_close_connection.valid),
.s_axis_close_conn_req_TREADY(axis_close_connection.ready),
.s_axis_close_conn_req_TDATA(axis_close_connection.data),

// rx data
.m_axis_rx_data_rsp_metadata_TVALID(axis_rx_metadata.valid),
.m_axis_rx_data_rsp_metadata_TREADY(axis_rx_metadata.ready),
.m_axis_rx_data_rsp_metadata_TDATA(axis_rx_metadata.data),
.m_axis_rx_data_rsp_TVALID(m_axis_tcp_rx.tvalid),
.m_axis_rx_data_rsp_TREADY(m_axis_tcp_rx.tready),
.m_axis_rx_data_rsp_TDATA(m_axis_tcp_rx.tdata),
.m_axis_rx_data_rsp_TKEEP(m_axis_tcp_rx.tkeep),
.m_axis_rx_data_rsp_TLAST(m_axis_tcp_rx.tlast),

// tx data
.s_axis_tx_data_req_metadata_TVALID(axis_tx_metadata.valid),
.s_axis_tx_data_req_metadata_TREADY(axis_tx_metadata.ready),
.s_axis_tx_data_req_metadata_TDATA(axis_tx_metadata.data),
.s_axis_tx_data_req_TVALID(s_axis_tcp_tx.tvalid),
.s_axis_tx_data_req_TREADY(s_axis_tcp_tx.tready),
.s_axis_tx_data_req_TDATA(s_axis_tcp_tx.tdata),
.s_axis_tx_data_req_TKEEP(s_axis_tcp_tx.tkeep),
.s_axis_tx_data_req_TLAST(s_axis_tcp_tx.tlast),
.m_axis_tx_data_rsp_TVALID(axis_tx_status.valid),
.m_axis_tx_data_rsp_TREADY(axis_tx_status.ready),
.m_axis_tx_data_rsp_TDATA(axis_tx_status.data),

.myIpAddress(local_ip_address),
.regSessionCount(session_count_data),
.regSessionCount_ap_vld(session_count_valid),
//for external RX Buffer
.axis_data_count(rx_buffer_data_count_reg2),
.axis_max_data_count(16'd1024),

.ap_clk(nclk),                                                        // input aclk
.ap_rst_n(nresetn)    
`else
// Data output
.m_axis_tcp_data_TVALID(m_axis_tx.tvalid),
.m_axis_tcp_data_TREADY(m_axis_tx.tready),
.m_axis_tcp_data_TDATA(m_axis_tx.tdata), // output [63 : 0] AXI_M_Stream_TDATA
.m_axis_tcp_data_TKEEP(m_axis_tx.tkeep),
.m_axis_tcp_data_TLAST(m_axis_tx.tlast),
// Data input
.s_axis_tcp_data_TVALID(s_axis_rx.tvalid),
.s_axis_tcp_data_TREADY(s_axis_rx.tready),
.s_axis_tcp_data_TDATA(s_axis_rx.tdata),
.s_axis_tcp_data_TKEEP(s_axis_rx.tkeep),
.s_axis_tcp_data_TLAST(s_axis_rx.tlast),

// rx buffer read path
.s_axis_rxread_data_TVALID(axis_rxbuffer2app.tvalid),
.s_axis_rxread_data_TREADY(axis_rxbuffer2app.tready),
.s_axis_rxread_data_TDATA(axis_rxbuffer2app.tdata),
.s_axis_rxread_data_TKEEP(axis_rxbuffer2app.tkeep),
.s_axis_rxread_data_TLAST(axis_rxbuffer2app.tlast),
// rx buffer write path
.m_axis_rxwrite_data_TVALID(axis_tcp2rxbuffer.tvalid),
.m_axis_rxwrite_data_TREADY(axis_tcp2rxbuffer.tready),
.m_axis_rxwrite_data_TDATA(axis_tcp2rxbuffer.tdata),
.m_axis_rxwrite_data_TKEEP(axis_tcp2rxbuffer.tkeep),
.m_axis_rxwrite_data_TLAST(axis_tcp2rxbuffer.tlast),

// tx read commands
.m_axis_txread_cmd_V_TVALID(m_tcp_mem_rd_cmd[ddrPortNetworkTx].valid),
.m_axis_txread_cmd_V_TREADY(m_tcp_mem_rd_cmd[ddrPortNetworkTx].ready),
.m_axis_txread_cmd_V_TDATA(axis_read_cmd_data[ddrPortNetworkTx]),
//tx write commands
.m_axis_txwrite_cmd_V_TVALID(m_tcp_mem_wr_cmd[ddrPortNetworkTx].valid),
.m_axis_txwrite_cmd_V_TREADY(m_tcp_mem_wr_cmd[ddrPortNetworkTx].ready),
.m_axis_txwrite_cmd_V_TDATA(axis_write_cmd_data[ddrPortNetworkTx]),
// tx write status
.s_axis_txwrite_sts_V_TVALID(s_tcp_mem_wr_sts[ddrPortNetworkTx].valid),
.s_axis_txwrite_sts_V_TREADY(s_tcp_mem_wr_sts[ddrPortNetworkTx].ready),
.s_axis_txwrite_sts_V_TDATA(s_tcp_mem_wr_sts[ddrPortNetworkTx].data),
// tx read path
.s_axis_txread_data_TVALID(axis_txread_data.tvalid),
.s_axis_txread_data_TREADY(axis_txread_data.tready),
.s_axis_txread_data_TDATA(axis_txread_data.tdata),
.s_axis_txread_data_TKEEP(axis_txread_data.tkeep),
.s_axis_txread_data_TLAST(axis_txread_data.tlast),
// tx write path
.m_axis_txwrite_data_TVALID(axis_txwrite_data.tvalid),
.m_axis_txwrite_data_TREADY(axis_txwrite_data.tready),
.m_axis_txwrite_data_TDATA(axis_txwrite_data.tdata),
.m_axis_txwrite_data_TKEEP(axis_txwrite_data.tkeep),
.m_axis_txwrite_data_TLAST(axis_txwrite_data.tlast),
/// SmartCAM I/F ///
.m_axis_session_upd_req_V_TVALID(axis_ht_upd_req.valid),
.m_axis_session_upd_req_V_TREADY(axis_ht_upd_req.ready),
.m_axis_session_upd_req_V_TDATA(axis_ht_upd_req.data),

.s_axis_session_upd_rsp_V_TVALID(axis_ht_upd_rsp.valid),
.s_axis_session_upd_rsp_V_TREADY(axis_ht_upd_rsp.ready),
.s_axis_session_upd_rsp_V_TDATA(axis_ht_upd_rsp.data),

.m_axis_session_lup_req_V_TVALID(axis_ht_lup_req.valid),
.m_axis_session_lup_req_V_TREADY(axis_ht_lup_req.ready),
.m_axis_session_lup_req_V_TDATA(axis_ht_lup_req.data),
.s_axis_session_lup_rsp_V_TVALID(axis_ht_lup_rsp.valid),
.s_axis_session_lup_rsp_V_TREADY(axis_ht_lup_rsp.ready),
.s_axis_session_lup_rsp_V_TDATA(axis_ht_lup_rsp.data),

/* Application Interface */
// listen&close port
.s_axis_listen_port_req_V_V_TVALID(axis_listen_port.valid),
.s_axis_listen_port_req_V_V_TREADY(axis_listen_port.ready),
.s_axis_listen_port_req_V_V_TDATA(axis_listen_port.data),
.m_axis_listen_port_rsp_V_TVALID(axis_listen_port_status.valid),
.m_axis_listen_port_rsp_V_TREADY(axis_listen_port_status.ready),
.m_axis_listen_port_rsp_V_TDATA(axis_listen_port_status.data),

// notification & read request
.m_axis_notification_V_TVALID(axis_notifications.valid),
.m_axis_notification_V_TREADY(axis_notifications.ready),
.m_axis_notification_V_TDATA(axis_notifications.data),
.s_axis_rx_data_req_V_TVALID(axis_read_package.valid),
.s_axis_rx_data_req_V_TREADY(axis_read_package.ready),
.s_axis_rx_data_req_V_TDATA(axis_read_package.data),

// open&close connection
.s_axis_open_conn_req_V_TVALID(axis_open_connection.valid),
.s_axis_open_conn_req_V_TREADY(axis_open_connection.ready),
.s_axis_open_conn_req_V_TDATA(axis_open_connection.data),
.m_axis_open_conn_rsp_V_TVALID(axis_open_status.valid),
.m_axis_open_conn_rsp_V_TREADY(axis_open_status.ready),
.m_axis_open_conn_rsp_V_TDATA(axis_open_status.data),
.s_axis_close_conn_req_V_V_TVALID(axis_close_connection.valid),
.s_axis_close_conn_req_V_V_TREADY(axis_close_connection.ready),
.s_axis_close_conn_req_V_V_TDATA(axis_close_connection.data),

// rx data
.m_axis_rx_data_rsp_metadata_V_V_TVALID(axis_rx_metadata.valid),
.m_axis_rx_data_rsp_metadata_V_V_TREADY(axis_rx_metadata.ready),
.m_axis_rx_data_rsp_metadata_V_V_TDATA(axis_rx_metadata.data),
.m_axis_rx_data_rsp_TVALID(m_axis_tcp_rx.tvalid),
.m_axis_rx_data_rsp_TREADY(m_axis_tcp_rx.tready),
.m_axis_rx_data_rsp_TDATA(m_axis_tcp_rx.tdata),
.m_axis_rx_data_rsp_TKEEP(m_axis_tcp_rx.tkeep),
.m_axis_rx_data_rsp_TLAST(m_axis_tcp_rx.tlast),

// tx data
.s_axis_tx_data_req_metadata_V_TVALID(axis_tx_metadata.valid),
.s_axis_tx_data_req_metadata_V_TREADY(axis_tx_metadata.ready),
.s_axis_tx_data_req_metadata_V_TDATA(axis_tx_metadata.data),
.s_axis_tx_data_req_TVALID(s_axis_tcp_tx.tvalid),
.s_axis_tx_data_req_TREADY(s_axis_tcp_tx.tready),
.s_axis_tx_data_req_TDATA(s_axis_tcp_tx.tdata),
.s_axis_tx_data_req_TKEEP(s_axis_tcp_tx.tkeep),
.s_axis_tx_data_req_TLAST(s_axis_tcp_tx.tlast),
.m_axis_tx_data_rsp_V_TVALID(axis_tx_status.valid),
.m_axis_tx_data_rsp_V_TREADY(axis_tx_status.ready),
.m_axis_tx_data_rsp_V_TDATA(axis_tx_status.data),

.myIpAddress_V(local_ip_address),
.regSessionCount_V(session_count_data),
.regSessionCount_V_ap_vld(session_count_valid),
//for external RX Buffer
.axis_data_count_V(rx_buffer_data_count_reg2),
.axis_max_data_count_V(16'd1024),

.ap_clk(nclk),                                                        // input aclk
.ap_rst_n(nresetn)    
`endif                                               // input aresetn
);
end //RX_DDR_BYPASS_EN

if (RX_DDR_BYPASS_EN == 1) begin
//RX BUFFER FIFO
axis_data_fifo_512_d1024 rx_buffer_fifo (
  .s_axis_aresetn(nresetn),          // input wire s_axis_aresetn
  .s_axis_aclk(nclk),                // input wire s_axis_aclk
  .s_axis_tvalid(axis_tcp2rxbuffer.tvalid),
  .s_axis_tready(axis_tcp2rxbuffer.tready),
  .s_axis_tdata(axis_tcp2rxbuffer.tdata),
  .s_axis_tkeep(axis_tcp2rxbuffer.tkeep),
  .s_axis_tlast(axis_tcp2rxbuffer.tlast),
  .m_axis_tvalid(axis_rxbuffer2app.tvalid),
  .m_axis_tready(axis_rxbuffer2app.tready),
  .m_axis_tdata(axis_rxbuffer2app.tdata),
  .m_axis_tkeep(axis_rxbuffer2app.tkeep),
  .m_axis_tlast(axis_rxbuffer2app.tlast),
  .axis_wr_data_count(rx_buffer_data_count),
  .axis_rd_data_count()
);

//register data_count
always @(posedge nclk) begin
    rx_buffer_data_count_reg <= rx_buffer_data_count[15:0];
    rx_buffer_data_count_reg2 <= rx_buffer_data_count_reg;
end

end //RX_DDR_BYPASS_EN

logic       ht_insert_failure_count_valid;
logic[15:0] ht_insert_failure_count;

hash_table_ip hash_table_inst (
`ifdef VITIS_HLS
  .ap_clk(nclk),
  .ap_rst_n(nresetn),
  .s_axis_lup_req_TVALID(axis_ht_lup_req.valid),
  .s_axis_lup_req_TREADY(axis_ht_lup_req.ready),
  .s_axis_lup_req_TDATA(axis_ht_lup_req.data),
  .m_axis_lup_rsp_TVALID(axis_ht_lup_rsp.valid),
  .m_axis_lup_rsp_TREADY(axis_ht_lup_rsp.ready),
  .m_axis_lup_rsp_TDATA(axis_ht_lup_rsp.data),
  .s_axis_upd_req_TVALID(axis_ht_upd_req.valid),
  .s_axis_upd_req_TREADY(axis_ht_upd_req.ready),
  .s_axis_upd_req_TDATA(axis_ht_upd_req.data),
  .m_axis_upd_rsp_TVALID(axis_ht_upd_rsp.valid),
  .m_axis_upd_rsp_TREADY(axis_ht_upd_rsp.ready),
  .m_axis_upd_rsp_TDATA(axis_ht_upd_rsp.data),
  .regInsertFailureCount_ap_vld(ht_insert_failure_count_valid),
  .regInsertFailureCount(ht_insert_failure_count)
`else
  .ap_clk(nclk),
  .ap_rst_n(nresetn),
  .s_axis_lup_req_V_TVALID(axis_ht_lup_req.valid),
  .s_axis_lup_req_V_TREADY(axis_ht_lup_req.ready),
  .s_axis_lup_req_V_TDATA(axis_ht_lup_req.data),
  .m_axis_lup_rsp_V_TVALID(axis_ht_lup_rsp.valid),
  .m_axis_lup_rsp_V_TREADY(axis_ht_lup_rsp.ready),
  .m_axis_lup_rsp_V_TDATA(axis_ht_lup_rsp.data),
  .s_axis_upd_req_V_TVALID(axis_ht_upd_req.valid),
  .s_axis_upd_req_V_TREADY(axis_ht_upd_req.ready),
  .s_axis_upd_req_V_TDATA(axis_ht_upd_req.data),
  .m_axis_upd_rsp_V_TVALID(axis_ht_upd_rsp.valid),
  .m_axis_upd_rsp_V_TREADY(axis_ht_upd_rsp.ready),
  .m_axis_upd_rsp_V_TDATA(axis_ht_upd_rsp.data),
  .regInsertFailureCount_V_ap_vld(ht_insert_failure_count_valid),
  .regInsertFailureCount_V(ht_insert_failure_count)
`endif
);

//TCP Data Path
assign axis_rxread_data.tvalid = s_axis_tcp_mem_rd[ddrPortNetworkRx].tvalid;
assign s_axis_tcp_mem_rd[ddrPortNetworkRx].tready = axis_rxread_data.tready;
assign axis_rxread_data.tdata = s_axis_tcp_mem_rd[ddrPortNetworkRx].tdata;
assign axis_rxread_data.tkeep = s_axis_tcp_mem_rd[ddrPortNetworkRx].tkeep;
assign axis_rxread_data.tlast = s_axis_tcp_mem_rd[ddrPortNetworkRx].tlast;

assign m_axis_tcp_mem_wr[ddrPortNetworkRx].tvalid = axis_rxwrite_data.tvalid;
assign axis_rxwrite_data.tready = m_axis_tcp_mem_wr[ddrPortNetworkRx].tready;
assign m_axis_tcp_mem_wr[ddrPortNetworkRx].tdata = axis_rxwrite_data.tdata;
assign m_axis_tcp_mem_wr[ddrPortNetworkRx].tkeep = axis_rxwrite_data.tkeep;
assign m_axis_tcp_mem_wr[ddrPortNetworkRx].tlast = axis_rxwrite_data.tlast;

assign axis_txread_data.tvalid = s_axis_tcp_mem_rd[ddrPortNetworkTx].tvalid;
assign s_axis_tcp_mem_rd[ddrPortNetworkTx].tready = axis_txread_data.tready;
assign axis_txread_data.tdata = s_axis_tcp_mem_rd[ddrPortNetworkTx].tdata;
assign axis_txread_data.tkeep = s_axis_tcp_mem_rd[ddrPortNetworkTx].tkeep;
assign axis_txread_data.tlast = s_axis_tcp_mem_rd[ddrPortNetworkTx].tlast;
assign m_axis_tcp_mem_wr[ddrPortNetworkTx].tvalid = axis_txwrite_data.tvalid;
assign axis_txwrite_data.tready = m_axis_tcp_mem_wr[ddrPortNetworkTx].tready;
assign m_axis_tcp_mem_wr[ddrPortNetworkTx].tdata = axis_txwrite_data.tdata;
assign m_axis_tcp_mem_wr[ddrPortNetworkTx].tkeep = axis_txwrite_data.tkeep;
assign m_axis_tcp_mem_wr[ddrPortNetworkTx].tlast = axis_txwrite_data.tlast;

// Register slices to avoid combinatorial loops created by HLS due to the new axis INTERFACE (enforced since 19.1)

axis_register_slice_tcp_16 listen_port_slice (
  .aclk(nclk),                    // input wire aclk
  .aresetn(nresetn),              // input wire aresetn
  .s_axis_tvalid(s_tcp_listen_req.valid),  // input wire s_axis_tvalid
  .s_axis_tready(s_tcp_listen_req.ready),  // output wire s_axis_tready
  .s_axis_tdata(s_tcp_listen_req.data),    // input wire [7 : 0] s_axis_tdata
  .m_axis_tvalid(axis_listen_port.valid),  // output wire m_axis_tvalid
  .m_axis_tready(axis_listen_port.ready),  // input wire m_axis_tready
  .m_axis_tdata(axis_listen_port.data)    // output wire [7 : 0] m_axis_tdata
);

axis_register_slice_tcp_8 port_status_slice (
  .aclk(nclk),                    // input wire aclk
  .aresetn(nresetn),              // input wire aresetn
  .s_axis_tvalid(axis_listen_port_status.valid),  // input wire s_axis_tvalid
  .s_axis_tready(axis_listen_port_status.ready),  // output wire s_axis_tready
  .s_axis_tdata(axis_listen_port_status.data),    // input wire [7 : 0] s_axis_tdata
  .m_axis_tvalid(m_tcp_listen_rsp.valid),  // output wire m_axis_tvalid
  .m_axis_tready(m_tcp_listen_rsp.ready),  // input wire m_axis_tready
  .m_axis_tdata(m_tcp_listen_rsp.data)    // output wire [7 : 0] m_axis_tdata
);

axis_register_slice_tcp_48 open_connection_slice (
  .aclk(nclk),                    // input wire aclk
  .aresetn(nresetn),              // input wire aresetn
  .s_axis_tvalid(s_tcp_open_req.valid),  // input wire s_axis_tvalid
  .s_axis_tready(s_tcp_open_req.ready),  // output wire s_axis_tready
  .s_axis_tdata(s_tcp_open_req.data),    // input wire [7 : 0] s_axis_tdata
  .m_axis_tvalid(axis_open_connection.valid),  // output wire m_axis_tvalid
  .m_axis_tready(axis_open_connection.ready),  // input wire m_axis_tready
  .m_axis_tdata(axis_open_connection.data)    // output wire [7 : 0] m_axis_tdata
);

axis_register_slice_tcp_72 open_status_slice (
  .aclk(nclk),                    // input wire aclk
  .aresetn(nresetn),              // input wire aresetn
  .s_axis_tvalid(axis_open_status.valid),  // input wire s_axis_tvalid
  .s_axis_tready(axis_open_status.ready),  // output wire s_axis_tready
  .s_axis_tdata(axis_open_status.data),    // input wire [7 : 0] s_axis_tdata
  .m_axis_tvalid(m_tcp_open_rsp.valid),  // output wire m_axis_tvalid
  .m_axis_tready(m_tcp_open_rsp.ready),  // input wire m_axis_tready
  .m_axis_tdata(m_tcp_open_rsp.data)    // output wire [7 : 0] m_axis_tdata
);

axis_register_slice_tcp_16 close_connection_slice (
  .aclk(nclk),                    // input wire aclk
  .aresetn(nresetn),              // input wire aresetn
  .s_axis_tvalid(s_tcp_close_req.valid),  // input wire s_axis_tvalid
  .s_axis_tready(s_tcp_close_req.ready),  // output wire s_axis_tready
  .s_axis_tdata(s_tcp_close_req.data),    // input wire [7 : 0] s_axis_tdata
  .m_axis_tvalid(axis_close_connection.valid),  // output wire m_axis_tvalid
  .m_axis_tready(axis_close_connection.ready),  // input wire m_axis_tready
  .m_axis_tdata(axis_close_connection.data)    // output wire [7 : 0] m_axis_tdata
);

axis_register_slice_tcp_88 notification_slice (
  .aclk(nclk),                    // input wire aclk
  .aresetn(nresetn),              // input wire aresetn
  .s_axis_tvalid(axis_notifications.valid),  // input wire s_axis_tvalid
  .s_axis_tready(axis_notifications.ready),  // output wire s_axis_tready
  .s_axis_tdata(axis_notifications.data),    // input wire [7 : 0] s_axis_tdata
  .m_axis_tvalid(m_tcp_notify.valid),  // output wire m_axis_tvalid
  .m_axis_tready(m_tcp_notify.ready),  // input wire m_axis_tready
  .m_axis_tdata(m_tcp_notify.data)    // output wire [7 : 0] m_axis_tdata
);

axis_register_slice_tcp_32 read_package_slice (
  .aclk(nclk),                    // input wire aclk
  .aresetn(nresetn),              // input wire aresetn
  .s_axis_tvalid(s_tcp_rd_pkg.valid),  // input wire s_axis_tvalid
  .s_axis_tready(s_tcp_rd_pkg.ready),  // output wire s_axis_tready
  .s_axis_tdata(s_tcp_rd_pkg.data[31:0]),    // input wire [7 : 0] s_axis_tdata
  .m_axis_tvalid(axis_read_package.valid),  // output wire m_axis_tvalid
  .m_axis_tready(axis_read_package.ready),  // input wire m_axis_tready
  .m_axis_tdata(axis_read_package.data)    // output wire [7 : 0] m_axis_tdata
);

axis_register_slice_tcp_40 axis_rx_metadata_slice (
  .aclk(nclk),                    // input wire aclk
  .aresetn(nresetn),              // input wire aresetn
  .s_axis_tvalid(axis_rx_metadata.valid),  // input wire s_axis_tvalid
  .s_axis_tready(axis_rx_metadata.ready),  // output wire s_axis_tready
  .s_axis_tdata(axis_rx_metadata.data),    // input wire [7 : 0] s_axis_tdata
  .m_axis_tvalid(m_tcp_rx_meta.valid),  // output wire m_axis_tvalid
  .m_axis_tready(m_tcp_rx_meta.ready),  // input wire m_axis_tready
  .m_axis_tdata(m_tcp_rx_meta.data)    // output wire [7 : 0] m_axis_tdata
);
axis_register_slice_tcp_32 axis_tx_metadata_slice (
  .aclk(nclk),                    // input wire aclk
  .aresetn(nresetn),              // input wire aresetn
  .s_axis_tvalid(s_tcp_tx_meta.valid),  // input wire s_axis_tvalid
  .s_axis_tready(s_tcp_tx_meta.ready),  // output wire s_axis_tready
  .s_axis_tdata(s_tcp_tx_meta.data[31:0]),    // input wire [7 : 0] s_axis_tdata
  .m_axis_tvalid(axis_tx_metadata.valid),  // output wire m_axis_tvalid
  .m_axis_tready(axis_tx_metadata.ready),  // input wire m_axis_tready
  .m_axis_tdata(axis_tx_metadata.data)    // output wire [7 : 0] m_axis_tdata
);
axis_register_slice_tcp_64 axis_tx_status_slice (
  .aclk(nclk),                    // input wire aclk
  .aresetn(nresetn),              // input wire aresetn
  .s_axis_tvalid(axis_tx_status.valid),  // input wire s_axis_tvalid
  .s_axis_tready(axis_tx_status.ready),  // output wire s_axis_tready
  .s_axis_tdata(axis_tx_status.data),    // input wire [7 : 0] s_axis_tdata
  .m_axis_tvalid(m_tcp_tx_stat.valid),  // output wire m_axis_tvalid
  .m_axis_tready(m_tcp_tx_stat.ready),  // input wire m_axis_tready
  .m_axis_tdata(m_tcp_tx_stat.data)    // output wire [7 : 0] m_axis_tdata
);

logic[15:0] read_cmd_counter;
logic[15:0] read_pkg_counter;

always @(posedge nclk) begin
    if (~nresetn) begin
        read_cmd_counter <= '0;
        read_pkg_counter <= '0;
    end
    else begin
        if (m_tcp_mem_rd_cmd[ddrPortNetworkTx].valid && m_tcp_mem_rd_cmd[ddrPortNetworkTx].ready) begin
            read_cmd_counter <= read_cmd_counter + 1;
        end
        if (s_axis_tcp_mem_rd[ddrPortNetworkTx].tvalid && s_axis_tcp_mem_rd[ddrPortNetworkTx].tready && s_axis_tcp_mem_rd[ddrPortNetworkTx].tlast) begin
            read_pkg_counter <= read_pkg_counter + 1;
        end
    end
end

endgenerate

endmodule

`default_nettype wire