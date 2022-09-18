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
    AXI4SR.m                m_axis_tcp_rx_user [N_REGIONS],
    AXI4SR.s                s_axis_tcp_tx_user [N_REGIONS],

    input  wire             aclk,
    input  wire             aresetn
);

//
// Arbiters
//

// Listen on the port (hash)
tcp_port_table inst_port_table (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_listen_req(s_tcp_listen_req_user),
    .m_listen_req(m_tcp_listen_req_net),
    .s_listen_rsp(s_tcp_listen_rsp_net),
    .m_listen_rsp(m_tcp_listen_rsp_user),
    .s_notify(s_tcp_notify_net),
    .m_notify(m_tcp_notify_user)
);

// Open connections (hash)
tcp_conn_table inst_conn_table (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_open_req(s_tcp_open_req_user),
    .m_open_req(m_tcp_open_req_net),
    .s_close_req(s_tcp_close_req_user),
    .m_close_req(m_tcp_close_req_net),
    .s_open_rsp(s_tcp_open_rsp_net),
    .m_open_rsp(m_tcp_open_rsp_user)
);

// RX data
tcp_rx_arbiter inst_rx_arb (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_rd_pkg(s_tcp_rd_pkg_user),
    .m_rd_pkg(m_tcp_rd_pkg_net),
    .s_rx_meta(s_tcp_rx_meta_net),
    .m_rx_meta(m_tcp_rx_meta_user),
    .s_axis_rx(s_axis_tcp_rx_net),
    .m_axis_rx(m_axis_tcp_rx_user)
);

// TX data
tcp_tx_arbiter inst_tx_arb (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_tx_meta(s_tcp_tx_meta_user),
    .m_tx_meta(m_tcp_tx_meta_net),
    .s_tx_stat(s_tcp_tx_stat_net),
    .m_tx_stat(m_tcp_tx_stat_user),
    .s_axis_tx(s_axis_tcp_tx_user),
    .m_axis_tx(m_axis_tcp_tx_net)
);

endmodule