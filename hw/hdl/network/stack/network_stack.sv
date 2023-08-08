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

`define IP_VERSION4

/**
 * @brief   Network stack
 *
 * Intantiates either an RDMA or a TCP/IP core
 */
module network_stack #(
    parameter IPV6_ADDRESS= 128'hE59D_02FF_FF35_0A02_0000_0000_0000_80FE, //LSB first: FE80_0000_0000_0000_020A_35FF_FF02_9DE5,
    parameter IP_SUBNET_MASK = 32'h00FFFFFF,
    parameter IP_DEFAULT_GATEWAY = 32'h00000000,
    parameter DHCP_EN   = 0,
    parameter ENABLE_TCP = 0,
    parameter ENABLE_RDMA = 0
)(
    input  wire                 nclk,
    input  wire                 nresetn,

    /* Init */
    metaIntf.s                  s_arp_lookup_request,
    metaIntf.m                  m_arp_lookup_reply,
    metaIntf.s                  s_set_ip_addr,
    metaIntf.s                  s_set_mac_addr,
`ifdef EN_STATS
    output net_stat_t           m_net_stats,
`endif

    /* QP interface */
    metaIntf.s                  s_rdma_qp_interface,
    metaIntf.s                  s_rdma_conn_interface,

    /* Commands */
    metaIntf.s                  s_rdma_sq,
    metaIntf.m                  m_rdma_ack,

    /* Roce */
    metaIntf.m                  m_rdma_rd_req,
    metaIntf.m                  m_rdma_wr_req,
    AXI4S.s                     s_axis_rdma_rd,
    AXI4S.m                     m_axis_rdma_wr,

    /* Mem */
    metaIntf.m                  m_tcp_mem_rd_cmd [N_TCP_CHANNELS],
    metaIntf.m                  m_tcp_mem_wr_cmd [N_TCP_CHANNELS],
    metaIntf.s                  s_tcp_mem_rd_sts [N_TCP_CHANNELS],
    metaIntf.s                  s_tcp_mem_wr_sts [N_TCP_CHANNELS],
    AXI4S.s                     s_axis_tcp_mem_rd [N_TCP_CHANNELS],
    AXI4S.m                     m_axis_tcp_mem_wr [N_TCP_CHANNELS],

    /* Interface */
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

    /* Network streams */
    AXI4S.s                     s_axis_net,
    AXI4S.m                     m_axis_net
);

// Sync the reset (timing)
(* DONT_TOUCH = "yes" *)
logic nresetn_r = 1'b1;
(* DONT_TOUCH = "yes" *)
logic nresetn_r_int = 1'b1;

always_ff @(posedge nclk) begin
    nresetn_r_int <= nresetn;
    nresetn_r <= nresetn_r_int;
end


// Ip handler
// ---------------------------------------------------------------------------------------------
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_slice_to_ibh();

AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_iph_to_arp_slice();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_iph_to_icmp_slice();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_iph_to_icmpv6_slice();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_iph_to_rocev6_slice();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_iph_to_toe_slice();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_iph_to_udp_slice();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_iph_to_roce_slice();

//Slice connections 
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_arp_slice_to_arp();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_arp_to_arp_slice();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_arp_to_arp_slice_r();

AXI4S #(.AXI4S_DATA_BITS(64)) axis_icmp_slice_to_icmp();
AXI4S #(.AXI4S_DATA_BITS(64)) axis_icmp_to_icmp_slice(); 
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS))axis_icmp_slice_to_merge();

AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_udp_to_udp_slice();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_udp_slice_to_udp();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_udp_slice_to_merge();

AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_toe_slice_to_toe();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_toe_to_toe_slice();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_toe_slice_to_merge();

AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_roce_to_roce_slice();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_roce_slice_to_roce();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_roce_slice_to_merge();

// ARP lookup
// ---------------------------------------------------------------------------------------------
metaIntf #(.STYPE(logic[56-1:0])) axis_arp_lookup_reply ();
metaIntf #(.STYPE(logic[32-1:0])) axis_arp_lookup_request ();

metaIntf #(.STYPE(logic[56-1:0])) axis_arp_lookup_reply_r ();
metaIntf #(.STYPE(logic[32-1:0])) axis_arp_lookup_request_r ();


// IP and MAC
// ---------------------------------------------------------------------------------------------
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_intercon_to_mie();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_intercon_to_mie_r();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_mie_to_intercon();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_mie_to_intercon_r();

// Register and distribute ip address
wire[31:0]  dhcp_ip_address;
wire        dhcp_ip_address_en;
reg[47:0]   mie_mac_address;
reg[47:0]   arp_mac_address;
reg[47:0]   ipv6_mac_address;
reg[31:0]   iph_ip_address;
reg[31:0]   arp_ip_address;
reg[31:0]   toe_ip_address;
reg[31:0]   ip_subnet_mask;
reg[31:0]   ip_default_gateway;
reg[127:0]  link_local_ipv6_address;

// Network controller
// ---------------------------------------------------------------------------------------------
reg [IP_ADDR_BITS-1:0] local_ip_address;
reg [MAC_ADDR_BITS-1:0] local_mac_address;

// Statistics
// ---------------------------------------------------------------------------------------------
logic[15:0] arp_request_pkg_counter;
logic[15:0] arp_reply_pkg_counter;

logic[31:0] regIbvRxPkgCount;
logic       regIbvRxPkgCount_valid;
logic[31:0] regIbvTxPkgCount;
logic       regIbvTxPkgCount_valid;
logic[31:0] regCrcDropPkgCount;
logic       regCrcDropPkgCount_valid;
logic[31:0] regInvalidPsnDropCount;
logic       regInvalidPsnDropCount_valid;
logic[31:0] regRetransCount;
logic       regRetransCount_valid;

logic       session_count_valid;
logic[15:0] session_count_data;


// ---------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------

/**
 * Addresses
 */

//assign dhcp_ip_address_en = 1'b1;
//assign dhcp_ip_address = 32'hD1D4010A;

always @(posedge nclk)
begin
    if (nresetn_r == 0) begin
        mie_mac_address <= 48'h000000000000;
        arp_mac_address <= 48'h000000000000;
        ipv6_mac_address <= 48'h000000000000;
        iph_ip_address <= 32'h00000000;
        arp_ip_address <= 32'h00000000;
        toe_ip_address <= 32'h00000000;
        ip_subnet_mask <= 32'h00000000;
        ip_default_gateway <= 32'h00000000;
        link_local_ipv6_address <= 0;
    end
    else begin
        mie_mac_address <= local_mac_address;
        arp_mac_address <= local_mac_address;
        ipv6_mac_address <= local_mac_address; 
        //link_local_ipv6_address[127:80] <= ipv6_mac_address;
        //link_local_ipv6_address[15:0] <= 16'h80fe; // fe80
        //link_local_ipv6_address[79:16] <= 64'h0000_0000_0000_0000;
        //link_local_ipv6_address <= {IPV6_ADDRESS[127:120]+local_mac_address, IPV6_ADDRESS[119:0]};
        if (DHCP_EN == 1) begin
            if (dhcp_ip_address_en == 1'b1) begin
                iph_ip_address <= dhcp_ip_address;
                arp_ip_address <= dhcp_ip_address;
                toe_ip_address <= dhcp_ip_address;
            end
        end
        else begin
            iph_ip_address <= local_ip_address;
            arp_ip_address <= local_ip_address;
            toe_ip_address <= local_ip_address;
            ip_subnet_mask <= IP_SUBNET_MASK;
            ip_default_gateway <= {local_ip_address[31:28], 8'h01, local_ip_address[23:0]};
        end
    end
end

// Local IP
always @(posedge nclk) begin
    if (~nresetn_r) begin
        local_ip_address <= DEF_IP_ADDRESS;
        local_mac_address <= DEF_MAC_ADDRESS;
    end
    else begin
        if (s_set_ip_addr.valid) begin
            local_ip_address[7:0] <= s_set_ip_addr.data[31:24];
            local_ip_address[15:8] <= s_set_ip_addr.data[23:16];
            local_ip_address[23:16] <= s_set_ip_addr.data[15:8];
            local_ip_address[31:24] <= s_set_ip_addr.data[7:0];
        end
        if (s_set_mac_addr.valid) begin
            local_mac_address[7:0] <= s_set_mac_addr.data[47:40];
            local_mac_address[15:8] <= s_set_mac_addr.data[39:32];
            local_mac_address[23:16] <= s_set_mac_addr.data[31:24];
            local_mac_address[31:24] <= s_set_mac_addr.data[23:16];
            local_mac_address[39:32] <= s_set_mac_addr.data[15:8];
            local_mac_address[47:40] <= s_set_mac_addr.data[7:0];
        end
    end
end

assign s_set_ip_addr.ready = 1'b1;
assign s_set_mac_addr.ready = 1'b1;

vio_ip inst_vio_ip (
    .clk(nclk),
    .probe_in0(local_ip_address), // 32
    .probe_in1(local_mac_address) // 48
);

/**
 * IP handler
 */

// In slice
axis_reg inst_slice_in (.aclk(nclk), .aresetn(nresetn_r), .s_axis(s_axis_net), .m_axis(axis_slice_to_ibh));
/*
vio_stack_1 inst_vio_stack_1 (
    .clk(nclk),
    .probe_in0(s_axis_net.tready),
    .probe_in1(axis_iph_to_arp_slice.tready),
    .probe_in2(axis_iph_to_icmp_slice.tready),
    .probe_in3(axis_iph_to_udp_slice.tready),
    .probe_in4(axis_iph_to_toe_slice.tready),
    .probe_in5(axis_iph_to_roce_slice.tready),
    .probe_in6(axis_iph_to_icmpv6_slice.tready),
    .probe_in7(axis_iph_to_rocev6_slice.tready),
    
    .probe_in8(s_axis_net.tvalid),
    .probe_in9(axis_iph_to_arp_slice.tvalid),
    .probe_in10(axis_iph_to_icmp_slice.tvalid),
    .probe_in11(axis_iph_to_udp_slice.tvalid),
    .probe_in12(axis_iph_to_toe_slice.tvalid),
    .probe_in13(axis_iph_to_roce_slice.tvalid),
    .probe_in14(axis_iph_to_icmpv6_slice.tvalid),
    .probe_in15(axis_iph_to_rocev6_slice.tvalid)
);
*/
// IP handler
ip_handler_ip ip_handler_inst ( 
    .m_axis_arp_TVALID(axis_iph_to_arp_slice.tvalid), // output AXI4Stream_M_TVALID
    .m_axis_arp_TREADY(axis_iph_to_arp_slice.tready), // input AXI4Stream_M_TREADY
    .m_axis_arp_TDATA(axis_iph_to_arp_slice.tdata), // output [63 : 0] AXI4Stream_M_TDATA
    .m_axis_arp_TKEEP(axis_iph_to_arp_slice.tkeep), // output [7 : 0] AXI4Stream_M_TSTRB
    .m_axis_arp_TLAST(axis_iph_to_arp_slice.tlast), // output [0 : 0] AXI4Stream_M_TLAST

    .m_axis_icmp_TVALID(axis_iph_to_icmp_slice.tvalid), // output AXI4Stream_M_TVALID
    .m_axis_icmp_TREADY(axis_iph_to_icmp_slice.tready), // input AXI4Stream_M_TREADY
    .m_axis_icmp_TDATA(axis_iph_to_icmp_slice.tdata), // output [63 : 0] AXI4Stream_M_TDATA
    .m_axis_icmp_TKEEP(axis_iph_to_icmp_slice.tkeep), // output [7 : 0] AXI4Stream_M_TSTRB
    .m_axis_icmp_TLAST(axis_iph_to_icmp_slice.tlast), // output [0 : 0] AXI4Stream_M_TLAST

    .m_axis_icmpv6_TVALID(axis_iph_to_icmpv6_slice.tvalid),
    .m_axis_icmpv6_TREADY(axis_iph_to_icmpv6_slice.tready),
    .m_axis_icmpv6_TDATA(axis_iph_to_icmpv6_slice.tdata),
    .m_axis_icmpv6_TKEEP(axis_iph_to_icmpv6_slice.tkeep),
    .m_axis_icmpv6_TLAST(axis_iph_to_icmpv6_slice.tlast),

    .m_axis_ipv6udp_TVALID(axis_iph_to_rocev6_slice.tvalid),
    .m_axis_ipv6udp_TREADY(axis_iph_to_rocev6_slice.tready),
    .m_axis_ipv6udp_TDATA(axis_iph_to_rocev6_slice.tdata), 
    .m_axis_ipv6udp_TKEEP(axis_iph_to_rocev6_slice.tkeep),
    .m_axis_ipv6udp_TLAST(axis_iph_to_rocev6_slice.tlast),

    .m_axis_udp_TVALID(axis_iph_to_udp_slice.tvalid),
    .m_axis_udp_TREADY(axis_iph_to_udp_slice.tready),
    .m_axis_udp_TDATA(axis_iph_to_udp_slice.tdata),
    .m_axis_udp_TKEEP(axis_iph_to_udp_slice.tkeep),
    .m_axis_udp_TLAST(axis_iph_to_udp_slice.tlast),

    .m_axis_tcp_TVALID(axis_iph_to_toe_slice.tvalid),
    .m_axis_tcp_TREADY(axis_iph_to_toe_slice.tready),
    .m_axis_tcp_TDATA(axis_iph_to_toe_slice.tdata),
    .m_axis_tcp_TKEEP(axis_iph_to_toe_slice.tkeep),
    .m_axis_tcp_TLAST(axis_iph_to_toe_slice.tlast),

    .m_axis_roce_TVALID(axis_iph_to_roce_slice.tvalid),
    .m_axis_roce_TREADY(axis_iph_to_roce_slice.tready),
    .m_axis_roce_TDATA(axis_iph_to_roce_slice.tdata),
    .m_axis_roce_TKEEP(axis_iph_to_roce_slice.tkeep),
    .m_axis_roce_TLAST(axis_iph_to_roce_slice.tlast),

    .s_axis_raw_TVALID(axis_slice_to_ibh.tvalid),
    .s_axis_raw_TREADY(axis_slice_to_ibh.tready),
    .s_axis_raw_TDATA(axis_slice_to_ibh.tdata),
    .s_axis_raw_TKEEP(axis_slice_to_ibh.tkeep),
    .s_axis_raw_TLAST(axis_slice_to_ibh.tlast),

`ifdef VITIS_HLS
    .myIpAddress(iph_ip_address),
`else
    .myIpAddress_V(iph_ip_address),
`endif

    .ap_clk(nclk), // input aclk
    .ap_rst_n(nresetn_r) // input aresetn
); 

// Tie-off
assign axis_iph_to_icmpv6_slice.tready = 1'b1;
assign axis_iph_to_rocev6_slice.tready = 1'b1;

// IP handler -> out slices
// ARP
axis_reg_array inst_reg_array_0 (.aclk(nclk), .aresetn(nresetn_r), .s_axis(axis_iph_to_arp_slice), .m_axis(axis_arp_slice_to_arp));

axis_512_to_64_converter icmp_in_data_converter (
    .aclk(nclk),
    .aresetn(nresetn_r),
    .s_axis_tvalid(axis_iph_to_icmp_slice.tvalid),
    .s_axis_tready(axis_iph_to_icmp_slice.tready),
    .s_axis_tdata(axis_iph_to_icmp_slice.tdata),
    .s_axis_tkeep(axis_iph_to_icmp_slice.tkeep),
    .s_axis_tlast(axis_iph_to_icmp_slice.tlast),
    .m_axis_tvalid(axis_icmp_slice_to_icmp.tvalid),
    .m_axis_tready(axis_icmp_slice_to_icmp.tready),
    .m_axis_tdata(axis_icmp_slice_to_icmp.tdata),
    .m_axis_tkeep(axis_icmp_slice_to_icmp.tkeep),
    .m_axis_tlast(axis_icmp_slice_to_icmp.tlast)
);

icmp_server_ip icmp_server_inst (
    .s_axis_TVALID(axis_icmp_slice_to_icmp.tvalid),    // input wire dataIn_TVALID
    .s_axis_TREADY(axis_icmp_slice_to_icmp.tready),    // output wire dataIn_TREADY
    .s_axis_TDATA(axis_icmp_slice_to_icmp.tdata),      // input wire [63 : 0] dataIn_TDATA
    .s_axis_TKEEP(axis_icmp_slice_to_icmp.tkeep),      // input wire [7 : 0] dataIn_TKEEP
    .s_axis_TLAST(axis_icmp_slice_to_icmp.tlast),      // input wire [0 : 0] dataIn_TLAST
    .udpIn_TVALID(1'b0),//(axis_udp_to_icmp_tvalid),           // input wire udpIn_TVALID
    .udpIn_TREADY(),           // output wire udpIn_TREADY
    .udpIn_TDATA(0),//(axis_udp_to_icmp_tdata),             // input wire [63 : 0] udpIn_TDATA
    .udpIn_TKEEP(0),//(axis_udp_to_icmp_tkeep),             // input wire [7 : 0] udpIn_TKEEP
    .udpIn_TLAST(0),//(axis_udp_to_icmp_tlast),             // input wire [0 : 0] udpIn_TLAST
    .ttlIn_TVALID(1'b0),//(axis_ttl_to_icmp_tvalid),           // input wire ttlIn_TVALID
    .ttlIn_TREADY(),           // output wire ttlIn_TREADY
    .ttlIn_TDATA(0),//(axis_ttl_to_icmp_tdata),             // input wire [63 : 0] ttlIn_TDATA
    .ttlIn_TKEEP(0),//(axis_ttl_to_icmp_tkeep),             // input wire [7 : 0] ttlIn_TKEEP
    .ttlIn_TLAST(0),//(axis_ttl_to_icmp_tlast),             // input wire [0 : 0] ttlIn_TLAST
    .m_axis_TVALID(axis_icmp_to_icmp_slice.tvalid),   // output wire dataOut_TVALID
    .m_axis_TREADY(axis_icmp_to_icmp_slice.tready),   // input wire dataOut_TREADY
    .m_axis_TDATA(axis_icmp_to_icmp_slice.tdata),     // output wire [63 : 0] dataOut_TDATA
    .m_axis_TKEEP(axis_icmp_to_icmp_slice.tkeep),     // output wire [7 : 0] dataOut_TKEEP
    .m_axis_TLAST(axis_icmp_to_icmp_slice.tlast),     // output wire [0 : 0] dataOut_TLAST
    .ap_clk(nclk),                                    // input wire ap_clk
    .ap_rst_n(nresetn_r)                                // input wire ap_rst_n
);

axis_64_to_512_converter icmp_out_data_converter (
    .aclk(nclk),
    .aresetn(nresetn_r),
    .s_axis_tvalid(axis_icmp_to_icmp_slice.tvalid),
    .s_axis_tready(axis_icmp_to_icmp_slice.tready),
    .s_axis_tdata(axis_icmp_to_icmp_slice.tdata),
    .s_axis_tkeep(axis_icmp_to_icmp_slice.tkeep),
    .s_axis_tlast(axis_icmp_to_icmp_slice.tlast),
    .s_axis_tdest(0),
    .m_axis_tvalid(axis_icmp_slice_to_merge.tvalid),
    .m_axis_tready(axis_icmp_slice_to_merge.tready),
    .m_axis_tdata(axis_icmp_slice_to_merge.tdata),
    .m_axis_tkeep(axis_icmp_slice_to_merge.tkeep),
    .m_axis_tlast(axis_icmp_slice_to_merge.tlast),
    .m_axis_tdest()
);

// UDP
axis_reg inst_slice_out_1 (.aclk(nclk), .aresetn(nresetn_r), .s_axis(axis_iph_to_udp_slice), .m_axis(axis_udp_slice_to_udp));
assign axis_udp_slice_to_udp.tready = 1'b1;

// TCP
axis_reg_array inst_slice_out_2 (.aclk(nclk), .aresetn(nresetn_r), .s_axis(axis_iph_to_toe_slice), .m_axis(axis_toe_slice_to_toe));
if(ENABLE_TCP == 0) begin
assign axis_toe_slice_to_toe.tready = 1'b1;
end

// Roce
axis_reg_array inst_slice_out_3 (.aclk(nclk), .aresetn(nresetn_r), .s_axis(axis_iph_to_roce_slice), .m_axis(axis_roce_slice_to_roce));
if(ENABLE_RDMA == 0) begin
assign axis_roce_slice_to_roce.tready = 1'b1;
end

/**
 * Merge TX
 */

// UDP
axis_reg_array inst_slice_out_4 (.aclk(nclk), .aresetn(nresetn_r), .s_axis(axis_udp_to_udp_slice), .m_axis(axis_udp_slice_to_merge));
assign axis_udp_to_udp_slice.tvalid = 1'b0;

// TCP
axis_reg_array inst_slice_out_5 (.aclk(nclk), .aresetn(nresetn_r), .s_axis(axis_toe_to_toe_slice), .m_axis(axis_toe_slice_to_merge));
if(ENABLE_TCP == 0) begin
assign axis_toe_to_toe_slice.tvalid = 1'b0;
end
// Roce
axis_reg_array inst_slice_out_6 (.aclk(nclk), .aresetn(nresetn_r), .s_axis(axis_roce_to_roce_slice), .m_axis(axis_roce_slice_to_merge));
if(ENABLE_RDMA == 0) begin
assign axis_roce_to_roce_slice.tvalid = 1'b0;
end

axis_interconnect_512_4to1 ip_merger (
    .ACLK(nclk),                                  // input wire ACLK
    .ARESETN(nresetn_r),                            // input wire ARESETN
    .S00_AXIS_ACLK(nclk),                // input wire S00_AXIS_ACLK
    .S01_AXIS_ACLK(nclk),                // input wire S01_AXIS_ACLK
    .S02_AXIS_ACLK(nclk),                // input wire S02_AXIS_ACLK
    .S03_AXIS_ACLK(nclk),                // input wire S03_AXIS_ACLK
    .S00_AXIS_ARESETN(nresetn_r),          // input wire S00_AXIS_ARESETN
    .S01_AXIS_ARESETN(nresetn_r),          // input wire S01_AXIS_ARESETN
    .S02_AXIS_ARESETN(nresetn_r),          // input wire S02_AXIS_ARESETN
    .S03_AXIS_ARESETN(nresetn_r),          // input wire S03_AXIS_ARESETN

    .S00_AXIS_TVALID(axis_icmp_slice_to_merge.tvalid),            // input wire S00_AXIS_TVALID
    .S00_AXIS_TREADY(axis_icmp_slice_to_merge.tready),            // output wire S00_AXIS_TREADY
    .S00_AXIS_TDATA(axis_icmp_slice_to_merge.tdata),              // input wire [63 : 0] S00_AXIS_TDATA
    .S00_AXIS_TKEEP(axis_icmp_slice_to_merge.tkeep),              // input wire [7 : 0] S00_AXIS_TKEEP
    .S00_AXIS_TLAST(axis_icmp_slice_to_merge.tlast),              // input wire S00_AXIS_TLAST

    .S01_AXIS_TVALID(axis_udp_slice_to_merge.tvalid),            // input wire S01_AXIS_TVALID
    .S01_AXIS_TREADY(axis_udp_slice_to_merge.tready),            // output wire S01_AXIS_TREADY
    .S01_AXIS_TDATA(axis_udp_slice_to_merge.tdata),              // input wire [63 : 0] S01_AXIS_TDATA
    .S01_AXIS_TKEEP(axis_udp_slice_to_merge.tkeep),              // input wire [7 : 0] S01_AXIS_TKEEP
    .S01_AXIS_TLAST(axis_udp_slice_to_merge.tlast),              // input wire S01_AXIS_TLAST

    .S02_AXIS_TVALID(axis_toe_slice_to_merge.tvalid),            // input wire S02_AXIS_TVALID
    .S02_AXIS_TREADY(axis_toe_slice_to_merge.tready),            // output wire S02_AXIS_TREADY
    .S02_AXIS_TDATA(axis_toe_slice_to_merge.tdata),              // input wire [63 : 0] S02_AXIS_TDATA
    .S02_AXIS_TKEEP(axis_toe_slice_to_merge.tkeep),              // input wire [7 : 0] S02_AXIS_TKEEP
    .S02_AXIS_TLAST(axis_toe_slice_to_merge.tlast),              // input wire S02_AXIS_TLAST

    .S03_AXIS_TVALID(axis_roce_slice_to_merge.tvalid),            // input wire S01_AXIS_TVALID
    .S03_AXIS_TREADY(axis_roce_slice_to_merge.tready),            // output wire S01_AXIS_TREADY
    .S03_AXIS_TDATA(axis_roce_slice_to_merge.tdata),              // input wire [63 : 0] S01_AXIS_TDATA
    .S03_AXIS_TKEEP(axis_roce_slice_to_merge.tkeep),              // input wire [7 : 0] S01_AXIS_TKEEP
    .S03_AXIS_TLAST(axis_roce_slice_to_merge.tlast),              // input wire S01_AXIS_TLAST

    .M00_AXIS_ACLK(nclk),                // input wire M00_AXIS_ACLK
    .M00_AXIS_ARESETN(nresetn_r),          // input wire M00_AXIS_ARESETN
    .M00_AXIS_TVALID(axis_intercon_to_mie.tvalid),            // output wire M00_AXIS_TVALID
    .M00_AXIS_TREADY(axis_intercon_to_mie.tready),            // input wire M00_AXIS_TREADY
    .M00_AXIS_TDATA(axis_intercon_to_mie.tdata),              // output wire [63 : 0] M00_AXIS_TDATA
    .M00_AXIS_TKEEP(axis_intercon_to_mie.tkeep),              // output wire [7 : 0] M00_AXIS_TKEEP
    .M00_AXIS_TLAST(axis_intercon_to_mie.tlast),              // output wire M00_AXIS_TLAST
    .S00_ARB_REQ_SUPPRESS(1'b0),  // input wire S00_ARB_REQ_SUPPRESS
    .S01_ARB_REQ_SUPPRESS(1'b0),  // input wire S01_ARB_REQ_SUPPRESS
    .S02_ARB_REQ_SUPPRESS(1'b0),  // input wire S02_ARB_REQ_SUPPRESS
    .S03_ARB_REQ_SUPPRESS(1'b0)  // input wire S02_ARB_REQ_SUPPRESS
);

/**
 * ARP lookup
 */

meta_reg_array #(.DATA_BITS(32)) inst_meta_slice_00 (.aclk(nclk), .aresetn(nresetn_r), .s_meta(axis_arp_lookup_request), .m_meta(axis_arp_lookup_request_r));
meta_reg_array #(.DATA_BITS(56)) inst_meta_slice_10 (.aclk(nclk), .aresetn(nresetn_r), .s_meta(axis_arp_lookup_reply),   .m_meta(axis_arp_lookup_reply_r));
axis_reg_array inst_reg_slice_mie (.aclk(nclk), .aresetn(nresetn_r), .s_axis(axis_intercon_to_mie), .m_axis(axis_intercon_to_mie_r));

mac_ip_encode_ip mac_ip_encode_inst (
`ifdef VITIS_HLS
    .m_axis_ip_TVALID(axis_mie_to_intercon.tvalid),
    .m_axis_ip_TREADY(axis_mie_to_intercon.tready),
    .m_axis_ip_TDATA(axis_mie_to_intercon.tdata),
    .m_axis_ip_TKEEP(axis_mie_to_intercon.tkeep),
    .m_axis_ip_TLAST(axis_mie_to_intercon.tlast),
    .m_axis_arp_lookup_request_TVALID(axis_arp_lookup_request.valid),
    .m_axis_arp_lookup_request_TREADY(axis_arp_lookup_request.ready),
    .m_axis_arp_lookup_request_TDATA(axis_arp_lookup_request.data),
    .s_axis_ip_TVALID(axis_intercon_to_mie_r.tvalid),
    .s_axis_ip_TREADY(axis_intercon_to_mie_r.tready),
    .s_axis_ip_TDATA(axis_intercon_to_mie_r.tdata),
    .s_axis_ip_TKEEP(axis_intercon_to_mie_r.tkeep),
    .s_axis_ip_TLAST(axis_intercon_to_mie_r.tlast),
    .s_axis_arp_lookup_reply_TVALID(axis_arp_lookup_reply_r.valid),
    .s_axis_arp_lookup_reply_TREADY(axis_arp_lookup_reply_r.ready),
    .s_axis_arp_lookup_reply_TDATA(axis_arp_lookup_reply_r.data),

    .myMacAddress(mie_mac_address),                                    // input wire [47 : 0] regMacAddress_V
    .regSubNetMask(ip_subnet_mask),                                    // input wire [31 : 0] regSubNetMask_V
    .regDefaultGateway(ip_default_gateway),                            // input wire [31 : 0] regDefaultGateway_V
    
    .ap_clk(nclk), // input aclk
    .ap_rst_n(nresetn_r) // input aresetn
`else
    .m_axis_ip_TVALID(axis_mie_to_intercon.tvalid),
    .m_axis_ip_TREADY(axis_mie_to_intercon.tready),
    .m_axis_ip_TDATA(axis_mie_to_intercon.tdata),
    .m_axis_ip_TKEEP(axis_mie_to_intercon.tkeep),
    .m_axis_ip_TLAST(axis_mie_to_intercon.tlast),
    .m_axis_arp_lookup_request_V_V_TVALID(axis_arp_lookup_request.valid),
    .m_axis_arp_lookup_request_V_V_TREADY(axis_arp_lookup_request.ready),
    .m_axis_arp_lookup_request_V_V_TDATA(axis_arp_lookup_request.data),
    .s_axis_ip_TVALID(axis_intercon_to_mie_r.tvalid),
    .s_axis_ip_TREADY(axis_intercon_to_mie_r.tready),
    .s_axis_ip_TDATA(axis_intercon_to_mie_r.tdata),
    .s_axis_ip_TKEEP(axis_intercon_to_mie_r.tkeep),
    .s_axis_ip_TLAST(axis_intercon_to_mie_r.tlast),
    .s_axis_arp_lookup_reply_V_TVALID(axis_arp_lookup_reply_r.valid),
    .s_axis_arp_lookup_reply_V_TREADY(axis_arp_lookup_reply_r.ready),
    .s_axis_arp_lookup_reply_V_TDATA(axis_arp_lookup_reply_r.data),

    .myMacAddress_V(mie_mac_address),                                    // input wire [47 : 0] regMacAddress_V
    .regSubNetMask_V(ip_subnet_mask),                                    // input wire [31 : 0] regSubNetMask_V
    .regDefaultGateway_V(ip_default_gateway),                            // input wire [31 : 0] regDefaultGateway_V
    
    .ap_clk(nclk), // input aclk
    .ap_rst_n(nresetn_r) // input aresetn
`endif
);

/**
 * Merges IP and ARP 
 */
axis_reg_array inst_reg_slice_mie_ic (.aclk(nclk), .aresetn(nresetn_r), .s_axis(axis_mie_to_intercon), .m_axis(axis_mie_to_intercon_r));
axis_reg_array inst_reg_slice_arp_r (.aclk(nclk), .aresetn(nresetn_r), .s_axis(axis_arp_to_arp_slice), .m_axis(axis_arp_to_arp_slice_r));

axis_interconnect_512_2to1 mac_merger (
    .ACLK(nclk), // input ACLK
    .ARESETN(nresetn_r), // input ARESETN
    .S00_AXIS_ACLK(nclk), // input S00_AXIS_ACLK
    .S01_AXIS_ACLK(nclk), // input S01_AXIS_ACLK
    //.S02_AXIS_ACLK(nclk), // input S01_AXIS_ACLK
    .S00_AXIS_ARESETN(nresetn_r), // input S00_AXIS_ARESETN
    .S01_AXIS_ARESETN(nresetn_r), // input S01_AXIS_ARESETN
    //.S02_AXIS_ARESETN(nresetn_r), // input S01_AXIS_ARESETN
    .S00_AXIS_TVALID(axis_arp_to_arp_slice_r.tvalid), // input S00_AXIS_TVALID
    .S00_AXIS_TREADY(axis_arp_to_arp_slice_r.tready), // output S00_AXIS_TREADY
    .S00_AXIS_TDATA(axis_arp_to_arp_slice_r.tdata), // input [63 : 0] S00_AXIS_TDATA
    .S00_AXIS_TKEEP(axis_arp_to_arp_slice_r.tkeep), // input [7 : 0] S00_AXIS_TKEEP
    .S00_AXIS_TLAST(axis_arp_to_arp_slice_r.tlast), // input S00_AXIS_TLAST

    .S01_AXIS_TVALID(axis_mie_to_intercon_r.tvalid), // input S01_AXIS_TVALID
    .S01_AXIS_TREADY(axis_mie_to_intercon_r.tready), // output S01_AXIS_TREADY
    .S01_AXIS_TDATA(axis_mie_to_intercon_r.tdata), // input [63 : 0] S01_AXIS_TDATA
    .S01_AXIS_TKEEP(axis_mie_to_intercon_r.tkeep), // input [7 : 0] S01_AXIS_TKEEP
    .S01_AXIS_TLAST(axis_mie_to_intercon_r.tlast), // input S01_AXIS_TLAST

    /*.S02_AXIS_TVALID(axis_ethencode_to_intercon.valid), // input S01_AXIS_TVALID
    .S02_AXIS_TREADY(axis_ethencode_to_intercon.ready), // output S01_AXIS_TREADY
    .S02_AXIS_TDATA(axis_ethencode_to_intercon.data), // input [63 : 0] S01_AXIS_TDATA
    .S02_AXIS_TKEEP(axis_ethencode_to_intercon.keep), // input [7 : 0] S01_AXIS_TKEEP
    .S02_AXIS_TLAST(axis_ethencode_to_intercon.last), // input S01_AXIS_TLAST*/

    .M00_AXIS_ACLK(nclk), // input M00_AXIS_ACLK
    .M00_AXIS_ARESETN(nresetn_r), // input M00_AXIS_ARESETN
    .M00_AXIS_TVALID(m_axis_net.tvalid), // output M00_AXIS_TVALID
    .M00_AXIS_TREADY(m_axis_net.tready), // input M00_AXIS_TREADY
    .M00_AXIS_TDATA(m_axis_net.tdata), // output [63 : 0] M00_AXIS_TDATA
    .M00_AXIS_TKEEP(m_axis_net.tkeep), // output [7 : 0] M00_AXIS_TKEEP
    .M00_AXIS_TLAST(m_axis_net.tlast), // output M00_AXIS_TLAST
    .S00_ARB_REQ_SUPPRESS(1'b0), // input S00_ARB_REQ_SUPPRESS
    .S01_ARB_REQ_SUPPRESS(1'b0) // input S01_ARB_REQ_SUPPRESS
    //.S02_ARB_REQ_SUPPRESS(1'b0) // input S01_ARB_REQ_SUPPRESS
);

arp_server_subnet_ip arp_server_inst(
`ifdef VITIS_HLS
    .m_axis_TVALID(axis_arp_to_arp_slice.tvalid),
    .m_axis_TREADY(axis_arp_to_arp_slice.tready),
    .m_axis_TDATA(axis_arp_to_arp_slice.tdata),
    .m_axis_TKEEP(axis_arp_to_arp_slice.tkeep),
    .m_axis_TLAST(axis_arp_to_arp_slice.tlast),
    .m_axis_arp_lookup_reply_TVALID(axis_arp_lookup_reply.valid),
    .m_axis_arp_lookup_reply_TREADY(axis_arp_lookup_reply.ready),
    .m_axis_arp_lookup_reply_TDATA(axis_arp_lookup_reply.data),
    .m_axis_host_arp_lookup_reply_TVALID(m_arp_lookup_reply.valid), //axis_host_arp_lookup_reply_TVALID),
    .m_axis_host_arp_lookup_reply_TREADY(m_arp_lookup_reply.ready), //axis_host_arp_lookup_reply_TREADY),
    .m_axis_host_arp_lookup_reply_TDATA(m_arp_lookup_reply.data), //axis_host_arp_lookup_reply_TDATA),
    .s_axis_TVALID(axis_arp_slice_to_arp.tvalid),
    .s_axis_TREADY(axis_arp_slice_to_arp.tready),
    .s_axis_TDATA(axis_arp_slice_to_arp.tdata),
    .s_axis_TKEEP(axis_arp_slice_to_arp.tkeep),
    .s_axis_TLAST(axis_arp_slice_to_arp.tlast),
    .s_axis_arp_lookup_request_TVALID(axis_arp_lookup_request_r.valid),
    .s_axis_arp_lookup_request_TREADY(axis_arp_lookup_request_r.ready),
    .s_axis_arp_lookup_request_TDATA(axis_arp_lookup_request_r.data),
    .s_axis_host_arp_lookup_request_TVALID(s_arp_lookup_request.valid), //axis_host_arp_lookup_request_TVALID),
    .s_axis_host_arp_lookup_request_TREADY(s_arp_lookup_request.ready), //axis_host_arp_lookup_request_TREADY),
    .s_axis_host_arp_lookup_request_TDATA(s_arp_lookup_request.data), //axis_host_arp_lookup_request_TDATA),

    .myMacAddress(arp_mac_address),
    .myIpAddress(arp_ip_address),
    .regRequestCount(arp_request_pkg_counter),
    .regRequestCount_ap_vld(),
    .regReplyCount(arp_reply_pkg_counter),
    .regReplyCount_ap_vld(),

    .ap_clk(nclk), // input aclk
    .ap_rst_n(nresetn_r) // input aresetn
`else
    .m_axis_TVALID(axis_arp_to_arp_slice.tvalid),
    .m_axis_TREADY(axis_arp_to_arp_slice.tready),
    .m_axis_TDATA(axis_arp_to_arp_slice.tdata),
    .m_axis_TKEEP(axis_arp_to_arp_slice.tkeep),
    .m_axis_TLAST(axis_arp_to_arp_slice.tlast),
    .m_axis_arp_lookup_reply_V_TVALID(axis_arp_lookup_reply.valid),
    .m_axis_arp_lookup_reply_V_TREADY(axis_arp_lookup_reply.ready),
    .m_axis_arp_lookup_reply_V_TDATA(axis_arp_lookup_reply.data),
    .m_axis_host_arp_lookup_reply_V_TVALID(m_arp_lookup_reply.valid), //axis_host_arp_lookup_reply_TVALID),
    .m_axis_host_arp_lookup_reply_V_TREADY(m_arp_lookup_reply.ready), //axis_host_arp_lookup_reply_TREADY),
    .m_axis_host_arp_lookup_reply_V_TDATA(m_arp_lookup_reply.data), //axis_host_arp_lookup_reply_TDATA),
    .s_axis_TVALID(axis_arp_slice_to_arp.tvalid),
    .s_axis_TREADY(axis_arp_slice_to_arp.tready),
    .s_axis_TDATA(axis_arp_slice_to_arp.tdata),
    .s_axis_TKEEP(axis_arp_slice_to_arp.tkeep),
    .s_axis_TLAST(axis_arp_slice_to_arp.tlast),
    .s_axis_arp_lookup_request_V_V_TVALID(axis_arp_lookup_request_r.valid),
    .s_axis_arp_lookup_request_V_V_TREADY(axis_arp_lookup_request_r.ready),
    .s_axis_arp_lookup_request_V_V_TDATA(axis_arp_lookup_request_r.data),
    .s_axis_host_arp_lookup_request_V_V_TVALID(s_arp_lookup_request.valid), //axis_host_arp_lookup_request_TVALID),
    .s_axis_host_arp_lookup_request_V_V_TREADY(s_arp_lookup_request.ready), //axis_host_arp_lookup_request_TREADY),
    .s_axis_host_arp_lookup_request_V_V_TDATA(s_arp_lookup_request.data), //axis_host_arp_lookup_request_TDATA),

    .myMacAddress_V(arp_mac_address),
    .myIpAddress_V(arp_ip_address),
    .regRequestCount_V(arp_request_pkg_counter),
    .regRequestCount_V_ap_vld(),
    .regReplyCount_V(arp_reply_pkg_counter),
    .regReplyCount_V_ap_vld(),

    .ap_clk(nclk), // input aclk
    .ap_rst_n(nresetn_r) // input aresetn
`endif
);

// RDMA --------------------------------------------------------------
// -------------------------------------------------------------------
if(ENABLE_RDMA == 1) begin
`ifdef EN_RDMA

/**
 * RoCE stack
 */

roce_stack inst_roce_stack (
    .nclk(nclk), // input aclk
    .nresetn(nresetn_r), // input aresetn

    // IPv4
    .s_axis_rx(axis_roce_slice_to_roce),
    .m_axis_tx(axis_roce_to_roce_slice),
    
    // Control
    .s_rdma_qp_interface(s_rdma_qp_interface),
    .s_rdma_conn_interface(s_rdma_conn_interface),

    // User
    .s_rdma_sq(s_rdma_sq),
    .m_rdma_ack(m_rdma_ack),
    
    // Memory
    .m_rdma_rd_req(m_rdma_rd_req),
    .m_rdma_wr_req(m_rdma_wr_req),
    .s_axis_rdma_rd(s_axis_rdma_rd),
    .m_axis_rdma_wr(m_axis_rdma_wr),
    
    //.local_ip_address_V(link_local_ipv6_address), // Use IPv6 addr
    .local_ip_address(iph_ip_address), //Use IPv4 addr

    // Debug
    .ibv_rx_pkg_count_valid(regIbvRxPkgCount_valid),
    .ibv_rx_pkg_count_data(regIbvRxPkgCount),
    .ibv_tx_pkg_count_valid(regIbvTxPkgCount_valid),
    .ibv_tx_pkg_count_data(regIbvTxPkgCount),
    .crc_drop_pkg_count_valid(regCrcDropPkgCount_valid),
    .crc_drop_pkg_count_data(regCrcDropPkgCount),
    .psn_drop_pkg_count_valid(regInvalidPsnDropCount_valid),
    .psn_drop_pkg_count_data(regInvalidPsnDropCount),
    .retrans_count_valid(regRetransCount_valid),
    .retrans_count_data(regRetransCount)
);
/*
ila_roce inst_ila_roce (
    .clk(nclk),
    .probe0(axis_roce_slice_to_roce.tvalid),
    .probe1(axis_roce_slice_to_roce.tready),
    .probe2(axis_roce_slice_to_roce.tlast),
    .probe3(axis_roce_to_roce_slice.tvalid),
    .probe4(axis_roce_to_roce_slice.tready),
    .probe5(axis_roce_to_roce_slice.tlast),
    .probe6(m_rdma_rd_req.valid),
    .probe7(m_rdma_rd_req.ready),
    .probe8(m_rdma_rd_req.data), // 96
    .probe9(m_rdma_wr_req.valid), 
    .probe10(m_rdma_wr_req.ready),
    .probe11(m_rdma_wr_req.data), // 96
    .probe12(s_rdma_sq.valid),
    .probe13(s_rdma_sq.ready),
    .probe14(s_rdma_sq.data), // 256
    
    .probe15(m_axis_rdma_wr.tvalid),
    .probe16(m_axis_rdma_wr.tready),
    .probe17(m_axis_rdma_wr.tdata), // 512
    .probe18(m_axis_rdma_wr.tlast),
    .probe19(axis_roce_to_roce_slice.tdata), // 512
    .probe20(axis_roce_slice_to_roce.tdata), // 512
    
    .probe21(s_axis_net.tvalid),
    .probe22(s_axis_net.tready),
    .probe23(s_axis_net.tdata), // 512
    .probe24(s_axis_net.tlast),
    
    .probe25(m_axis_net.tvalid),
    .probe26(m_axis_net.tready),
    .probe27(m_axis_net.tdata), // 512
    .probe28(m_axis_net.tlast)
);
*/
/*
create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_roce
set_property -dict [list CONFIG.C_PROBE27_WIDTH {512} CONFIG.C_PROBE23_WIDTH {512} CONFIG.C_PROBE20_WIDTH {512} CONFIG.C_PROBE19_WIDTH {512} CONFIG.C_PROBE17_WIDTH {512} CONFIG.C_PROBE14_WIDTH {256} CONFIG.C_PROBE11_WIDTH {96} CONFIG.C_PROBE8_WIDTH {96} CONFIG.C_DATA_DEPTH {2048} CONFIG.C_NUM_OF_PROBES {29} CONFIG.Component_Name {ila_roce} CONFIG.C_EN_STRG_QUAL {1} CONFIG.C_PROBE28_MU_CNT {2} CONFIG.C_PROBE27_MU_CNT {2} CONFIG.C_PROBE26_MU_CNT {2} CONFIG.C_PROBE25_MU_CNT {2} CONFIG.C_PROBE24_MU_CNT {2} CONFIG.C_PROBE23_MU_CNT {2} CONFIG.C_PROBE22_MU_CNT {2} CONFIG.C_PROBE21_MU_CNT {2} CONFIG.C_PROBE20_MU_CNT {2} CONFIG.C_PROBE19_MU_CNT {2} CONFIG.C_PROBE18_MU_CNT {2} CONFIG.C_PROBE17_MU_CNT {2} CONFIG.C_PROBE16_MU_CNT {2} CONFIG.C_PROBE15_MU_CNT {2} CONFIG.C_PROBE14_MU_CNT {2} CONFIG.C_PROBE13_MU_CNT {2} CONFIG.C_PROBE12_MU_CNT {2} CONFIG.C_PROBE11_MU_CNT {2} CONFIG.C_PROBE10_MU_CNT {2} CONFIG.C_PROBE9_MU_CNT {2} CONFIG.C_PROBE8_MU_CNT {2} CONFIG.C_PROBE7_MU_CNT {2} CONFIG.C_PROBE6_MU_CNT {2} CONFIG.C_PROBE5_MU_CNT {2} CONFIG.C_PROBE4_MU_CNT {2} CONFIG.C_PROBE3_MU_CNT {2} CONFIG.C_PROBE2_MU_CNT {2} CONFIG.C_PROBE1_MU_CNT {2} CONFIG.C_PROBE0_MU_CNT {2} CONFIG.ALL_PROBE_SAME_MU_CNT {2}] [get_ips ila_roce]
*/

`endif
end

// TCP/IP ------------------------------------------------------------
// -------------------------------------------------------------------
if(ENABLE_TCP == 1) begin
`ifdef EN_TCP

/**
 * TCP/IP stack
 */

tcp_stack tcp_stack_inst(
    .nclk(nclk), // input aclk
    .nresetn(nresetn), // input aresetn
    
    // Streams to network
    .s_axis_rx(axis_toe_slice_to_toe),
    .m_axis_tx(axis_toe_to_toe_slice),
    
    // Memory cmd streams
    .m_tcp_mem_rd_cmd(m_tcp_mem_rd_cmd),
    .m_tcp_mem_wr_cmd(m_tcp_mem_wr_cmd),
    // Memory sts streams
    .s_tcp_mem_rd_sts(s_tcp_mem_rd_sts),
    .s_tcp_mem_wr_sts(s_tcp_mem_wr_sts),
    // Memory data streams
    .s_axis_tcp_mem_rd(s_axis_tcp_mem_rd),
    .m_axis_tcp_mem_wr(m_axis_tcp_mem_wr),
    
    // Application
    .s_tcp_listen_req(s_tcp_listen_req),
    .m_tcp_listen_rsp(m_tcp_listen_rsp),
    
    .s_tcp_open_req(s_tcp_open_req),
    .m_tcp_open_rsp(m_tcp_open_rsp),
    .s_tcp_close_req(s_tcp_close_req),
    
    .m_tcp_notify(m_tcp_notify),
    .s_tcp_rd_pkg(s_tcp_rd_pkg),
    
    .m_tcp_rx_meta(m_tcp_rx_meta),
    .s_tcp_tx_meta(s_tcp_tx_meta),
    .m_tcp_tx_stat(m_tcp_tx_stat),
    
    .s_axis_tcp_tx(s_axis_tcp_tx),
    .m_axis_tcp_rx(m_axis_tcp_rx),
    
    .local_ip_address(toe_ip_address),
    .session_count_valid(session_count_valid),
    .session_count_data(session_count_data)
);

/*
ila_tcp ila_tcp (
  .clk(nclk), // input wire clk

  .probe0(s_tcp_open_req.valid), // 1
  .probe1(s_tcp_open_req.ready), // 1
  .probe2(m_tcp_open_rsp.valid), // 1  
  .probe3(m_tcp_open_rsp.ready), // 1   
  .probe4(m_axis_tcp_rx.tvalid), // 1
  .probe5(m_axis_tcp_rx.tready), // 1                 
  .probe6(s_tcp_close_req.valid), // 1                        
  .probe7(s_tcp_close_req.ready), // 1                     
  .probe8(s_axis_tcp_tx.tvalid), //1                                                
  .probe9(s_axis_tcp_tx.tready),//1
  .probe10(s_tcp_tx_meta.valid),//1
  .probe11(s_tcp_tx_meta.ready),//1
  .probe12(m_tcp_tx_stat.valid),//1
  .probe13(m_tcp_tx_stat.ready), //1
  .probe14(m_tcp_notify.valid), //1
  .probe15(m_tcp_notify.ready), //1
  .probe16(m_tcp_listen_rsp.valid),  // 1
  .probe17(m_tcp_listen_rsp.ready),  // 1
  .probe18(s_tcp_listen_req.valid),  // 1
  .probe19(s_tcp_listen_req.ready),  //1
  .probe20(m_tcp_rx_meta.valid), // 1
  .probe21(m_tcp_rx_meta.ready), // 1
  .probe22(s_tcp_rd_pkg.valid),  // 1
  .probe23(s_tcp_rd_pkg.ready), //1 

  .probe24(s_tcp_listen_req.data), // 16
  .probe25(m_tcp_listen_rsp.data), // 8
  .probe26(m_tcp_open_rsp.data), // 72    
  .probe27(s_tcp_open_req.data) // 48
);*/

`endif
end

/**
 * Statistics
 */

`ifdef EN_STATS

    logic[31:0] rx_word_counter; 
    logic[31:0] rx_pkg_counter; 
    logic[31:0] tx_word_counter; 
    logic[31:0] tx_pkg_counter;

    logic[31:0] arp_rx_pkg_counter;
    logic[31:0] arp_tx_pkg_counter;
    logic[31:0] icmp_rx_pkg_counter;
    logic[31:0] icmp_tx_pkg_counter;

    logic[31:0] tcp_rx_pkg_counter;
    logic[31:0] tcp_tx_pkg_counter;

    logic[31:0] roce_rx_pkg_counter;
    logic[31:0] roce_tx_pkg_counter;
    logic[31:0] roce_retrans_counter;

    logic[15:0] axis_stream_down_counter;
    logic axis_stream_down;

    net_stat_t[NET_STATS_DELAY-1:0] net_stats_tmp; // Slice

    assign net_stats_tmp[0].rx_pkg_counter = rx_pkg_counter;
    assign net_stats_tmp[0].tx_pkg_counter = tx_pkg_counter;
    assign net_stats_tmp[0].arp_rx_pkg_counter = arp_rx_pkg_counter;
    assign net_stats_tmp[0].arp_tx_pkg_counter = arp_tx_pkg_counter;
    assign net_stats_tmp[0].icmp_rx_pkg_counter = icmp_rx_pkg_counter;
    assign net_stats_tmp[0].icmp_tx_pkg_counter = icmp_tx_pkg_counter;
    assign net_stats_tmp[0].tcp_rx_pkg_counter = tcp_rx_pkg_counter;
    assign net_stats_tmp[0].tcp_tx_pkg_counter = tcp_tx_pkg_counter;
    assign net_stats_tmp[0].roce_rx_pkg_counter = roce_rx_pkg_counter;
    assign net_stats_tmp[0].roce_tx_pkg_counter = roce_tx_pkg_counter;
    assign net_stats_tmp[0].ibv_rx_pkg_counter = regIbvRxPkgCount;
    assign net_stats_tmp[0].ibv_tx_pkg_counter = regIbvTxPkgCount;
    assign net_stats_tmp[0].roce_psn_drop_counter = regInvalidPsnDropCount;
    assign net_stats_tmp[0].roce_retrans_counter = regRetransCount;
    assign net_stats_tmp[0].tcp_session_counter = session_count_data;
    assign net_stats_tmp[0].axis_stream_down = axis_stream_down;

    assign m_net_stats = net_stats_tmp[NET_STATS_DELAY-1];

    always @(posedge nclk) begin
        if (~nresetn_r) begin
            rx_word_counter <= '0;
            rx_pkg_counter <= '0;
            tx_word_counter <= '0;
            tx_pkg_counter <= '0;

            arp_rx_pkg_counter <= '0;
            arp_tx_pkg_counter <= '0;
            icmp_rx_pkg_counter <= 0;
            icmp_tx_pkg_counter <= 0;

            tcp_rx_pkg_counter <= '0;
            tcp_tx_pkg_counter <= '0;
            roce_rx_pkg_counter <= '0;
            roce_tx_pkg_counter <= '0;

            axis_stream_down_counter <= '0;  
            axis_stream_down <= 1'b0;
        end

        // Reg the stats
        for(int i = 1; i < NET_STATS_DELAY; i++) begin
            net_stats_tmp[i] <= net_stats_tmp[i-1];
        end

        // Raw
        if (s_axis_net.tvalid && s_axis_net.tready) begin
            rx_word_counter <= rx_word_counter + 1;
            if (s_axis_net.tlast) begin
                rx_pkg_counter <= rx_pkg_counter + 1;
            end
        end
        if (m_axis_net.tvalid && m_axis_net.tready) begin
            tx_word_counter <= tx_word_counter + 1;
            if (m_axis_net.tlast) begin
                tx_pkg_counter <= tx_pkg_counter + 1;
            end
        end

        //Arp
        if (axis_arp_slice_to_arp.tvalid && axis_arp_slice_to_arp.tready) begin
            if (axis_arp_slice_to_arp.tlast) begin
                arp_rx_pkg_counter <= arp_rx_pkg_counter + 1;
            end
        end
        if (axis_arp_to_arp_slice.tvalid && axis_arp_to_arp_slice.tready) begin
            if (axis_arp_to_arp_slice.tlast) begin
                arp_tx_pkg_counter <= arp_tx_pkg_counter + 1;
            end
        end

        // Icmp
        if (axis_icmp_slice_to_icmp.tvalid && axis_icmp_slice_to_icmp.tready) begin
            if (axis_icmp_slice_to_icmp.tlast) begin
                icmp_rx_pkg_counter <= icmp_rx_pkg_counter + 1;
            end
        end
        if (axis_icmp_to_icmp_slice.tvalid && axis_icmp_to_icmp_slice.tready) begin
            if (axis_icmp_to_icmp_slice.tlast) begin
                icmp_tx_pkg_counter <= icmp_tx_pkg_counter + 1;
            end
        end

        // TCP
        if (axis_toe_slice_to_toe.tvalid && axis_toe_slice_to_toe.tready) begin
            if (axis_toe_slice_to_toe.tlast) begin
                tcp_rx_pkg_counter <= tcp_rx_pkg_counter + 1;
            end
        end
        if (axis_toe_to_toe_slice.tvalid && axis_toe_to_toe_slice.tready) begin
            if (axis_toe_to_toe_slice.tlast) begin
                tcp_tx_pkg_counter <= tcp_tx_pkg_counter + 1;
            end
        end

        // ROCE
        if (axis_roce_slice_to_roce.tvalid && axis_roce_slice_to_roce.tready) begin
            if (axis_roce_slice_to_roce.tlast) begin
                roce_rx_pkg_counter <= roce_rx_pkg_counter + 1;
            end
        end
        if (axis_roce_to_roce_slice.tvalid && axis_roce_to_roce_slice.tready) begin
            if (axis_roce_to_roce_slice.tlast) begin
                roce_tx_pkg_counter <= roce_tx_pkg_counter + 1;
            end
        end

        // Status
        if (s_axis_net.tready) begin
            axis_stream_down_counter <= '0;
        end
        if (s_axis_net.tvalid && ~s_axis_net.tready) begin
            axis_stream_down_counter <= (axis_stream_down_counter == NET_STRM_DOWN_THRS) ? axis_stream_down_counter : axis_stream_down_counter + 1;
        end
        axis_stream_down <= (axis_stream_down_counter == NET_STRM_DOWN_THRS);

    end

`endif

endmodule
