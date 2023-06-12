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
    metaIntf.s              s_arp_lookup_reply_nclk,
    metaIntf.m              m_set_ip_addr_nclk,
    metaIntf.m              m_set_mac_addr_nclk,
`ifdef EN_STATS
    input  net_stat_t       s_net_stats_nclk,
`endif
`ifdef NET_DROP
    metaIntf.m              m_drop_rx_nclk,
    metaIntf.m              m_drop_tx_nclk,
    output logic            m_clear_drop_nclk,
`endif  

    // User
    metaIntf.s              s_arp_lookup_request_aclk,
    metaIntf.m              m_arp_lookup_reply_aclk,
    metaIntf.s              s_set_ip_addr_aclk,
    metaIntf.s              s_set_mac_addr_aclk,
`ifdef EN_STATS
    output net_stat_t       m_net_stats_aclk,
`endif
`ifdef NET_DROP
    metaIntf.s              s_drop_rx_aclk,
    metaIntf.s              s_drop_tx_aclk,
    input  logic            s_clear_drop_aclk,
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

    // ARP reply
    axis_clock_converter_net_56 inst_cross_arp_reply (
        .s_axis_aresetn(nresetn),
        .m_axis_aresetn(aresetn),
        .s_axis_aclk(nclk),
        .m_axis_aclk(aclk),
        .s_axis_tvalid(s_arp_lookup_reply_nclk.valid),
        .s_axis_tready(s_arp_lookup_reply_nclk.ready),
        .s_axis_tdata(s_arp_lookup_reply_nclk.data),  
        .m_axis_tvalid(m_arp_lookup_reply_aclk.valid),
        .m_axis_tready(m_arp_lookup_reply_aclk.ready),
        .m_axis_tdata(m_arp_lookup_reply_aclk.data)
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

`ifdef NET_DROP
    // Drop RX
    axis_clock_converter_net_32 inst_ccross_drop_rx (
        .s_axis_aresetn(aresetn),
        .m_axis_aresetn(nresetn),
        .s_axis_aclk(aclk),
        .m_axis_aclk(nclk),
        .s_axis_tvalid(s_drop_rx_aclk.valid),
        .s_axis_tready(s_drop_rx_aclk.ready),
        .s_axis_tdata (s_drop_rx_aclk.data),  
        .m_axis_tvalid(m_drop_rx_nclk.valid),
        .m_axis_tready(m_drop_rx_nclk.ready),
        .m_axis_tdata (m_drop_rx_nclk.data)
    );

    // Drop TX
    axis_clock_converter_net_32 inst_ccross_drop_tx (
        .s_axis_aresetn(aresetn),
        .m_axis_aresetn(nresetn),
        .s_axis_aclk(aclk),
        .m_axis_aclk(nclk),
        .s_axis_tvalid(s_drop_tx_aclk.valid),
        .s_axis_tready(s_drop_tx_aclk.ready),
        .s_axis_tdata (s_drop_tx_aclk.data),  
        .m_axis_tvalid(m_drop_tx_nclk.valid),
        .m_axis_tready(m_drop_tx_nclk.ready),
        .m_axis_tdata (m_drop_tx_nclk.data)
    );

    // Clear drop
    axis_clock_converter_net_8 inst_ccross_drop_clear (
        .s_axis_aresetn(aresetn),
        .m_axis_aresetn(nresetn),
        .s_axis_aclk(aclk),
        .m_axis_aclk(nclk),
        .s_axis_tvalid(1'b1),
        .s_axis_tready(),
        .s_axis_tdata (s_clear_drop_aclk),  
        .m_axis_tvalid(),
        .m_axis_tready(1'b1),
        .m_axis_tdata (m_clear_drop_nclk)
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

    // ARP reply
    axis_register_slice_net_56 inst_clk_cnvrt_arp_reply_nc (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_arp_lookup_reply_nclk.valid),
        .s_axis_tready(s_arp_lookup_reply_nclk.ready),
        .s_axis_tdata(s_arp_lookup_reply_nclk.data),  
        .m_axis_tvalid(m_arp_lookup_reply_aclk.valid),
        .m_axis_tready(m_arp_lookup_reply_aclk.ready),
        .m_axis_tdata(m_arp_lookup_reply_aclk.data)
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

`ifdef NET_DROP
    // Drop RX
    axis_register_slice_net_32 inst_clk_cnvrt_drop_rx (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_drop_rx_aclk.valid),
        .s_axis_tready(s_drop_rx_aclk.ready),
        .s_axis_tdata (s_drop_rx_aclk.data),  
        .m_axis_tvalid(m_drop_rx_nclk.valid),
        .m_axis_tready(m_drop_rx_nclk.ready),
        .m_axis_tdata (m_drop_rx_nclk.data)
    );

    // Drop TX
    axis_register_slice_net_32 inst_clk_cnvrt_drop_tx (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_drop_tx_aclk.valid),
        .s_axis_tready(s_drop_tx_aclk.ready),
        .s_axis_tdata (s_drop_tx_aclk.data),  
        .m_axis_tvalid(m_drop_tx_nclk.valid),
        .m_axis_tready(m_drop_tx_nclk.ready),
        .m_axis_tdata (m_drop_tx_nclk.data)
    );

    // Clear drop
    axis_register_slice_net_8 inst_clk_cnvrt_drop_clear (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(1'b1),
        .s_axis_tready(),
        .s_axis_tdata (s_clear_drop_aclk),  
        .m_axis_tvalid(),
        .m_axis_tready(1'b1),
        .m_axis_tdata (m_clear_drop_nclk)
    );

`endif

end

endmodule