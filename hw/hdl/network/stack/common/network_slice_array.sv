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
 */
module network_slice_array #(
    parameter integer       N_STAGES = 2  
) (
    // Network
    metaIntf.m              m_arp_lookup_request_n,
    metaIntf.m              m_set_ip_addr_n,
    metaIntf.m              m_set_mac_addr_n,
`ifdef EN_STATS
    input  net_stat_t       s_net_stats_n,
`endif

    // User
    metaIntf.s              s_arp_lookup_request_u,
    metaIntf.s              s_set_ip_addr_u,
    metaIntf.s              s_set_mac_addr_u,
`ifdef EN_STATS
    output net_stat_t       m_net_stats_u,
`endif
    
    input  wire             aclk,
    input  wire             aresetn
);

metaIntf #(.STYPE(logic[ARP_LUP_REQ_BITS-1:0])) arp_lookup_request_s [N_STAGES+1] ();
metaIntf #(.STYPE(logic[IP_ADDR_BITS-1:0])) set_ip_addr_s [N_STAGES+1] ();
metaIntf #(.STYPE(logic[MAC_ADDR_BITS-1:0])) set_mac_addr_s [N_STAGES+1] ();
net_stat_t [N_STAGES:0] net_stats_s;

// Slaves
`ifdef EN_STATS
assign net_stats_s[0] = s_net_stats_n;
`endif

`META_ASSIGN(s_arp_lookup_request_u, arp_lookup_request_s[0])
`META_ASSIGN(s_set_ip_addr_u, set_ip_addr_s[0])
`META_ASSIGN(s_set_mac_addr_u, set_mac_addr_s[0])

// Masters
`META_ASSIGN(arp_lookup_request_s[N_STAGES], m_arp_lookup_request_n)
`META_ASSIGN(set_ip_addr_s[N_STAGES], m_set_ip_addr_n)
`META_ASSIGN(set_mac_addr_s[N_STAGES], m_set_mac_addr_n)

`ifdef EN_STATS
assign m_net_stats_u = net_stats_s[N_STAGES];
`endif

for(genvar i = 0; i < N_STAGES; i++) begin

    // ARP request
    axis_register_slice_net_32 (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(arp_lookup_request_s[i].valid),
        .s_axis_tready(arp_lookup_request_s[i].ready),
        .s_axis_tdata (arp_lookup_request_s[i].data),  
        .m_axis_tvalid(arp_lookup_request_s[i+1].valid),
        .m_axis_tready(arp_lookup_request_s[i+1].ready),
        .m_axis_tdata (arp_lookup_request_s[i+1].data)
    );

    // Set IP address
    axis_register_slice_net_32 (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(set_ip_addr_s[i].valid),
        .s_axis_tready(set_ip_addr_s[i].ready),
        .s_axis_tdata (set_ip_addr_s[i].data),  
        .m_axis_tvalid(set_ip_addr_s[i+1].valid),
        .m_axis_tready(set_ip_addr_s[i+1].ready),
        .m_axis_tdata (set_ip_addr_s[i+1].data)
    );

    // Set MAC address
    axis_register_slice_net_48 (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(set_mac_addr_s[i].valid),
        .s_axis_tready(set_mac_addr_s[i].ready),
        .s_axis_tdata (set_mac_addr_s[i].data),  
        .m_axis_tvalid(set_mac_addr_s[i+1].valid),
        .m_axis_tready(set_mac_addr_s[i+1].ready),
        .m_axis_tdata (set_mac_addr_s[i+1].data)
    );

`ifdef EN_STATS
    // NET stats
    axis_register_slice_net_512 (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(1'b1),
        .s_axis_tready(),
        .s_axis_tdata(net_stats_s[i]),  
        .m_axis_tvalid(),
        .m_axis_tready(1'b1),
        .m_axis_tdata(net_stats_s[i+1])
    );
`endif

end

endmodule