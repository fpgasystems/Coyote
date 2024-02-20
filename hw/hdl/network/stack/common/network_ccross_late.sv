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
 * @brief   Network late clock crossing
 *
 * Cross late from nclk -> aclk
 */
module network_ccross_late #(
    parameter integer       ENABLED = 0  
) (
    // Network
    metaIntf.m              m_arp_lookup_request_nclk,
    metaIntf.m              m_set_ip_addr_nclk,
    metaIntf.m              m_set_mac_addr_nclk,
`ifdef EN_STATS
    input  net_stat_t       s_net_stats_nclk,
`endif  

    // User
    metaIntf.s              s_arp_lookup_request_aclk,
    metaIntf.s              s_set_ip_addr_aclk,
    metaIntf.s              s_set_mac_addr_aclk,
`ifdef EN_STATS
    output net_stat_t       m_net_stats_aclk,
`endif
    

    input  wire             nclk,
    input  wire             nresetn,
    input  wire             aclk,
    input  wire             aresetn
);

if(ENABLED == 1) begin

    // ---------------------------------------------------------------------------------------------------
    // Crossings
    // ---------------------------------------------------------------------------------------------------

    // ARP request
    axis_clock_converter_net_32 inst_cross_arp_request (
        .s_axis_aresetn(aresetn),
        .m_axis_aresetn(nresetn),
        .s_axis_aclk(aclk),
        .m_axis_aclk(nclk),
        .s_axis_tvalid(s_arp_lookup_request_aclk.valid),
        .s_axis_tready(s_arp_lookup_request_aclk.ready),
        .s_axis_tdata(s_arp_lookup_request_aclk.data),  
        .m_axis_tvalid(m_arp_lookup_request_nclk.valid),
        .m_axis_tready(m_arp_lookup_request_nclk.ready),
        .m_axis_tdata(m_arp_lookup_request_nclk.data)
    );

    // Set IP address
    axis_clock_converter_net_32 inst_cross_set_ip_addr (
        .s_axis_aresetn(aresetn),
        .m_axis_aresetn(nresetn),
        .s_axis_aclk(aclk),
        .m_axis_aclk(nclk),
        .s_axis_tvalid(s_set_ip_addr_aclk.valid),
        .s_axis_tready(s_set_ip_addr_aclk.ready),
        .s_axis_tdata(s_set_ip_addr_aclk.data),  
        .m_axis_tvalid(m_set_ip_addr_nclk.valid),
        .m_axis_tready(m_set_ip_addr_nclk.ready),
        .m_axis_tdata(m_set_ip_addr_nclk.data)
    );

    // Set MAC address
    axis_clock_converter_net_48 inst_cross_set_mac_addr (
        .s_axis_aresetn(aresetn),
        .m_axis_aresetn(nresetn),
        .s_axis_aclk(aclk),
        .m_axis_aclk(nclk),
        .s_axis_tvalid(s_set_mac_addr_aclk.valid),
        .s_axis_tready(s_set_mac_addr_aclk.ready),
        .s_axis_tdata(s_set_mac_addr_aclk.data),  
        .m_axis_tvalid(m_set_mac_addr_nclk.valid),
        .m_axis_tready(m_set_mac_addr_nclk.ready),
        .m_axis_tdata(m_set_mac_addr_nclk.data)
    );

`ifdef EN_STATS
    // Stats
    axis_clock_converter_net_512 inst_ccross_qp_interface (
        .s_axis_aresetn(nresetn),
        .m_axis_aresetn(aresetn),
        .s_axis_aclk(nclk),
        .m_axis_aclk(aclk),
        .s_axis_tvalid(1'b1),
        .s_axis_tready(),
        .s_axis_tdata(s_net_stats_nclk),  
        .m_axis_tvalid(),
        .m_axis_tready(1'b1),
        .m_axis_tdata(m_net_stats_aclk)
    );
`endif

end
else begin

    //
    // Decouple it a bit 
    //

    // ARP request
    axis_register_slice_net_32 inst_clk_cnvrt_arp_request_nc (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_arp_lookup_request_aclk.valid),
        .s_axis_tready(s_arp_lookup_request_aclk.ready),
        .s_axis_tdata(s_arp_lookup_request_aclk.data),  
        .m_axis_tvalid(m_arp_lookup_request_nclk.valid),
        .m_axis_tready(m_arp_lookup_request_nclk.ready),
        .m_axis_tdata(m_arp_lookup_request_nclk.data)
    );

    // Set IP address
    axis_register_slice_net_32 inst_clk_cnvrt_set_ip_addr_nc (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_set_ip_addr_aclk.valid),
        .s_axis_tready(s_set_ip_addr_aclk.ready),
        .s_axis_tdata(s_set_ip_addr_aclk.data),  
        .m_axis_tvalid(m_set_ip_addr_nclk.valid),
        .m_axis_tready(m_set_ip_addr_nclk.ready),
        .m_axis_tdata(m_set_ip_addr_nclk.data)
    );

    // Set MAC address
    axis_register_slice_net_48 inst_clk_cnvrt_set_mac_addr_nc (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_set_mac_addr_aclk.valid),
        .s_axis_tready(s_set_mac_addr_aclk.ready),
        .s_axis_tdata(s_set_mac_addr_aclk.data),  
        .m_axis_tvalid(m_set_mac_addr_nclk.valid),
        .m_axis_tready(m_set_mac_addr_nclk.ready),
        .m_axis_tdata(m_set_mac_addr_nclk.data)
    );

`ifdef EN_STATS
    // Stats
    axis_register_slice_net_512 inst_reg_net_stats (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(1'b1),
        .s_axis_tready(),
        .s_axis_tdata(s_net_stats_nclk),  
        .m_axis_tvalid(),
        .m_axis_tready(1'b1),
        .m_axis_tdata(m_net_stats_aclk)
    );
`endif

end

endmodule