`timescale 1ns / 1ps

import lynxTypes::*;

`define IP_VERSION4

module network_stack #(
    parameter MAC_ADDRESS = 48'hE59D02350A00, // LSB first, 00:0A:35:02:9D:E5
    parameter IPV6_ADDRESS= 128'hE59D_02FF_FF35_0A02_0000_0000_0000_80FE, //LSB first: FE80_0000_0000_0000_020A_35FF_FF02_9DE5,
    parameter IP_SUBNET_MASK = 32'h00FFFFFF,
    parameter IP_DEFAULT_GATEWAY = 32'h00000000,
    parameter DHCP_EN   = 0
)(
    input  wire                 net_clk,
    input  wire                 net_aresetn,

    /* Network streams */
    AXI4S.s                     s_axis_net,
    AXI4S.m                     m_axis_net,

    /* Init */
    metaIntf.s                  arp_lookup_request,
    metaIntf.m                  arp_lookup_reply,
    metaIntf.s                  set_ip_addr,
    metaIntf.s                  set_board_number,
    metaIntf.s                  qp_interface,
    metaIntf.s                  conn_interface,

    /* Commands */
    metaIntf.s                  s_axis_host_meta,
    metaIntf.s                  s_axis_card_meta,
    metaIntf.m                  m_axis_rpc_meta,
    
    /* Roce */
    rdmaIntf.m                  m_axis_roce_read_cmd,
    rdmaIntf.m                  m_axis_roce_write_cmd,
    AXI4S.s                     s_axis_roce_read_data,
    AXI4S.m                     m_axis_roce_write_data
);

// Sync the reset (timing)
(* DONT_TOUCH = "yes" *)
logic net_aresetn_r = 1'b1;

always_ff @(posedge net_clk) begin
  net_aresetn_r <= net_aresetn;
end


// Ip handler
// ---------------------------------------------------------------------------------------------
AXI4S axis_slice_to_ibh();

AXI4S axis_iph_to_arp_slice();
AXI4S axis_iph_to_icmp_slice();
AXI4S axis_iph_to_icmpv6_slice();
AXI4S axis_iph_to_rocev6_slice();
AXI4S axis_iph_to_toe_slice();
AXI4S axis_iph_to_udp_slice();
AXI4S axis_iph_to_roce_slice();

//Slice connections 
AXI4S axis_arp_slice_to_arp();
AXI4S axis_arp_to_arp_slice();

AXI4S #(.AXI4S_DATA_BITS(64)) axis_icmp_slice_to_icmp();
AXI4S #(.AXI4S_DATA_BITS(64)) axis_icmp_to_icmp_slice(); 
AXI4S axis_icmp_slice_to_merge();

AXI4S axis_udp_to_udp_slice();
AXI4S axis_udp_slice_to_udp();
AXI4S axis_udp_slice_to_merge();

AXI4S axis_toe_slice_to_toe();
AXI4S axis_toe_to_toe_slice();
AXI4S axis_toe_slice_to_merge();

AXI4S axis_roce_to_roce_slice();
AXI4S axis_roce_slice_to_roce();
AXI4S axis_roce_slice_to_merge();

// ARP lookup
// ---------------------------------------------------------------------------------------------
metaIntf #(.DATA_BITS(56)) axis_arp_lookup_reply ();
metaIntf #(.DATA_BITS(32)) axis_arp_lookup_request ();

metaIntf #(.DATA_BITS(56)) axis_arp_lookup_reply_r ();
metaIntf #(.DATA_BITS(32)) axis_arp_lookup_request_r ();


// IP and MAC
// ---------------------------------------------------------------------------------------------
AXI4S axis_intercon_to_mie();
AXI4S axis_mie_to_intercon();

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
// TX meta
metaIntf #(.DATA_BITS(FV_REQ_BITS)) axis_tx_metadata();

reg [31:0] local_ip_address;
reg[3:0] board_number;

// Statistics
// ---------------------------------------------------------------------------------------------
logic[15:0] arp_request_pkg_counter;
logic[15:0] arp_reply_pkg_counter;

logic[31:0] regCrcDropPkgCount;
logic       regCrcDropPkgCount_valid;
logic[31:0] regInvalidPsnDropCount;
logic       regInvalidPsnDropCount_valid;

logic[31:0] rx_word_counter; 
logic[31:0] rx_pkg_counter; 
logic[31:0] tx_word_counter; 
logic[31:0] tx_pkg_counter;

logic[31:0] tcp_rx_pkg_counter;
logic[31:0] tcp_tx_pkg_counter;
logic[31:0] udp_rx_pkg_counter;
logic[31:0] udp_tx_pkg_counter;
logic[31:0] roce_rx_pkg_counter;
logic[31:0] roce_tx_pkg_counter;

logic[31:0] roce_data_rx_word_counter;
logic[31:0] roce_data_rx_pkg_counter;
logic[31:0] roce_data_tx_role_word_counter;
logic[31:0] roce_data_tx_role_pkg_counter;
logic[31:0] roce_data_tx_host_word_counter;
logic[31:0] roce_data_tx_host_pkg_counter;

logic[31:0] arp_rx_pkg_counter;
logic[31:0] arp_tx_pkg_counter;
logic[31:0] icmp_rx_pkg_counter;
logic[31:0] icmp_tx_pkg_counter;

reg[7:0] axis_stream_down_counter;
reg axis_stream_down;
reg[7:0] output_stream_down_counter;
reg output_stream_down;


// ---------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------

/**
 * Addresses
 */

//assign dhcp_ip_address_en = 1'b1;
//assign dhcp_ip_address = 32'hD1D4010A;

always @(posedge net_clk)
begin
    if (net_aresetn_r == 0) begin
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
        mie_mac_address <= {MAC_ADDRESS[47:44], (MAC_ADDRESS[43:40]+board_number), MAC_ADDRESS[39:0]};
        arp_mac_address <= {MAC_ADDRESS[47:44], (MAC_ADDRESS[43:40]+board_number), MAC_ADDRESS[39:0]};
        ipv6_mac_address <= {MAC_ADDRESS[47:44], (MAC_ADDRESS[43:40]+board_number), MAC_ADDRESS[39:0]};
        //link_local_ipv6_address[127:80] <= ipv6_mac_address;
        //link_local_ipv6_address[15:0] <= 16'h80fe; // fe80
        //link_local_ipv6_address[79:16] <= 64'h0000_0000_0000_0000;
        link_local_ipv6_address <= {IPV6_ADDRESS[127:120]+board_number, IPV6_ADDRESS[119:0]};
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

/**
 * IP handler
 */

// In slice
axis_reg inst_slice_in (.aclk(net_clk), .aresetn(net_aresetn_r), .axis_in(s_axis_net), .axis_out(axis_slice_to_ibh));

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

    .myIpAddress_V(iph_ip_address),

    .ap_clk(net_clk), // input aclk
    .ap_rst_n(net_aresetn_r) // input aresetn
);

// Tie-off
assign axis_iph_to_icmpv6_slice.tready = 1'b1;
assign axis_iph_to_rocev6_slice.tready = 1'b1;

// IP handler -> out slices
// ARP
axis_reg inst_slice_out_0 (.aclk(net_clk), .aresetn(net_aresetn_r), .axis_in(axis_iph_to_arp_slice), .axis_out(axis_arp_slice_to_arp));

// ICMP
axis_512_to_64_converter icmp_in_data_converter (
    .aclk(net_clk),
    .aresetn(net_aresetn_r),
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
    .ap_clk(net_clk),                                    // input wire ap_clk
    .ap_rst_n(net_aresetn_r)                                // input wire ap_rst_n
);

axis_64_to_512_converter icmp_out_data_converter (
    .aclk(net_clk),
    .aresetn(net_aresetn_r),
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
axis_reg inst_slice_out_1 (.aclk(net_clk), .aresetn(net_aresetn_r), .axis_in(axis_iph_to_udp_slice), .axis_out(axis_udp_slice_to_udp));
assign axis_udp_slice_to_udp.tready = 1'b1;

// TCP
axis_reg inst_slice_out_2 (.aclk(net_clk), .aresetn(net_aresetn_r), .axis_in(axis_iph_to_toe_slice), .axis_out(axis_toe_slice_to_toe));
assign axis_toe_slice_to_toe.tready = 1'b1;

// Roce
axis_reg inst_slice_out_3 (.aclk(net_clk), .aresetn(net_aresetn_r), .axis_in(axis_iph_to_roce_slice), .axis_out(axis_roce_slice_to_roce));

/**
 * Merge TX
 */

// UDP
axis_reg inst_slice_out_4 (.aclk(net_clk), .aresetn(net_aresetn_r), .axis_in(axis_udp_to_udp_slice), .axis_out(axis_udp_slice_to_merge));
assign axis_udp_to_udp_slice.tvalid = 1'b0;

// TCP
axis_reg inst_slice_out_5 (.aclk(net_clk), .aresetn(net_aresetn_r), .axis_in(axis_toe_to_toe_slice), .axis_out(axis_toe_slice_to_merge));
assign axis_toe_to_toe_slice.tvalid = 1'b0;

// Roce
axis_reg inst_slice_out_6 (.aclk(net_clk), .aresetn(net_aresetn_r), .axis_in(axis_roce_to_roce_slice), .axis_out(axis_roce_slice_to_merge));

axis_interconnect_512_4to1 ip_merger (
    .ACLK(net_clk),                                  // input wire ACLK
    .ARESETN(net_aresetn_r),                            // input wire ARESETN
    .S00_AXIS_ACLK(net_clk),                // input wire S00_AXIS_ACLK
    .S01_AXIS_ACLK(net_clk),                // input wire S01_AXIS_ACLK
    .S02_AXIS_ACLK(net_clk),                // input wire S02_AXIS_ACLK
    .S03_AXIS_ACLK(net_clk),                // input wire S03_AXIS_ACLK
    .S00_AXIS_ARESETN(net_aresetn_r),          // input wire S00_AXIS_ARESETN
    .S01_AXIS_ARESETN(net_aresetn_r),          // input wire S01_AXIS_ARESETN
    .S02_AXIS_ARESETN(net_aresetn_r),          // input wire S02_AXIS_ARESETN
    .S03_AXIS_ARESETN(net_aresetn_r),          // input wire S03_AXIS_ARESETN

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

    .M00_AXIS_ACLK(net_clk),                // input wire M00_AXIS_ACLK
    .M00_AXIS_ARESETN(net_aresetn_r),          // input wire M00_AXIS_ARESETN
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

meta_reg #(.DATA_BITS(32)) inst_meta_slice_0 (.aclk(net_clk), .aresetn(net_aresetn_r), .meta_in(axis_arp_lookup_request), .meta_out(axis_arp_lookup_request_r));
meta_reg #(.DATA_BITS(56)) inst_meta_slice_1 (.aclk(net_clk), .aresetn(net_aresetn_r), .meta_in(axis_arp_lookup_reply), .meta_out(axis_arp_lookup_reply_r));

mac_ip_encode_ip mac_ip_encode_inst (
    .m_axis_ip_TVALID(axis_mie_to_intercon.tvalid),
    .m_axis_ip_TREADY(axis_mie_to_intercon.tready),
    .m_axis_ip_TDATA(axis_mie_to_intercon.tdata),
    .m_axis_ip_TKEEP(axis_mie_to_intercon.tkeep),
    .m_axis_ip_TLAST(axis_mie_to_intercon.tlast),
    .m_axis_arp_lookup_request_V_V_TVALID(axis_arp_lookup_request.valid),
    .m_axis_arp_lookup_request_V_V_TREADY(axis_arp_lookup_request.ready),
    .m_axis_arp_lookup_request_V_V_TDATA(axis_arp_lookup_request.data),
    .s_axis_ip_TVALID(axis_intercon_to_mie.tvalid),
    .s_axis_ip_TREADY(axis_intercon_to_mie.tready),
    .s_axis_ip_TDATA(axis_intercon_to_mie.tdata),
    .s_axis_ip_TKEEP(axis_intercon_to_mie.tkeep),
    .s_axis_ip_TLAST(axis_intercon_to_mie.tlast),
    .s_axis_arp_lookup_reply_V_TVALID(axis_arp_lookup_reply_r.valid),
    .s_axis_arp_lookup_reply_V_TREADY(axis_arp_lookup_reply_r.ready),
    .s_axis_arp_lookup_reply_V_TDATA(axis_arp_lookup_reply_r.data),

    .myMacAddress_V(mie_mac_address),                                    // input wire [47 : 0] regMacAddress_V
    .regSubNetMask_V(ip_subnet_mask),                                    // input wire [31 : 0] regSubNetMask_V
    .regDefaultGateway_V(ip_default_gateway),                            // input wire [31 : 0] regDefaultGateway_V
    
    .ap_clk(net_clk), // input aclk
    .ap_rst_n(net_aresetn_r) // input aresetn
);

/**
 * Merges IP and ARP 
 */

axis_interconnect_512_2to1 mac_merger (
    .ACLK(net_clk), // input ACLK
    .ARESETN(net_aresetn_r), // input ARESETN
    .S00_AXIS_ACLK(net_clk), // input S00_AXIS_ACLK
    .S01_AXIS_ACLK(net_clk), // input S01_AXIS_ACLK
    //.S02_AXIS_ACLK(net_clk), // input S01_AXIS_ACLK
    .S00_AXIS_ARESETN(net_aresetn_r), // input S00_AXIS_ARESETN
    .S01_AXIS_ARESETN(net_aresetn_r), // input S01_AXIS_ARESETN
    //.S02_AXIS_ARESETN(net_aresetn_r), // input S01_AXIS_ARESETN
    .S00_AXIS_TVALID(axis_arp_to_arp_slice.tvalid), // input S00_AXIS_TVALID
    .S00_AXIS_TREADY(axis_arp_to_arp_slice.tready), // output S00_AXIS_TREADY
    .S00_AXIS_TDATA(axis_arp_to_arp_slice.tdata), // input [63 : 0] S00_AXIS_TDATA
    .S00_AXIS_TKEEP(axis_arp_to_arp_slice.tkeep), // input [7 : 0] S00_AXIS_TKEEP
    .S00_AXIS_TLAST(axis_arp_to_arp_slice.tlast), // input S00_AXIS_TLAST

    .S01_AXIS_TVALID(axis_mie_to_intercon.tvalid), // input S01_AXIS_TVALID
    .S01_AXIS_TREADY(axis_mie_to_intercon.tready), // output S01_AXIS_TREADY
    .S01_AXIS_TDATA(axis_mie_to_intercon.tdata), // input [63 : 0] S01_AXIS_TDATA
    .S01_AXIS_TKEEP(axis_mie_to_intercon.tkeep), // input [7 : 0] S01_AXIS_TKEEP
    .S01_AXIS_TLAST(axis_mie_to_intercon.tlast), // input S01_AXIS_TLAST

    /*.S02_AXIS_TVALID(axis_ethencode_to_intercon.valid), // input S01_AXIS_TVALID
    .S02_AXIS_TREADY(axis_ethencode_to_intercon.ready), // output S01_AXIS_TREADY
    .S02_AXIS_TDATA(axis_ethencode_to_intercon.data), // input [63 : 0] S01_AXIS_TDATA
    .S02_AXIS_TKEEP(axis_ethencode_to_intercon.keep), // input [7 : 0] S01_AXIS_TKEEP
    .S02_AXIS_TLAST(axis_ethencode_to_intercon.last), // input S01_AXIS_TLAST*/

    .M00_AXIS_ACLK(net_clk), // input M00_AXIS_ACLK
    .M00_AXIS_ARESETN(net_aresetn_r), // input M00_AXIS_ARESETN
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
    .m_axis_TVALID(axis_arp_to_arp_slice.tvalid),
    .m_axis_TREADY(axis_arp_to_arp_slice.tready),
    .m_axis_TDATA(axis_arp_to_arp_slice.tdata),
    .m_axis_TKEEP(axis_arp_to_arp_slice.tkeep),
    .m_axis_TLAST(axis_arp_to_arp_slice.tlast),
    .m_axis_arp_lookup_reply_V_TVALID(axis_arp_lookup_reply.valid),
    .m_axis_arp_lookup_reply_V_TREADY(axis_arp_lookup_reply.ready),
    .m_axis_arp_lookup_reply_V_TDATA(axis_arp_lookup_reply.data),
    .m_axis_host_arp_lookup_reply_V_TVALID(arp_lookup_reply.valid), //axis_host_arp_lookup_reply_TVALID),
    .m_axis_host_arp_lookup_reply_V_TREADY(arp_lookup_reply.ready), //axis_host_arp_lookup_reply_TREADY),
    .m_axis_host_arp_lookup_reply_V_TDATA(arp_lookup_reply.data), //axis_host_arp_lookup_reply_TDATA),
    .s_axis_TVALID(axis_arp_slice_to_arp.tvalid),
    .s_axis_TREADY(axis_arp_slice_to_arp.tready),
    .s_axis_TDATA(axis_arp_slice_to_arp.tdata),
    .s_axis_TKEEP(axis_arp_slice_to_arp.tkeep),
    .s_axis_TLAST(axis_arp_slice_to_arp.tlast),
    .s_axis_arp_lookup_request_V_V_TVALID(axis_arp_lookup_request_r.valid),
    .s_axis_arp_lookup_request_V_V_TREADY(axis_arp_lookup_request_r.ready),
    .s_axis_arp_lookup_request_V_V_TDATA(axis_arp_lookup_request_r.data),
    .s_axis_host_arp_lookup_request_V_V_TVALID(arp_lookup_request.valid), //axis_host_arp_lookup_request_TVALID),
    .s_axis_host_arp_lookup_request_V_V_TREADY(arp_lookup_request.ready), //axis_host_arp_lookup_request_TREADY),
    .s_axis_host_arp_lookup_request_V_V_TDATA(arp_lookup_request.data), //axis_host_arp_lookup_request_TDATA),

    .myMacAddress_V(arp_mac_address),
    .myIpAddress_V(arp_ip_address),
    .regRequestCount_V(arp_request_pkg_counter),
    .regRequestCount_V_ap_vld(),
    .regReplyCount_V(arp_reply_pkg_counter),
    .regReplyCount_V_ap_vld(),

    .ap_clk(net_clk), // input aclk
    .ap_rst_n(net_aresetn_r) // input aresetn
);

// Local IP
always @(posedge net_clk) begin
    if (~net_aresetn_r) begin
        local_ip_address <= 32'hD1D4010B;
        board_number <= 0;
    end
    else begin
        if (set_ip_addr.valid) begin
            local_ip_address[7:0] <= set_ip_addr.data[31:24];
            local_ip_address[15:8] <= set_ip_addr.data[23:16];
            local_ip_address[23:16] <= set_ip_addr.data[15:8];
            local_ip_address[31:24] <= set_ip_addr.data[7:0];
        end
        if (set_board_number.valid) begin
            board_number <= set_board_number.data;
        end
    end
end

assign set_ip_addr.ready = 1'b1;
assign set_board_number.ready = 1'b1;

// Merge host and user commands
axis_interconnect_merger_256 tx_metadata_merger (
    .ACLK(net_clk),
    .ARESETN(net_aresetn_r),
    .S00_AXIS_ACLK(net_clk),
    .S00_AXIS_ARESETN(net_aresetn_r),
    .S00_AXIS_TVALID(s_axis_host_meta.valid),
    .S00_AXIS_TREADY(s_axis_host_meta.ready),
    .S00_AXIS_TDATA(s_axis_host_meta.data),
    .S01_AXIS_ACLK(net_clk),
    .S01_AXIS_ARESETN(net_aresetn_r),
    .S01_AXIS_TVALID(s_axis_card_meta.valid),
    .S01_AXIS_TREADY(s_axis_card_meta.ready),
    .S01_AXIS_TDATA(s_axis_card_meta.data),
    .M00_AXIS_ACLK(net_clk),
    .M00_AXIS_ARESETN(net_aresetn_r),
    .M00_AXIS_TVALID(axis_tx_metadata.valid),
    .M00_AXIS_TREADY(axis_tx_metadata.ready),
    .M00_AXIS_TDATA(axis_tx_metadata.data),
    .S00_ARB_REQ_SUPPRESS(1'b0), 
    .S01_ARB_REQ_SUPPRESS(1'b0) 
);

/**
 * Roce stack
 */

roce_stack inst_roce_stack(
    .net_clk(net_clk), // input aclk
    .net_aresetn(net_aresetn_r), // input aresetn

    // IPv4
    .s_axis_rx_data(axis_roce_slice_to_roce),
    .m_axis_tx_data(axis_roce_to_roce_slice),
    
    // User
    .s_axis_tx_meta(axis_tx_metadata),
    .m_axis_rx_rpc_params(m_axis_rpc_meta),
    
    // Memory
    .m_axis_mem_write_cmd(m_axis_roce_write_cmd),
    .m_axis_mem_read_cmd(m_axis_roce_read_cmd),
    .m_axis_mem_write_data(m_axis_roce_write_data),
    .s_axis_mem_read_data(s_axis_roce_read_data),

    // Control
    .s_axis_qp_interface(qp_interface),
    .s_axis_qp_conn_interface(conn_interface),
    
    //.local_ip_address_V(link_local_ipv6_address), // Use IPv6 addr
    .local_ip_address(iph_ip_address), //Use IPv4 addr

    // Debug
    .crc_drop_pkg_count_valid(regCrcDropPkgCount_valid),
    .crc_drop_pkg_count_data(regCrcDropPkgCount),
    .psn_drop_pkg_count_valid(regInvalidPsnDropCount_valid),
    .psn_drop_pkg_count_data(regInvalidPsnDropCount)
);

/**
 * Statistics
 */

/*
assign rdma_debug.roce_crc_pkg_drop_count = regCrcDropPkgCount;
assign rdma_debug.roce_psn_pkg_drop_count = regInvalidPsnDropCount;
assign rdma_debug.rx_word_counter = rx_word_counter;
assign rdma_debug.rx_pkg_counter = rx_pkg_counter;
assign rdma_debug.tx_word_counter = tx_word_counter;
assign rdma_debug.tx_pkg_counter = tx_pkg_counter;
assign rdma_debug.arp_rx_pkg_counter = arp_rx_pkg_counter;
assign rdma_debug.arp_tx_pkg_counter = arp_tx_pkg_counter;
assign rdma_debug.arp_request_pkg_counter = arp_request_pkg_counter;
assign rdma_debug.arp_reply_pkg_counter = arp_reply_pkg_counter;
assign rdma_debug.icmp_rx_pkg_counter = icmp_rx_pkg_counter;
assign rdma_debug.icmp_tx_pkg_counter = icmp_tx_pkg_counter;
assign rdma_debug.tcp_rx_pkg_counter = tcp_rx_pkg_counter;
assign rdma_debug.tcp_tx_pkg_counter = tcp_tx_pkg_counter;
assign rdma_debug.roce_rx_pkg_counter = roce_rx_pkg_counter;
assign rdma_debug.roce_tx_pkg_counter = roce_tx_pkg_counter;
assign rdma_debug.roce_data_rx_word_counter = roce_data_rx_word_counter;
assign rdma_debug.roce_data_rx_pkg_counter = roce_data_rx_pkg_counter;
assign rdma_debug.roce_data_tx_role_word_counter = roce_data_tx_role_word_counter;
assign rdma_debug.roce_data_tx_role_pkg_counter = roce_data_tx_role_pkg_counter;
assign rdma_debug.roce_data_tx_host_word_counter = roce_data_tx_host_word_counter;
assign rdma_debug.roce_data_tx_host_pkg_counter = roce_data_tx_host_pkg_counter;
assign rdma_debug.axis_stream_down = axis_stream_down;

always @(posedge net_clk) begin
    if (set_ip_addr.valid) begin
        rx_word_counter <= '0;
        rx_pkg_counter <= '0;
        tx_word_counter <= '0;
        tx_pkg_counter <= '0;

        tcp_rx_pkg_counter <= '0;
        tcp_tx_pkg_counter <= '0;

        roce_data_rx_word_counter <= '0;
        roce_data_rx_pkg_counter <= '0;
        roce_data_tx_role_word_counter <= '0;
        roce_data_tx_role_pkg_counter <= '0;
        roce_data_tx_host_word_counter <= '0;
        roce_data_tx_host_pkg_counter <= '0;
        
        arp_rx_pkg_counter <= '0;
        arp_tx_pkg_counter <= '0;
        
        udp_rx_pkg_counter <= '0;
        udp_tx_pkg_counter <= '0;

        roce_rx_pkg_counter <= '0;
        roce_tx_pkg_counter <= '0;

        axis_stream_down_counter <= '0;
        axis_stream_down <= 1'b0;      
    end

    if (s_axis_net.tready) begin
        axis_stream_down_counter <= '0;
    end
    if (s_axis_net.tvalid && ~s_axis_net.tready) begin
        axis_stream_down_counter <= axis_stream_down_counter + 1;
    end
    if (axis_stream_down_counter > 2) begin
        axis_stream_down <= 1'b1;
    end
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
    //arp
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
    //icmp
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
    //tcp
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
    //udp
    if (axis_udp_slice_to_udp.tvalid && axis_udp_slice_to_udp.tready) begin
        if (axis_udp_slice_to_udp.tlast) begin
            udp_rx_pkg_counter <= udp_rx_pkg_counter + 1;
        end
    end
    if (axis_udp_to_udp_slice.tvalid && axis_udp_to_udp_slice.tready) begin
        if (axis_udp_to_udp_slice.tlast) begin
            udp_tx_pkg_counter <= udp_tx_pkg_counter + 1;
        end
    end
    //roce
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
    //roce data
    if (m_axis_roce_write_data.tvalid && m_axis_roce_write_data.tready) begin
        roce_data_rx_word_counter <= roce_data_rx_word_counter + 1;
        if (m_axis_roce_write_data.tlast) begin
            roce_data_rx_pkg_counter <= roce_data_rx_pkg_counter + 1;
        end
    end
    if (s_axis_roce_read_data.tvalid && s_axis_roce_read_data.tready) begin
        roce_data_tx_host_word_counter <= roce_data_tx_host_word_counter + 1;
        if (s_axis_roce_read_data.tlast) begin
            roce_data_tx_host_pkg_counter <= roce_data_tx_host_pkg_counter + 1;
        end
    end
    if (s_axis_roce_role_tx_data.tvalid && s_axis_roce_role_tx_data.tready) begin
        roce_data_tx_role_word_counter <= roce_data_tx_role_word_counter + 1;
        if (s_axis_roce_role_tx_data.tlast) begin
            roce_data_tx_role_pkg_counter <= roce_data_tx_role_pkg_counter + 1;
        end
    end
end
*/

// DEBUG ila --------------------------------------------------------------------------------
/*
ila_conn inst_ila_conn (
    .clk(net_clk),
    .probe0(qp_interface.valid),
    .probe1(qp_interface.ready),
    .probe2(qp_interface.data),
    .probe3(conn_interface.valid),
    .probe4(conn_interface.ready),
    .probe5(conn_interface.data),
    .probe6(local_ip_address),
    .probe7(board_number),
    .probe8(arp_lookup_request.valid),
    .probe9(arp_lookup_request.ready),
    .probe10(arp_lookup_request.data),
    .probe11(arp_lookup_reply.valid),
    .probe12(arp_lookup_reply.ready),
    .probe13(arp_lookup_reply.data)
);
*/
/*
ila_network_stack inst_ila_network_stack (
    .clk(net_clk),
    .probe0(s_axis_net.tvalid),
    .probe1(s_axis_net.tready),
    .probe2(s_axis_net.tlast),
    .probe3(m_axis_net.tvalid),
    .probe4(m_axis_net.tready),
    .probe5(m_axis_net.tlast),
    .probe6(axis_roce_slice_to_merge.tvalid),
    .probe7(axis_roce_slice_to_merge.tready),
    .probe8(axis_roce_slice_to_merge.tlast),
    .probe9(m_axis_roce_read_cmd.valid),
    .probe10(m_axis_roce_read_cmd.ready),
    .probe11(m_axis_roce_read_cmd.req.vaddr), //48
    .probe12(m_axis_roce_read_cmd.req.len), //28
    .probe13(m_axis_roce_read_cmd.req.ctl),
    .probe14(m_axis_roce_read_cmd.req.id), //4
    .probe15(m_axis_roce_read_cmd.req.host),
    .probe16(m_axis_roce_write_cmd.valid),
    .probe17(m_axis_roce_write_cmd.ready),
    .probe18(m_axis_roce_write_cmd.req.vaddr), //48
    .probe19(m_axis_roce_write_cmd.req.len), //28
    .probe20(m_axis_roce_write_cmd.req.ctl),
    .probe21(m_axis_roce_write_cmd.req.id), //4
    .probe22(m_axis_roce_write_cmd.req.host),
    .probe23(s_axis_roce_read_data.tvalid),
    .probe24(s_axis_roce_read_data.tready),
    .probe25(s_axis_roce_read_data.tlast),
    .probe26(m_axis_roce_write_data.tvalid),
    .probe27(m_axis_roce_write_data.tready),
    .probe28(m_axis_roce_write_data.tlast),
    .probe29(axis_roce_slice_to_merge.tdata), //512
    .probe30(m_axis_rpc_meta.data), //256
    .probe31(m_axis_rpc_meta.valid),
    .probe32(m_axis_rpc_meta.ready),
    .probe33(axis_tx_metadata.valid),
    .probe34(axis_tx_metadata.ready),
    .probe35(axis_tx_metadata.data) //256
);
*/

/*
ila_network_stack_rpc inst_ila_rpc (
    .clk(net_clk),
    .probe0(m_axis_rpc_meta.valid),
    .probe1(m_axis_rpc_meta.ready),
    .probe2(m_axis_rpc_meta.data[199:192]),
    .probe3(cnt_rpc),
    .probe4(axis_tx_metadata.valid),
    .probe5(axis_tx_metadata.ready),
    .probe6(axis_tx_metadata.data[63:0]),
    .probe7(cnt_meta),
    .probe8(s_axis_roce_read_data.tvalid),
    .probe9(s_axis_roce_read_data.tready),
    .probe10(s_axis_roce_read_data.tlast)
);
*/
endmodule
