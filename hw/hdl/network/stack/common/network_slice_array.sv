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