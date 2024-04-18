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

/**
 * @brief   Network top
 *
 * Top level network stack
 * 
 *  @param CROSS_EARLY      Crossing early 322 -> nclk
 *  @param CROSS_LATE       Crossing late nclk -> aclk
 */
module network_top #(
    parameter integer CROSS_EARLY = 0,
    parameter integer CROSS_LATE = 1,
    parameter integer ENABLE_RDMA = 0,
    parameter integer ENABLE_TCP = 0,
    parameter integer QSFP = 0
) (
    // Network physical
    input  wire                 sys_reset,  
    input  wire                 init_clk,             
    input  wire                 gt_refclk_p,
    input  wire                 gt_refclk_n,

    input  wire [3:0]           gt_rxp_in,         
    input  wire [3:0]           gt_rxn_in,            
    output wire [3:0]           gt_txp_out,
    output wire [3:0]           gt_txn_out,

    // Init
    metaIntf.s                  s_arp_lookup_request,
    metaIntf.m                 m_arp_lookup_reply,
    metaIntf.s                  s_set_ip_addr,
    metaIntf.s                  s_set_mac_addr,
`ifdef EN_STATS
    output net_stat_t           m_net_stats,
`endif

    metaIntf.s                  s_rdma_qp_interface,
    metaIntf.s                  s_rdma_conn_interface,

    // Commands
    metaIntf.s                  s_rdma_sq,
    metaIntf.m                 m_rdma_ack,

    // RDMA ctrl + data
    metaIntf.m                 m_rdma_rd_req,
    metaIntf.m                 m_rdma_wr_req,
    AXI4S.s                     s_axis_rdma_rd,
    AXI4S.m                    m_axis_rdma_wr,

    // Offsets
    input logic [63:0]          s_ddr_offset_addr,

    // TCP memory interface
    AXI4.m                     m_axi_tcp_ddr,

    // TCP interface
    metaIntf.s                  s_tcp_listen_req,
    metaIntf.m                 m_tcp_listen_rsp,   
    metaIntf.s                  s_tcp_open_req,
    metaIntf.m                 m_tcp_open_rsp,
    metaIntf.s                  s_tcp_close_req,
    metaIntf.m                 m_tcp_notify,
    metaIntf.s                  s_tcp_rd_pkg,
    metaIntf.m                 m_tcp_rx_meta,
    metaIntf.s                  s_tcp_tx_meta,
    metaIntf.m                 m_tcp_tx_stat,
    AXI4S.s                     s_axis_tcp_tx,
    AXI4S.m                    m_axis_tcp_rx,  

`ifdef NET_DROP
    metaIntf.s                  s_drop_rx,
    metaIntf.s                  s_drop_tx,
    input  wire                 s_clear_drop,
`endif 

    // Clocks
    input  wire                 aclk,
    input  wire                 aresetn,
    input  wire                 nclk,
    input  wire                 nresetn
);

/**
 * Raw CMAC clock - 322 MHz
 */
logic r_resetn;
logic r_clk;

/**
 * Stack clock
 */
logic n_resetn;
logic n_clk;

if(CROSS_EARLY == 1) begin
    assign n_clk = nclk;
    assign n_resetn = nresetn;
end
else begin
    assign n_clk = r_clk;
    assign n_resetn = r_resetn;
end

/**
 * Network module
 */
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_r_clk_rx_data();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_r_clk_tx_data();

network_module #(
    .QSFP(QSFP),
    .N_STGS(N_REG_NET_S2)
) inst_network_module (
    .init_clk (init_clk),
    .sys_reset (sys_reset),
    .rclk(r_clk),
    .rresetn(r_resetn),

    .gt_refclk_p(gt_refclk_p),
    .gt_refclk_n(gt_refclk_n),

    .gt_rxp_in(gt_rxp_in),
    .gt_rxn_in(gt_rxn_in),
    .gt_txp_out(gt_txp_out),
    .gt_txn_out(gt_txn_out),

    //master 0
    .m_axis_net_rx(axis_r_clk_rx_data),
    .s_axis_net_tx(axis_r_clk_tx_data)
);

/**
 * Cross early
 */
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_n_clk_rx_data();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_n_clk_tx_data();

network_ccross_early #(
    .ENABLED(CROSS_EARLY),
    .N_STGS(N_REG_NET_S1)
) inst_early_ccross (
    .rclk(r_clk),
    .rresetn(r_resetn),
    .nclk(n_clk),
    .nresetn(n_resetn),
    .s_axis_rclk(axis_r_clk_rx_data),
    .m_axis_rclk(axis_r_clk_tx_data),
    .s_axis_nclk(axis_n_clk_tx_data),
    .m_axis_nclk(axis_n_clk_rx_data)
); 

/**
 * Network stack
 */

// Network
metaIntf #(.STYPE(logic[ARP_LUP_REQ_BITS-1:0])) arp_lookup_request_n_clk();
metaIntf #(.STYPE(logic[ARP_LUP_RSP_BITS-1:0])) arp_lookup_reply_n_clk();
metaIntf #(.STYPE(logic[IP_ADDR_BITS-1:0])) set_ip_addr_n_clk();
metaIntf #(.STYPE(logic[MAC_ADDR_BITS-1:0])) set_mac_addr_n_clk();
net_stat_t net_stats_n_clk;
metaIntf #(.STYPE(logic[31:0])) drop_rx_n_clk();
metaIntf #(.STYPE(logic[31:0])) drop_tx_n_clk();
logic clear_drop_n_clk;

metaIntf #(.STYPE(logic[ARP_LUP_REQ_BITS-1:0])) arp_lookup_request_aclk_slice();
metaIntf #(.STYPE(logic[ARP_LUP_RSP_BITS-1:0])) arp_lookup_reply_aclk_slice();
metaIntf #(.STYPE(logic[IP_ADDR_BITS-1:0])) set_ip_addr_aclk_slice();
metaIntf #(.STYPE(logic[MAC_ADDR_BITS-1:0])) set_mac_addr_aclk_slice();
net_stat_t net_stats_aclk_slice;
metaIntf #(.STYPE(logic[31:0])) drop_rx_aclk_slice();
metaIntf #(.STYPE(logic[31:0])) drop_tx_aclk_slice();
logic clear_drop_aclk_slice;

// RDMA
metaIntf #(.STYPE(logic[RDMA_QP_INTF_BITS-1:0])) rdma_qp_interface_n_clk();
metaIntf #(.STYPE(logic[RDMA_QP_CONN_BITS-1:0])) rdma_conn_interface_n_clk();

metaIntf #(.STYPE(logic[RDMA_QP_INTF_BITS-1:0])) rdma_qp_interface_aclk_slice();
metaIntf #(.STYPE(logic[RDMA_QP_CONN_BITS-1:0])) rdma_conn_interface_aclk_slice();

metaIntf #(.STYPE(rdma_req_t)) rdma_sq_n_clk();
metaIntf #(.STYPE(rdma_ack_t)) rdma_ack_n_clk();
metaIntf #(.STYPE(req_t)) rdma_rd_req_n_clk ();
metaIntf #(.STYPE(req_t)) rdma_wr_req_n_clk ();
AXI4S #(.AXI4S_DATA_BITS(AXI_DDR_BITS)) axis_rdma_rd_n_clk ();
AXI4S #(.AXI4S_DATA_BITS(AXI_DDR_BITS)) axis_rdma_wr_n_clk ();

metaIntf #(.STYPE(rdma_req_t)) rdma_sq_aclk ();
metaIntf #(.STYPE(rdma_ack_t)) rdma_ack_aclk ();
metaIntf #(.STYPE(req_t)) rdma_rd_req_aclk ();
metaIntf #(.STYPE(req_t)) rdma_wr_req_aclk ();
AXI4S #(.AXI4S_DATA_BITS(AXI_DDR_BITS)) axis_rdma_rd_aclk ();
AXI4S #(.AXI4S_DATA_BITS(AXI_DDR_BITS)) axis_rdma_wr_aclk ();

// TCP/IP
metaIntf #(.STYPE(logic[TCP_MEM_CMD_BITS-1:0])) tcp_mem_rd_cmd_n_clk [N_TCP_CHANNELS] ();
metaIntf #(.STYPE(logic[TCP_MEM_CMD_BITS-1:0])) tcp_mem_wr_cmd_n_clk [N_TCP_CHANNELS] ();
metaIntf #(.STYPE(logic[TCP_MEM_STS_BITS-1:0])) tcp_mem_rd_sts_n_clk [N_TCP_CHANNELS] ();
metaIntf #(.STYPE(logic[TCP_MEM_STS_BITS-1:0])) tcp_mem_wr_sts_n_clk [N_TCP_CHANNELS] ();
AXI4S #(.AXI4S_DATA_BITS(AXI_DDR_BITS)) axis_tcp_mem_rd_n_clk [N_TCP_CHANNELS] ();
AXI4S #(.AXI4S_DATA_BITS(AXI_DDR_BITS)) axis_tcp_mem_wr_n_clk [N_TCP_CHANNELS] ();

metaIntf #(.STYPE(logic[TCP_MEM_CMD_BITS-1:0])) tcp_mem_rd_cmd_aclk ();
metaIntf #(.STYPE(logic[TCP_MEM_CMD_BITS-1:0])) tcp_mem_wr_cmd_aclk ();
metaIntf #(.STYPE(logic[TCP_MEM_STS_BITS-1:0])) tcp_mem_rd_sts_aclk ();
metaIntf #(.STYPE(logic[TCP_MEM_STS_BITS-1:0])) tcp_mem_wr_sts_aclk ();
AXI4S #(.AXI4S_DATA_BITS(AXI_DDR_BITS)) axis_tcp_mem_rd_aclk ();
AXI4S #(.AXI4S_DATA_BITS(AXI_DDR_BITS)) axis_tcp_mem_wr_aclk ();

metaIntf #(.STYPE(tcp_listen_req_t)) tcp_listen_req_n_clk ();
metaIntf #(.STYPE(tcp_listen_rsp_t)) tcp_listen_rsp_n_clk ();
metaIntf #(.STYPE(tcp_open_req_t)) tcp_open_req_n_clk ();
metaIntf #(.STYPE(tcp_open_rsp_t)) tcp_open_rsp_n_clk ();
metaIntf #(.STYPE(tcp_close_req_t)) tcp_close_req_n_clk ();
metaIntf #(.STYPE(tcp_notify_t)) tcp_notify_n_clk ();
metaIntf #(.STYPE(tcp_rd_pkg_t)) tcp_rd_pkg_n_clk ();
metaIntf #(.STYPE(tcp_rx_meta_t)) tcp_rx_meta_n_clk ();
metaIntf #(.STYPE(tcp_tx_meta_t)) tcp_tx_meta_n_clk ();
metaIntf #(.STYPE(tcp_tx_stat_t)) tcp_tx_stat_n_clk ();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_tcp_rx_n_clk ();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_tcp_tx_n_clk ();

metaIntf #(.STYPE(tcp_listen_req_t)) tcp_listen_req_aclk ();
metaIntf #(.STYPE(tcp_listen_rsp_t)) tcp_listen_rsp_aclk ();
metaIntf #(.STYPE(tcp_open_req_t)) tcp_open_req_aclk ();
metaIntf #(.STYPE(tcp_open_rsp_t)) tcp_open_rsp_aclk ();
metaIntf #(.STYPE(tcp_close_req_t)) tcp_close_req_aclk ();
metaIntf #(.STYPE(tcp_notify_t)) tcp_notify_aclk ();
metaIntf #(.STYPE(tcp_rd_pkg_t)) tcp_rd_pkg_aclk ();
metaIntf #(.STYPE(tcp_rx_meta_t)) tcp_rx_meta_aclk ();
metaIntf #(.STYPE(tcp_tx_meta_t)) tcp_tx_meta_aclk ();
metaIntf #(.STYPE(tcp_tx_stat_t)) tcp_tx_stat_aclk ();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_tcp_rx_aclk ();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_tcp_tx_aclk ();

// Regs
logic [N_REG_NET_S0:0][63:0] ddr_offset_addr;
AXI4 axi_tcp_ddr_slice ();

/**
 * Network dropper
 */
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_n_clk_rx_ddata();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_n_clk_tx_ddata();

network_dropper 
inst_network_dropper (
    .s_axis_net(axis_n_clk_rx_data),
    .m_axis_net(axis_n_clk_tx_data),
    .s_axis_user(axis_n_clk_tx_ddata),
    .m_axis_user(axis_n_clk_rx_ddata),
`ifdef NET_DROP
    .pckt_drop_rx(drop_rx_n_clk),
    .pckt_drop_tx(drop_tx_n_clk),
    .clear_drop(clear_drop_n_clk),
`endif
    .nclk(n_clk),
    .nresetn(n_resetn)
);

/**
 * Network stack
 */
network_stack #(
    .ENABLE_RDMA(ENABLE_RDMA),
    .ENABLE_TCP(ENABLE_TCP)
) inst_network_stack (
    .s_axis_net(axis_n_clk_rx_ddata),
    .m_axis_net(axis_n_clk_tx_ddata),

    .s_arp_lookup_request(arp_lookup_request_n_clk),
    .m_arp_lookup_reply(arp_lookup_reply_n_clk),
    .s_set_ip_addr(set_ip_addr_n_clk),
    .s_set_mac_addr(set_mac_addr_n_clk),
`ifdef EN_STATS
    .m_net_stats(net_stats_n_clk),
`endif

    .s_rdma_qp_interface(rdma_qp_interface_n_clk),
    .s_rdma_conn_interface(rdma_conn_interface_n_clk),

    .s_rdma_sq(rdma_sq_n_clk),
    .m_rdma_ack(rdma_ack_n_clk),
    .m_rdma_rd_req(rdma_rd_req_n_clk),
    .m_rdma_wr_req(rdma_wr_req_n_clk),
    .s_axis_rdma_rd(axis_rdma_rd_n_clk),
    .m_axis_rdma_wr(axis_rdma_wr_n_clk),

    .m_tcp_mem_rd_cmd(tcp_mem_rd_cmd_n_clk),
    .m_tcp_mem_wr_cmd(tcp_mem_wr_cmd_n_clk),
    .s_tcp_mem_rd_sts(tcp_mem_rd_sts_n_clk),
    .s_tcp_mem_wr_sts(tcp_mem_wr_sts_n_clk),
    .s_axis_tcp_mem_rd(axis_tcp_mem_rd_n_clk),
    .m_axis_tcp_mem_wr(axis_tcp_mem_wr_n_clk),

    .s_tcp_listen_req(tcp_listen_req_n_clk),
    .m_tcp_listen_rsp(tcp_listen_rsp_n_clk),
    .s_tcp_open_req(tcp_open_req_n_clk),
    .m_tcp_open_rsp(tcp_open_rsp_n_clk),
    .s_tcp_close_req(tcp_close_req_n_clk),
    .m_tcp_notify(tcp_notify_n_clk),
    .s_tcp_rd_pkg(tcp_rd_pkg_n_clk),
    .m_tcp_rx_meta(tcp_rx_meta_n_clk),
    .s_tcp_tx_meta(tcp_tx_meta_n_clk),
    .m_tcp_tx_stat(tcp_tx_stat_n_clk),
    .s_axis_tcp_tx(axis_tcp_tx_n_clk),
    .m_axis_tcp_rx(axis_tcp_rx_n_clk),

    .nclk(n_clk),
    .nresetn(n_resetn)
);

/**
 * Config 
 */
network_ccross_late #(
    .ENABLED(CROSS_LATE)
) inst_network_ccross_late (
    // Network
    .m_arp_lookup_request_nclk(arp_lookup_request_n_clk),
    .s_arp_lookup_reply_nclk(arp_lookup_reply_n_clk),
    .m_set_ip_addr_nclk(set_ip_addr_n_clk),
    .m_set_mac_addr_nclk(set_mac_addr_n_clk),
`ifdef EN_STATS
    .s_net_stats_nclk(net_stats_n_clk), 
`endif
`ifdef NET_DROP
    .m_drop_rx_nclk(drop_rx_n_clk),
    .m_drop_tx_nclk(drop_tx_n_clk),
    .m_clear_drop_nclk(clear_drop_n_clk),
`endif
    
    // User
    .s_arp_lookup_request_aclk(arp_lookup_request_aclk_slice),
    .m_arp_lookup_reply_aclk(arp_lookup_reply_aclk_slice),
    .s_set_ip_addr_aclk(set_ip_addr_aclk_slice),
    .s_set_mac_addr_aclk(set_mac_addr_aclk_slice),
`ifdef EN_STATS
    .m_net_stats_aclk(net_stats_aclk_slice),
`endif
`ifdef NET_DROP
    .s_drop_rx_aclk(drop_rx_aclk_slice),
    .s_drop_tx_aclk(drop_tx_aclk_slice),
    .s_clear_drop_aclk(clear_drop_aclk_slice),
`endif

    .nclk(n_clk),
    .nresetn(n_resetn),
    .aclk(aclk),
    .aresetn(aresetn)
);

// Slicing
network_slice_array #(
    .N_STAGES(N_REG_NET_S0)  
) inst_network_slice_array (
    // Network
    .m_arp_lookup_request_n(arp_lookup_request_aclk_slice),
    .s_arp_lookup_reply_n(arp_lookup_reply_aclk_slice),
    .m_set_ip_addr_n(set_ip_addr_aclk_slice),
    .m_set_mac_addr_n(set_mac_addr_aclk_slice),
`ifdef EN_STATS
    .s_net_stats_n(net_stats_aclk_slice),
`endif
`ifdef NET_DROP
    .m_drop_rx_n(drop_rx_aclk_slice),
    .m_drop_tx_n(drop_tx_aclk_slice),
    .m_clear_drop_n(clear_drop_aclk_slice),
`endif
    
    // User
    .s_arp_lookup_request_u(s_arp_lookup_request),
    .m_arp_lookup_reply_u(m_arp_lookup_reply),
    .s_set_ip_addr_u(s_set_ip_addr),
    .s_set_mac_addr_u(s_set_mac_addr),
`ifdef EN_STATS
    .m_net_stats_u(m_net_stats),
`endif
`ifdef NET_DROP
    .s_drop_rx_u(s_drop_rx),
    .s_drop_tx_u(s_drop_tx),
    .s_clear_drop_u(s_clear_drop),
`endif

    .aclk(aclk),
    .aresetn(aresetn)
);

/**
 * RDMA
 */
if(ENABLE_RDMA == 1) begin
`ifdef EN_RDMA

    // RDMA late cross
    rdma_ccross_late #(
        .ENABLED(CROSS_LATE)
    ) inst_rdma_clk_cross_late (
        // Network
        .m_rdma_qp_interface_nclk(rdma_qp_interface_n_clk),
        .m_rdma_conn_interface_nclk(rdma_conn_interface_n_clk),

        .m_rdma_sq_nclk(rdma_sq_n_clk),
        .s_rdma_ack_nclk(rdma_ack_n_clk),
        .s_rdma_rd_req_nclk(rdma_rd_req_n_clk),
        .s_rdma_wr_req_nclk(rdma_wr_req_n_clk),
        .m_axis_rdma_rd_nclk(axis_rdma_rd_n_clk),
        .s_axis_rdma_wr_nclk(axis_rdma_wr_n_clk),
        
        // User
        .s_rdma_qp_interface_aclk(rdma_qp_interface_aclk_slice),
        .s_rdma_conn_interface_aclk(rdma_conn_interface_aclk_slice),

        .s_rdma_sq_aclk(rdma_sq_aclk),
        .m_rdma_ack_aclk(rdma_ack_aclk),
        .m_rdma_rd_req_aclk(rdma_rd_req_aclk),
        .m_rdma_wr_req_aclk(rdma_wr_req_aclk),
        .s_axis_rdma_rd_aclk(axis_rdma_rd_aclk),
        .m_axis_rdma_wr_aclk(axis_rdma_wr_aclk),

        .nclk(n_clk),
        .nresetn(n_resetn),
        .aclk(aclk),
        .aresetn(aresetn)
    );

    // RDMA slicing
    rdma_slice_array #( 
        .N_STAGES(N_REG_NET_S0)
    ) inst_rdma_slice_array (
        // Network
        .m_rdma_sq_n(rdma_sq_aclk),
        .s_rdma_ack_n(rdma_ack_aclk),
        .s_rdma_rd_req_n(rdma_rd_req_aclk),
        .s_rdma_wr_req_n(rdma_wr_req_aclk),
        .m_axis_rdma_rd_n(axis_rdma_rd_aclk),
        .s_axis_rdma_wr_n(axis_rdma_wr_aclk),

        // User
        .s_rdma_sq_u(s_rdma_sq),
        .m_rdma_ack_u(m_rdma_ack),
        .m_rdma_rd_req_u(m_rdma_rd_req),
        .m_rdma_wr_req_u(m_rdma_wr_req),
        .s_axis_rdma_rd_u(s_axis_rdma_rd),
        .m_axis_rdma_wr_u(m_axis_rdma_wr),
        
        .aclk(aclk),
        .aresetn(aresetn)
    );

    // RDMA control slicing
    rdma_slice_ctrl_array #(
        .N_STAGES(N_REG_NET_S0)
    ) inst_rdma_ctrl_array (
        // Network
        .m_rdma_qp_interface_n(rdma_qp_interface_aclk_slice),
        .m_rdma_conn_interface_n(rdma_conn_interface_aclk_slice),

        // User
        .s_rdma_qp_interface_u(s_rdma_qp_interface),
        .s_rdma_conn_interface_u(s_rdma_conn_interface),

        .aclk(aclk),
        .aresetn(aresetn)
    );

`endif
end

/**
 * TCP/IP
 */
if(ENABLE_TCP == 1) begin
`ifdef EN_TCP

    tcp_ccross_late #(
        .ENABLED(CROSS_LATE)
    ) inst_tcp_ccross_late (
        // Network
        .s_tcp_mem_rd_cmd_nclk(tcp_mem_rd_cmd_n_clk[0]),
        .s_tcp_mem_wr_cmd_nclk(tcp_mem_wr_cmd_n_clk[0]),
        .m_tcp_mem_rd_sts_nclk(tcp_mem_rd_sts_n_clk[0]),
        .m_tcp_mem_wr_sts_nclk(tcp_mem_wr_sts_n_clk[0]),
        .m_axis_tcp_mem_rd_nclk(axis_tcp_mem_rd_n_clk[0]),
        .s_axis_tcp_mem_wr_nclk(axis_tcp_mem_wr_n_clk[0]),

        .m_tcp_listen_req_nclk(tcp_listen_req_n_clk),
        .s_tcp_listen_rsp_nclk(tcp_listen_rsp_n_clk),    
        .m_tcp_open_req_nclk(tcp_open_req_n_clk),
        .s_tcp_open_rsp_nclk(tcp_open_rsp_n_clk),
        .m_tcp_close_req_nclk(tcp_close_req_n_clk),
        .s_tcp_notify_nclk(tcp_notify_n_clk),
        .m_tcp_rd_pkg_nclk(tcp_rd_pkg_n_clk),
        .s_tcp_rx_meta_nclk(tcp_rx_meta_n_clk),
        .m_tcp_tx_meta_nclk(tcp_tx_meta_n_clk),
        .s_tcp_tx_stat_nclk(tcp_tx_stat_n_clk),
        .m_axis_tcp_tx_nclk(axis_tcp_tx_n_clk),
        .s_axis_tcp_rx_nclk(axis_tcp_rx_n_clk),
        
        
        // User
        .m_tcp_mem_rd_cmd_aclk(tcp_mem_rd_cmd_aclk),
        .m_tcp_mem_wr_cmd_aclk(tcp_mem_wr_cmd_aclk),
        .s_tcp_mem_rd_sts_aclk(tcp_mem_rd_sts_aclk),
        .s_tcp_mem_wr_sts_aclk(tcp_mem_wr_sts_aclk),
        .s_axis_tcp_mem_rd_aclk(axis_tcp_mem_rd_aclk),
        .m_axis_tcp_mem_wr_aclk(axis_tcp_mem_wr_aclk),

        .s_tcp_listen_req_aclk(tcp_listen_req_aclk),
        .m_tcp_listen_rsp_aclk(tcp_listen_rsp_aclk),   
        .s_tcp_open_req_aclk(tcp_open_req_aclk),
        .m_tcp_open_rsp_aclk(tcp_open_rsp_aclk),
        .s_tcp_close_req_aclk(tcp_close_req_aclk),      
        .m_tcp_notify_aclk(tcp_notify_aclk),
        .s_tcp_rd_pkg_aclk(tcp_rd_pkg_aclk),       
        .m_tcp_rx_meta_aclk(tcp_rx_meta_aclk),
        .s_tcp_tx_meta_aclk(tcp_tx_meta_aclk),
        .m_tcp_tx_stat_aclk(tcp_tx_stat_aclk),  
        .s_axis_tcp_tx_aclk(axis_tcp_tx_aclk),
        .m_axis_tcp_rx_aclk(axis_tcp_rx_aclk),

        .nclk(n_clk),
        .nresetn(n_resetn),
        .aclk(aclk),
        .aresetn(aresetn)
    );

    // Memory commands
    tcp_mem_intf #(
        .ENABLE(1),
        .UNALIGNED(0 < N_TCP_CHANNELS)
    ) inst_tcp_mem_intf_0 (
        .aclk(aclk),
        .aresetn(aresetn),
        .addr_offset(ddr_offset_addr[N_REG_NET_S0]),
        .s_mem_rd_cmd(tcp_mem_rd_cmd_aclk),
        .s_mem_wr_cmd(tcp_mem_wr_cmd_aclk),
        .m_mem_rd_sts(tcp_mem_rd_sts_aclk),
        .m_mem_wr_sts(tcp_mem_wr_sts_aclk),
        .m_axis_rd_data(axis_tcp_mem_rd_aclk),
        .s_axis_wr_data(axis_tcp_mem_wr_aclk),
        .m_axi_mem(axi_tcp_ddr_slice)
    );

    // TCP slicing
    tcp_slice_array #( 
        .N_STAGES(N_REG_NET_S0)
    ) inst_tcp_slice_array (
        // Network
        .m_tcp_listen_req_n(tcp_listen_req_aclk),
        .s_tcp_listen_rsp_n(tcp_listen_rsp_aclk),
        .m_tcp_open_req_n(tcp_open_req_aclk),
        .s_tcp_open_rsp_n(tcp_open_rsp_aclk),
        .m_tcp_close_req_n(tcp_close_req_aclk),
        .s_tcp_notify_n(tcp_notify_aclk),
        .m_tcp_rd_pkg_n(tcp_rd_pkg_aclk),
        .s_tcp_rx_meta_n(tcp_rx_meta_aclk),
        .m_tcp_tx_meta_n(tcp_tx_meta_aclk),
        .s_tcp_tx_stat_n(tcp_tx_stat_aclk),
        .m_axis_tcp_tx_n(axis_tcp_tx_aclk),
        .s_axis_tcp_rx_n(axis_tcp_rx_aclk),
        

        // User
        .s_tcp_listen_req_u(s_tcp_listen_req),
        .m_tcp_listen_rsp_u(m_tcp_listen_rsp),
        .s_tcp_open_req_u(s_tcp_open_req),
        .m_tcp_open_rsp_u(m_tcp_open_rsp),
        .s_tcp_close_req_u(s_tcp_close_req),
        .m_tcp_notify_u(m_tcp_notify),
        .s_tcp_rd_pkg_u(s_tcp_rd_pkg),
        .m_tcp_rx_meta_u(m_tcp_rx_meta),
        .s_tcp_tx_meta_u(s_tcp_tx_meta),
        .m_tcp_tx_stat_u(m_tcp_tx_stat),
        .s_axis_tcp_tx_u(s_axis_tcp_tx),
        .m_axis_tcp_rx_u(m_axis_tcp_rx),
        
        .aclk(aclk),
        .aresetn(aresetn)
    );

    // Memory commands slicing
    assign ddr_offset_addr[0] = s_ddr_offset_addr;

    always_ff @( posedge  aclk ) begin
        if(~aresetn)
            for(int i = 0; i < N_REG_NET_S0; i++)
                ddr_offset_addr[i+1] <= 'X;
        else
            for(int i = 0; i < N_REG_NET_S0; i++)
                ddr_offset_addr[i+1] <= ddr_offset_addr[i];
    end    

    axi_reg_array #(.N_STAGES(N_REG_NET_S0)) (.aclk(aclk), .aresetn(aresetn), .s_axi(axi_tcp_ddr_slice), .m_axi(m_axi_tcp_ddr));

`endif
end


endmodule
