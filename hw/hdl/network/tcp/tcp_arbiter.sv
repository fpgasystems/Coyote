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
 * @brief   Top level TCP arbiter
 * 
 */
module tcp_arbiter (
    // Network
    metaIntf.m              m_tcp_listen_req_net,  
    metaIntf.s              s_tcp_listen_rsp_net,
    metaIntf.m              m_tcp_open_req_net,
    metaIntf.s              s_tcp_open_rsp_net,
    metaIntf.m              m_tcp_close_req_net,
    metaIntf.s              s_tcp_notify_net,
    metaIntf.m              m_tcp_rd_pkg_net,
    metaIntf.s              s_tcp_rx_meta_net,
    metaIntf.m              m_tcp_tx_meta_net,
    metaIntf.s              s_tcp_tx_stat_net,
    AXI4S.s                 s_axis_tcp_rx_net,
    AXI4S.m                 m_axis_tcp_tx_net,

    // User
    metaIntf.s              s_tcp_listen_req_host, 
    metaIntf.m              m_tcp_listen_rsp_host,
    metaIntf.s              s_tcp_open_req_host,
    metaIntf.m              m_tcp_open_rsp_host,
    metaIntf.m              m_tcp_rx_meta_user [N_REGIONS], // sid + len
    metaIntf.s              s_tcp_tx_meta_user [N_REGIONS], // sid + len
    AXI4S.m                 m_axis_tcp_rx_user [N_REGIONS],
    AXI4S.s                 s_axis_tcp_tx_user [N_REGIONS],

    input  wire             aclk,
    input  wire             aresetn
);

//
// Arbiters
//

// Port table
logic [TCP_PORT_ORDER-1:0] port_addr;
logic [TCP_PORT_TABLE_DATA_BITS-1:0] rsid;

tcp_port_table inst_port_table (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_listen_req(s_tcp_listen_req_host),
    .m_listen_req(m_tcp_listen_req_net),
    .s_listen_rsp(s_tcp_listen_rsp_net),
    .m_listen_rsp(m_tcp_listen_rsp_host),
    .port_addr(port_addr),
    .rsid(rsid)
);

// Notify arbitration
metaIntf #(.STYPE(tcp_notify_t)) notify_opened ();
metaIntf #(.STYPE(tcp_notify_t)) notify_recv ();

tcp_notify_arb inst_notify_arb (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_notify(s_tcp_notify_net),
    .m_notify_opened(notify_opened),
    .m_notify_recv(notify_recv)
);

// TCP convert
metaIntf #(.STYPE(tcp_meta_t)) rx_meta ();
AXI4S axis_tcp_rx ();

metaIntf #(.STYPE(tcp_meta_t)) tx_meta ();
AXI4S axis_tcp_tx ();

tcp_cnvrt_wrap inst_tcp_cnvrt (
    .aclk(aclk),
    .aresetn(aresetn),

    .maxPkgWord(PMTU_BYTES >> 6), // TODO: Check ...
    .ap_clr_pulse(1'b0),

    // User
    .netTxData(axis_tcp_tx),
    .netTxMeta(tx_meta),
    .netRxData(axis_tcp_rx),
    .netRxMeta(rx_meta),

    // Net
    .tcp_0_notify(s_tcp_notify_net),
    .tcp_0_rd_pkg(m_tcp_rd_pkg_net),
    .tcp_0_rx_meta(s_tcp_rx_meta_net),
    .tcp_0_tx_meta(m_tcp_tx_meta_net),
    .tcp_0_tx_stat(s_tcp_tx_stat_net),
    .axis_tcp_0_sink(s_axis_tcp_rx_net),
    .axis_tcp_0_src(m_axis_tcp_tx_net)
);

// Connection table
metaIntf #(.STYPE(tcp_meta_r_t)) rx_meta_r ();
AXI4S axis_tcp_rx_conn ();

metaIntf #(.STYPE(tcp_tx_meta_r_t)) tx_meta_r ();
AXI4S axis_tcp_tx_conn ();

tcp_conn_table inst_conn_table (
    .aclk(aclk),
    .aresetn(aresetn),
    
    .s_open_req(s_tcp_open_req_host),
    .m_open_req(m_tcp_open_req_net),
    .m_close_req(m_tcp_close_req_net),
    .s_open_rsp(s_tcp_open_rsp_net),
    .m_open_rsp(m_tcp_open_rsp_host),
    
    .s_notify_opened(notify_opened),
    .port_addr(port_addr),
    .rsid_in(rsid),

    .s_rx_meta(s_tcp_rx_meta_net),
    .m_rx_meta_r(rx_meta_r),
    .s_axis_rx(axis_tcp_rx),
    .m_axis_rx_r(axis_tcp_rx_conn),

    .s_tx_meta_r(tx_meta_r),
    .m_tx_meta(m_tcp_tx_meta_net),
    .s_axis_tx_r(axis_tcp_tx_conn),
    .m_axis_tx(axis_tcp_tx)
);

// RX mux
tcp_rx_arbiter inst_rx_arb (
    .aclk(aclk),
    .aresetn(aresetn),
    .rx_meta(rx_meta_r), 
    .m_rx_meta(m_tcp_rx_meta_user), 
    .axis_rx_data(axis_tcp_rx_conn),
    .m_rx_data(m_axis_tcp_rx_user)
);

// TX mux
tcp_tx_arbiter inst_tx_arb (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_tx_meta(s_tcp_tx_meta_user),
    .tx_meta(tx_meta_r),
    .s_tx_data(s_axis_tcp_tx_user),
    .axis_tx_data(axis_tcp_tx_conn)
);

endmodule