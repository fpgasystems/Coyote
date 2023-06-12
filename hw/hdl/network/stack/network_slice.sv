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
 * @brief   Network slice array
 *
 * Cross late from nclk -> aclk
 */
module network_slice (
    // Network
    metaIntf.m              m_arp_lookup_request_n,
    metaIntf.s              s_arp_lookup_reply_n,
    metaIntf.m              m_set_ip_addr_n,
    metaIntf.m              m_set_mac_addr_n,
`ifdef EN_STATS
    input  net_stat_t       s_net_stats_n,
`endif
`ifdef NET_DROP
    metaIntf.m              m_drop_rx_n,
    metaIntf.m              m_drop_tx_n,
    output logic            m_clear_drop_n,
`endif  

    // User
    metaIntf.s              s_arp_lookup_request_u,
    metaIntf.m              m_arp_lookup_reply_u,
    metaIntf.s              s_set_ip_addr_u,
    metaIntf.s              s_set_mac_addr_u,
`ifdef EN_STATS
    output net_stat_t       m_net_stats_u,
`endif
`ifdef NET_DROP
    metaIntf.s              s_drop_rx_u,
    metaIntf.s              s_drop_tx_u,
    input  logic            s_clear_drop_u,
`endif 
    
    input  wire             aclk,
    input  wire             aresetn
);

    // ARP request
    axis_register_slice_net_32 inst_slice_arp_request_nc (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_arp_lookup_request_u.valid),
        .s_axis_tready(s_arp_lookup_request_u.ready),
        .s_axis_tdata(s_arp_lookup_request_u.data),  
        .m_axis_tvalid(m_arp_lookup_request_n.valid),
        .m_axis_tready(m_arp_lookup_request_n.ready),
        .m_axis_tdata(m_arp_lookup_request_n.data)
    );

    // ARP reply
    axis_register_slice_net_56 inst_slice_arp_reply_nc (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_arp_lookup_reply_n.valid),
        .s_axis_tready(s_arp_lookup_reply_n.ready),
        .s_axis_tdata(s_arp_lookup_reply_n.data),  
        .m_axis_tvalid(m_arp_lookup_reply_u.valid),
        .m_axis_tready(m_arp_lookup_reply_u.ready),
        .m_axis_tdata(m_arp_lookup_reply_u.data)
    );

    // Set IP address
    axis_register_slice_net_32 inst_slice_set_ip_addr_nc (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_set_ip_addr_u.valid),
        .s_axis_tready(s_set_ip_addr_u.ready),
        .s_axis_tdata(s_set_ip_addr_u.data),  
        .m_axis_tvalid(m_set_ip_addr_n.valid),
        .m_axis_tready(m_set_ip_addr_n.ready),
        .m_axis_tdata(m_set_ip_addr_n.data)
    );

    // Set MAC address
    axis_register_slice_net_48 inst_slice_set_mac_addr_nc (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_set_mac_addr_u.valid),
        .s_axis_tready(s_set_mac_addr_u.ready),
        .s_axis_tdata(s_set_mac_addr_u.data),  
        .m_axis_tvalid(m_set_mac_addr_n.valid),
        .m_axis_tready(m_set_mac_addr_n.ready),
        .m_axis_tdata(m_set_mac_addr_n.data)
    );

`ifdef EN_STATS
    // Stats
    axis_register_slice_net_512 inst_reg_net_stats (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(1'b1),
        .s_axis_tready(),
        .s_axis_tdata(s_net_stats_n),  
        .m_axis_tvalid(),
        .m_axis_tready(1'b1),
        .m_axis_tdata(m_net_stats_u)
    );
`endif

`ifdef NET_DROP
    // RX drop
    axis_register_slice_net_32 (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_drop_rx_u.valid),
        .s_axis_tready(s_drop_rx_u.ready),
        .s_axis_tdata (s_drop_rx_u.data),  
        .m_axis_tvalid(m_drop_rx_n.valid),
        .m_axis_tready(m_drop_rx_n.ready),
        .m_axis_tdata (m_drop_rx_n.data)
    );

    // TX drop
    axis_register_slice_net_32 (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_drop_tx_u.valid),
        .s_axis_tready(s_drop_tx_u.ready),
        .s_axis_tdata (s_drop_tx_u.data),  
        .m_axis_tvalid(m_drop_tx_n.valid),
        .m_axis_tready(m_drop_tx_n.ready),
        .m_axis_tdata (m_drop_tx_n.data)
    );

    // Clear drop
    axis_register_slice_net_8 (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(1'b1),
        .s_axis_tready(),
        .s_axis_tdata(s_clear_drop_u),  
        .m_axis_tvalid(),
        .m_axis_tready(1'b1),
        .m_axis_tdata(m_clear_drop_n)
    );

`endif

endmodule