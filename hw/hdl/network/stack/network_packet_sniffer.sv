/**
  * Copyright (c) 2024, Systems Group, ETH Zurich
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
 * @brief   Packet Filter
 *
 * Filter and select packets basing on given configuration
 */
module packet_filter (
    /* Network stream */
    AXI4S.s                     rx_axis_net, // RX
    AXI4S.s                     tx_axis_net, // TX
    AXI4S.m                     rx_pass_axis_net, // RX pass-through
    AXI4S.m                     tx_pass_axis_net, // TX pass-through

    /* Filtered stream */
    AXI4S.m                     rx_filtered_axis,
    AXI4S.m                     tx_filtered_axis,

    /* Filter configuration */
    input wire [63:0]           local_filter_config,
    // Bit 00-07: reserved
    // Bit 08: ignore all ipv4
    // Bit 09: ignore all ipv6
    // Bit 10-15: reserved
    // Bit 16: ignore arp
    // Bit 17: reserved
    // Bit 18: ignore icmp(ipv4)
    // Bit 19: reserved
    // Bit 20: ignore icmp(ipv6)
    // Bit 21: reserved
    // Bit 22: ignore udp(ipv4)
    // Bit 23: ignore udp(ipv4) data field & checksum
    // Bit 24: ignore udp(ipv6)
    // Bit 25: ignore udp(ipv6) data field & checksum
    // Bit 26: ignore tcp(ipv4)
    // Bit 27: ignore tcp(ipv4) data field & checksum
    // Bit 28-29: reserved
    // Bit 30: ignore roce(ipv4)
    // Bit 31: ignore roce(ipv4) data field & checksum
    // Bit 32-63: reserved

    input  wire                 nclk,
    input  wire                 nresetn_r
);

/**
 * Stream Pass-Through
 */
// RX
assign rx_axis_net.tready = rx_pass_axis_net.tready & rx_filtered_axis.tready;
assign rx_pass_axis_net.tvalid = rx_axis_net.tready & rx_axis_net.tvalid;
assign rx_pass_axis_net.tdata = rx_axis_net.tdata;
assign rx_pass_axis_net.tkeep = rx_axis_net.tkeep;
assign rx_pass_axis_net.tlast = rx_axis_net.tlast;
// TX
assign tx_axis_net.tready = tx_pass_axis_net.tready & tx_filtered_axis.tready;
assign tx_pass_axis_net.tvalid = tx_axis_net.tready & tx_axis_net.tvalid;
assign tx_pass_axis_net.tdata = tx_axis_net.tdata;
assign tx_pass_axis_net.tkeep = tx_axis_net.tkeep;
assign tx_pass_axis_net.tlast = tx_axis_net.tlast;

/**
 * Filter Flags
 */

// RX
logic rx_ipv4, rx_ipv6;
logic [5:0] rx_ip_header_len;
logic rx_arp;
logic rx_icmp_ipv4, rx_icmp_ipv6;
logic rx_udp_ipv4, rx_udp_ipv6;
logic rx_tcp_ipv4;
logic rx_rocev2_ipv4;
logic rx_rocev2_ipv4_aeth, rx_rocev2_ipv4_reth;

// TX
logic tx_ipv4, tx_ipv6;
logic [5:0] tx_ip_header_len;
logic tx_arp;
logic tx_icmp_ipv4, tx_icmp_ipv6;
logic tx_udp_ipv4, tx_udp_ipv6;
logic tx_tcp_ipv4;
logic tx_rocev2_ipv4;
logic tx_rocev2_ipv4_aeth, tx_rocev2_ipv4_reth;

// Flags for state machine
reg   rx_in_pkt_not_first, tx_in_pkt_not_first;
logic rx_in_pkt_first,     tx_in_pkt_first;
// logic rx_in_pkt_last,      tx_in_pkt_last;
assign rx_in_pkt_first = ~rx_in_pkt_not_first & rx_axis_net.tvalid & rx_axis_net.tready;
assign tx_in_pkt_first = ~tx_in_pkt_not_first & tx_axis_net.tvalid & tx_axis_net.tready;
// assign rx_in_pkt_last  = rx_axis_net.tlast & rx_axis_net.tvalid & rx_axis_net.tready;
// assign tx_in_pkt_last  = tx_axis_net.tlast & tx_axis_net.tvalid & tx_axis_net.tready;
always @(posedge nclk) begin
    if (~nresetn_r) begin
        rx_in_pkt_not_first <= 1'b0;
        tx_in_pkt_not_first <= 1'b0;
    end else begin
        if (rx_axis_net.tvalid & rx_axis_net.tready) begin
            if (rx_axis_net.tlast) begin
                rx_in_pkt_not_first <= 1'b0;
            end else begin
                rx_in_pkt_not_first <= 1'b1;
            end
        end
        if (tx_axis_net.tvalid & tx_axis_net.tready) begin
            if (tx_axis_net.tlast) begin
                tx_in_pkt_not_first <= 1'b0;
            end else begin
                tx_in_pkt_not_first <= 1'b1;
            end
        end
    end
end

always_comb begin
    // Variable IPv4 header length is not supported!
    // Protocol deetection for packets with non-20-bytes header might fail

    // RX
    rx_ipv4             = {rx_axis_net.tdata[12*8+7:12*8], rx_axis_net.tdata[13*8+7:13*8]} == 16'h0800;
    rx_ipv6             = {rx_axis_net.tdata[12*8+7:12*8], rx_axis_net.tdata[13*8+7:13*8]} == 16'h86dd;
    // rx_ip_header_len    = rx_ipv4 ? {rx_axis_net.tdata[14*8+3:14*8], 2'b00} : (rx_ipv6 ? 6'd40 : 6'b0);
    rx_ip_header_len    = rx_ipv4 ? 6'd20 : (rx_ipv6 ? 6'd40 : 6'b0);
    rx_arp              = {rx_axis_net.tdata[12*8+7:12*8], rx_axis_net.tdata[13*8+7:13*8]} == 16'h0806;
    rx_icmp_ipv4        = rx_ipv4 & rx_axis_net.tdata[23*8+7:23*8] == 8'h01;
    rx_icmp_ipv6        = rx_ipv6 & rx_axis_net.tdata[20*8+7:20*8] == 8'h3a;
    rx_udp_ipv4         = rx_ipv4 & rx_axis_net.tdata[23*8+7:23*8] == 8'h11;
    rx_udp_ipv6         = rx_ipv6 & rx_axis_net.tdata[20*8+7:20*8] == 8'h11;
    rx_tcp_ipv4         = rx_ipv4 & rx_axis_net.tdata[23*8+7:23*8] == 8'h06;
    // rx_rocev2_ipv4      = rx_udp_ipv4 & {rx_axis_net.tdata[(16+rx_ip_header_len)*8+7:(16+rx_ip_header_len)*8], rx_axis_net.tdata[(17+rx_ip_header_len)*8+7:(17+rx_ip_header_len)*8]} == 16'hb712;
    rx_rocev2_ipv4      = rx_udp_ipv4 & {rx_axis_net.tdata[36*8+7:36*8], rx_axis_net.tdata[37*8+7:37*8]} == 16'hb712;
    rx_rocev2_ipv4_aeth = rx_axis_net.tdata[42*8+7:42*8] == 8'h10 | rx_axis_net.tdata[42*8+7:42*8] == 8'h0d | rx_axis_net.tdata[42*8+7:42*8] == 8'h0f | rx_axis_net.tdata[42*8+7:42*8] == 8'h11; // OP = RC_READ_RESP_(ONLY/FIRST/LAST), RC_ACK
    rx_rocev2_ipv4_reth = rx_axis_net.tdata[42*8+7:42*8] == 8'h0a | rx_axis_net.tdata[42*8+7:42*8] == 8'h06 | rx_axis_net.tdata[42*8+7:42*8] == 8'h0b | rx_axis_net.tdata[42*8+7:42*8] == 8'h0c; // OP = RC_WRITE_(ONLY/FIRST), RC_WRITE_ONLY_WITH_IMM, RC_READ_REQUEST

    // TX
    tx_ipv4             = {tx_axis_net.tdata[12*8+7:12*8], tx_axis_net.tdata[13*8+7:13*8]} == 16'h0800;
    tx_ipv6             = {tx_axis_net.tdata[12*8+7:12*8], tx_axis_net.tdata[13*8+7:13*8]} == 16'h86dd;
    // tx_ip_header_len    = tx_ipv4 ? {tx_axis_net.tdata[14*8+3:14*8], 2'b00} : (tx_ipv6 ? 6'd40 : 6'b0);
    tx_ip_header_len    = tx_ipv4 ? 6'd20 : (tx_ipv6 ? 6'd40 : 6'b0);
    tx_arp              = {tx_axis_net.tdata[12*8+7:12*8], tx_axis_net.tdata[13*8+7:13*8]} == 16'h0806;
    tx_icmp_ipv4        = tx_ipv4 & tx_axis_net.tdata[23*8+7:23*8] == 8'h01;
    tx_icmp_ipv6        = tx_ipv6 & tx_axis_net.tdata[20*8+7:20*8] == 8'h3a;
    tx_udp_ipv4         = tx_ipv4 & tx_axis_net.tdata[23*8+7:23*8] == 8'h11;
    tx_udp_ipv6         = tx_ipv6 & tx_axis_net.tdata[20*8+7:20*8] == 8'h11;
    tx_tcp_ipv4         = tx_ipv4 & tx_axis_net.tdata[23*8+7:23*8] == 8'h06;
    // tx_rocev2_ipv4      = tx_udp_ipv4 & {tx_axis_net.tdata[(16+rx_ip_header_len)*8+7:(16+rx_ip_header_len)*8], tx_axis_net.tdata[(17+rx_ip_header_len)*8+7:(17+rx_ip_header_len)*8]} == 16'hb712;
    tx_rocev2_ipv4      = tx_udp_ipv4 & {tx_axis_net.tdata[36*8+7:36*8], tx_axis_net.tdata[37*8+7:37*8]} == 16'hb712;
    tx_rocev2_ipv4_aeth = tx_axis_net.tdata[42*8+7:42*8] == 8'h10 | tx_axis_net.tdata[42*8+7:42*8] == 8'h0d | tx_axis_net.tdata[42*8+7:42*8] == 8'h0f | tx_axis_net.tdata[42*8+7:42*8] == 8'h11; // OP = RC_READ_RESP_(ONLY/FIRST/LAST), RC_ACK
    tx_rocev2_ipv4_reth = tx_axis_net.tdata[42*8+7:42*8] == 8'h0a | tx_axis_net.tdata[42*8+7:42*8] == 8'h06 | tx_axis_net.tdata[42*8+7:42*8] == 8'h0b | tx_axis_net.tdata[42*8+7:42*8] == 8'h0c; // OP = RC_WRITE_(ONLY/FIRST), RC_WRITE_ONLY_WITH_IMM, RC_READ_REQUEST
end

reg          rx_filter_dropped;
logic        rx_filter_dropping;
reg   [63:0] rx_header_remain;
logic [63:0] rx_header_remain_next;
reg          tx_filter_dropped;
logic        tx_filter_dropping;
reg   [63:0] tx_header_remain;
logic [63:0] tx_header_remain_next;
always @(posedge nclk) begin
    if (~nresetn_r) begin
        rx_filter_dropped <= 1'b0;
        rx_header_remain  <= 64'b0;
        tx_filter_dropped <= 1'b0;
        tx_header_remain  <= 64'b0;
    end else begin
        if (rx_axis_net.tvalid & rx_axis_net.tready) begin
            rx_header_remain <= rx_header_remain_next;
            if (rx_axis_net.tlast) begin
                rx_filter_dropped <= 1'b0;
            end else if (rx_filter_dropping) begin
                rx_filter_dropped <= rx_filter_dropping;
            end
        end
        if (tx_axis_net.tvalid & tx_axis_net.tready) begin
            tx_header_remain <= tx_header_remain_next;
            if (tx_axis_net.tlast) begin
                tx_filter_dropped <= 1'b0;
            end else if (tx_filter_dropping) begin
                tx_filter_dropped <= tx_filter_dropping;
            end
        end
    end
end

assign rx_filtered_axis.tdata = rx_axis_net.tdata;
assign tx_filtered_axis.tdata = tx_axis_net.tdata;
always_comb begin
    // RX
    rx_filtered_axis.tvalid = rx_axis_net.tvalid;
    rx_filtered_axis.tkeep  = rx_axis_net.tkeep;
    rx_filtered_axis.tlast  = rx_axis_net.tlast;
    rx_filter_dropping      = 1'b0;
    rx_header_remain_next   = 64'b0;
    // drop all logic
    if ((rx_in_pkt_first &&
            ((rx_ipv4 & local_filter_config[8])      ||
            (rx_ipv6 & local_filter_config[9])       ||
            (rx_arp & local_filter_config[16])       ||
            (rx_icmp_ipv4 & local_filter_config[18]) ||
            (rx_icmp_ipv6 & local_filter_config[20]) ||
            (rx_udp_ipv4 & local_filter_config[22])  ||
            (rx_udp_ipv6 & local_filter_config[24])  ||
            (rx_tcp_ipv4 & local_filter_config[26])  || 
            (rx_rocev2_ipv4 & local_filter_config[30]))) ||
        (rx_in_pkt_not_first &&
            (rx_filter_dropped))
    ) begin
        rx_filtered_axis.tvalid = 1'b0;
        rx_filtered_axis.tkeep  = 64'b0;
        rx_filtered_axis.tlast  = 1'b0;
        rx_filter_dropping      = 1'b1;
    // select header logic
    end else if (rx_in_pkt_first) begin
        if (rx_udp_ipv4 & local_filter_config[23]) begin
            // 14 (eth header) + 20 (ipv4 header) + 8 (udp header) = 42B
            rx_filtered_axis.tkeep  = 64'h0000_03ff_ffff_ffff;
            rx_filtered_axis.tlast  = 1'b1;
            rx_filter_dropping      = 1'b1;
        end else if (rx_udp_ipv6 & local_filter_config[25]) begin
            // 14 (eth header) + 40 (ipv4 header) + 8 (udp header) = 62B
            rx_filtered_axis.tkeep  = 64'h3fff_ffff_ffff_ffff;
            rx_filtered_axis.tlast  = 1'b1;
            rx_filter_dropping      = 1'b1;
        end else if (rx_tcp_ipv4 & local_filter_config[27]) begin
            // 14 (eth header) + 20 (ipv4 header) + 20 (tcp header) = 54B
            // note: TCP Options will also be ignored
            rx_filtered_axis.tkeep  = 64'h003f_ffff_ffff_ffff;
            rx_filtered_axis.tlast  = 1'b1;
            rx_filter_dropping      = 1'b1;
        end else if (rx_rocev2_ipv4 & local_filter_config[31]) begin
            // 14 (eth header) + 20 (ipv4 header) + 8 (udp header) + 12 (rocev2 bth) = 54B
            // additional header?
            if (tx_rocev2_ipv4_aeth) begin
                // 54 + 4 = 58B
                rx_filtered_axis.tkeep  = 64'h03ff_ffff_ffff_ffff;
                rx_filtered_axis.tlast  = 1'b1;
                rx_filter_dropping      = 1'b1;
            end else if (tx_rocev2_ipv4_reth) begin
                // 54 + 16 = 70B
                rx_header_remain_next   = 64'h0000_0000_0000_003f;
            end else begin
                // 54B
                rx_filtered_axis.tkeep  = 64'h003f_ffff_ffff_ffff;
                rx_filtered_axis.tlast  = 1'b1;
                rx_filter_dropping      = 1'b1;
            end
        end
    // long header (64 < len <= 128) logic
    end else if (rx_header_remain > 64'b0 && rx_axis_net.tvalid && rx_axis_net.tready) begin
        rx_header_remain_next   = 64'b0;
        rx_filtered_axis.tkeep  = rx_header_remain;
        rx_filtered_axis.tlast  = 1'b1;
        rx_filter_dropping      = 1'b1;
    end

    // TX
    tx_filtered_axis.tvalid = tx_axis_net.tvalid;
    tx_filtered_axis.tkeep  = tx_axis_net.tkeep;
    tx_filtered_axis.tlast  = tx_axis_net.tlast;
    tx_filter_dropping      = 1'b0;
    tx_header_remain_next   = 64'b0;
    // drop all logic
    if ((tx_in_pkt_first &&
            ((tx_ipv4 & local_filter_config[8])      ||
            (tx_ipv6 & local_filter_config[9])       ||
            (tx_arp & local_filter_config[16])       ||
            (tx_icmp_ipv4 & local_filter_config[18]) ||
            (tx_icmp_ipv6 & local_filter_config[20]) ||
            (tx_udp_ipv4 & local_filter_config[22])  ||
            (tx_udp_ipv6 & local_filter_config[24])  ||
            (tx_tcp_ipv4 & local_filter_config[26])  || 
            (tx_rocev2_ipv4 & local_filter_config[30]))) ||
        (tx_in_pkt_not_first &&
            (tx_filter_dropped))
    ) begin
        tx_filtered_axis.tvalid = 1'b0;
        tx_filtered_axis.tkeep  = 64'b0;
        tx_filtered_axis.tlast  = 1'b0;
        tx_filter_dropping      = 1'b1;
    // select header logic
    end else if (tx_in_pkt_first) begin
        if (tx_udp_ipv4 & local_filter_config[23]) begin
            // 14 (eth header) + 20 (ipv4 header) + 8 (udp header) = 42B
            tx_filtered_axis.tkeep  = 64'h0000_03ff_ffff_ffff;
            tx_filtered_axis.tlast  = 1'b1;
            tx_filter_dropping      = 1'b1;
        end else if (tx_udp_ipv6 & local_filter_config[25]) begin
            // 14 (eth header) + 40 (ipv4 header) + 8 (udp header) = 62B
            tx_filtered_axis.tkeep  = 64'h3fff_ffff_ffff_ffff;
            tx_filtered_axis.tlast  = 1'b1;
            tx_filter_dropping      = 1'b1;
        end else if (tx_tcp_ipv4 & local_filter_config[27]) begin
            // 14 (eth header) + 20 (ipv4 header) + 20 (tcp header) = 54B
            // note: TCP Options will also be ignored
            tx_filtered_axis.tkeep  = 64'h003f_ffff_ffff_ffff;
            tx_filtered_axis.tlast  = 1'b1;
            tx_filter_dropping      = 1'b1;
        end else if (tx_rocev2_ipv4 & local_filter_config[31]) begin
            // 14 (eth header) + 20 (ipv4 header) + 8 (udp header) + 12 (rocev2 bth) = 54B
            // additional header?
            if (tx_rocev2_ipv4_aeth) begin
                // 54 + 4 = 58B
                tx_filtered_axis.tkeep  = 64'h03ff_ffff_ffff_ffff;
                tx_filtered_axis.tlast  = 1'b1;
                tx_filter_dropping      = 1'b1;
            end else if (tx_rocev2_ipv4_reth) begin
                // 54 + 16 = 70B
                tx_header_remain_next   = 64'h0000_0000_0000_003f;
            end else begin
                // 54B
                tx_filtered_axis.tkeep  = 64'h003f_ffff_ffff_ffff;
                tx_filtered_axis.tlast  = 1'b1;
                tx_filter_dropping      = 1'b1;
            end
        end
    // long header (64 < len <= 128) logic
    end else if (tx_header_remain > 64'b0 && tx_axis_net.tvalid && tx_axis_net.tready) begin
        tx_header_remain_next   = 64'b0;
        tx_filtered_axis.tkeep  = tx_header_remain;
        tx_filtered_axis.tlast  = 1'b1;
        tx_filter_dropping      = 1'b1;
    end
end

endmodule


// /**
//  * @brief   Timestamp Inserter
//  *
//  * Insert timestamp into packets
//  */
// module timestamp_inserter (
//     // TODO
// );
//     // TODO
// endmodule


/**
 * @brief   Packet Sniffer
 *
 * Capture packets on RX and TX, filter, insert timestamp, and merge results into one stream
 */
module packet_sniffer (
    /* Network stream */
    AXI4S.s                     rx_axis_net, // RX
    AXI4S.s                     tx_axis_net, // TX
    AXI4S.m                     rx_pass_axis_net, // RX pass-through
    AXI4S.m                     tx_pass_axis_net, // TX pass-through
    
    // subject to future changes
    /* Filtered stream */
    AXI4S.m                     rx_filtered_axis,
    AXI4S.m                     tx_filtered_axis,
    /* Filter configuration */
    metaIntf.s                  filter_config,

    input  wire                 nclk,
    input  wire                 nresetn_r
);

AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) rx_filter_before_slice();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) tx_filter_before_slice();
axis_reg_array inst_slice_rx_filter (.aclk(nclk), .aresetn(nresetn_r), .s_axis(rx_filter_before_slice), .m_axis(rx_filtered_axis));
axis_reg_array inst_slice_tx_filter (.aclk(nclk), .aresetn(nresetn_r), .s_axis(tx_filter_before_slice), .m_axis(tx_filtered_axis));

assign filter_config.ready = 1'b1;
reg [63:0] filter_config_r;
always @(posedge nclk) begin
    if (~nresetn_r) begin
        filter_config_r <= 0;
    end else begin
        if (filter_config.valid && filter_config.ready) begin
            filter_config_r <= filter_config.data;
        end
    end
end

packet_filter packet_filter_inst (
    .rx_axis_net(rx_axis_net),
    .tx_axis_net(tx_axis_net),
    .rx_pass_axis_net(rx_pass_axis_net),
    .tx_pass_axis_net(tx_pass_axis_net),
    .rx_filtered_axis(rx_filter_before_slice),
    .tx_filtered_axis(tx_filter_before_slice),
    .local_filter_config(filter_config_r),
    .nclk(nclk),
    .nresetn_r(nresetn_r)
);

endmodule
