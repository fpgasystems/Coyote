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
    metaIntf.s              s_tcp_listen_req_user [N_REGIONS], 
    metaIntf.m              m_tcp_listen_rsp_user [N_REGIONS],
    metaIntf.s              s_tcp_open_req_user [N_REGIONS],
    metaIntf.m              m_tcp_open_rsp_user [N_REGIONS],
    metaIntf.s              s_tcp_close_req_user [N_REGIONS],
    metaIntf.m              m_tcp_notify_user [N_REGIONS],
    metaIntf.s              s_tcp_rd_pkg_user [N_REGIONS],
    metaIntf.m              m_tcp_rx_meta_user [N_REGIONS],
    metaIntf.s              s_tcp_tx_meta_user [N_REGIONS],
    metaIntf.m              m_tcp_tx_stat_user [N_REGIONS],
    AXI4S.m                m_axis_tcp_rx_user [N_REGIONS],
    AXI4S.s                s_axis_tcp_tx_user [N_REGIONS],

    input  wire             aclk,
    input  wire             aresetn
);



//
// Arbiters
//
`ifdef MULT_REGIONS

    logic [TCP_IP_PORT_BITS-1:0]            port_addr;
    logic [TCP_PORT_TABLE_DATA_BITS-1:0]    rsid;     

    // Listen on the port (table)
    tcp_port_table inst_port_table (
        .aclk         (aclk),
        .aresetn      (aresetn),
        .s_listen_req (s_tcp_listen_req_user),
        .m_listen_req (m_tcp_listen_req_net),
        .s_listen_rsp (s_tcp_listen_rsp_net),
        .m_listen_rsp (m_tcp_listen_rsp_user),
        .port_addr    (port_addr),
        .rsid_out     (rsid)
    );

    // Open/Close connections + notify routing
    tcp_conn_table inst_conn_table (
        .aclk        (aclk),
        .aresetn     (aresetn),

        .s_open_req  (s_tcp_open_req_user),
        .m_open_req  (m_tcp_open_req_net),
        .s_close_req (s_tcp_close_req_user),
        .m_close_req (m_tcp_close_req_net),
        .s_open_rsp  (s_tcp_open_rsp_net),
        .m_open_rsp  (m_tcp_open_rsp_user),

        .s_notify    (s_tcp_notify_net),
        .m_notify    (m_tcp_notify_user),

        .port_addr   (port_addr),
        .rsid_in     (rsid)
    );

    // RX data
    tcp_rx_arbiter inst_rx_arb (
        .aclk     (aclk),
        .aresetn  (aresetn),
        .s_rd_pkg (s_tcp_rd_pkg_user),
        .m_rd_pkg (m_tcp_rd_pkg_net),
        .s_rx_meta(s_tcp_rx_meta_net),
        .m_rx_meta(m_tcp_rx_meta_user),
        .s_axis_rx(s_axis_tcp_rx_net),
        .m_axis_rx(m_axis_tcp_rx_user)
    );

    // TX data
    tcp_tx_arbiter inst_tx_arb (
        .aclk     (aclk),
        .aresetn  (aresetn),
        .s_tx_meta(s_tcp_tx_meta_user),
        .m_tx_meta(m_tcp_tx_meta_net),
        .s_tx_stat(s_tcp_tx_stat_net),
        .m_tx_stat(m_tcp_tx_stat_user),
        .s_axis_tx(s_axis_tcp_tx_user),
        .m_axis_tx(m_axis_tcp_tx_net)
    );
    
`else
    `META_ASSIGN(s_tcp_listen_req_user[0], m_tcp_listen_req_net)    
    `META_ASSIGN(s_tcp_listen_rsp_net, m_tcp_listen_rsp_user[0])

    `META_ASSIGN(s_tcp_open_req_user[0], m_tcp_open_req_net)
    `META_ASSIGN(s_tcp_close_req_user[0], m_tcp_close_req_net)
    `META_ASSIGN(s_tcp_open_rsp_net, m_tcp_open_rsp_user[0])

    `META_ASSIGN(s_tcp_notify_net, m_tcp_notify_user[0])
    `META_ASSIGN(s_tcp_rd_pkg_user[0], m_tcp_rd_pkg_net)
    `META_ASSIGN(s_tcp_rx_meta_net, m_tcp_rx_meta_user[0])
    `AXIS_ASSIGN(s_axis_tcp_rx_net, m_axis_tcp_rx_user[0]) 

    `META_ASSIGN(s_tcp_tx_meta_user[0], m_tcp_tx_meta_net)
    `META_ASSIGN(s_tcp_tx_stat_net, m_tcp_tx_stat_user[0])
    `AXIS_ASSIGN(s_axis_tcp_tx_user[0], m_axis_tcp_tx_net)
 
`endif

endmodule