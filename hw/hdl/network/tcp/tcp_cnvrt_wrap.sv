/*
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

`include "axi_macros.svh"
`include "lynx_macros.svh"

import lynxTypes::*;
import bftTypes::*;

/**
 * User logic
 * 
 */
module tcp_cnvrt_wrap (
    // control
    input wire                  ap_clr_pulse,

    // config
    input wire [63:0]           maxPkgWord,

    // User Interface
    AXI4S.s                     netTxData,
    metaIntf.s                  netTxMeta,
    AXI4S.m                     netRxData,
    metaIntf.m                  netRxMeta,

    // TCP/IP QSFP0 CMD
    metaIntf.s			        tcp_0_notify,
    metaIntf.m			        tcp_0_rd_pkg,
    metaIntf.s			        tcp_0_rx_meta,
    metaIntf.m			        tcp_0_tx_meta,
    metaIntf.s			        tcp_0_tx_stat,

    // AXI4S TCP/IP QSFP0 STREAMS
    AXI4S.s                     axis_tcp_0_sink,
    AXI4S.m                     axis_tcp_0_src,

    // Clock and reset
    input  wire                 aclk,
    input  wire[0:0]            aresetn
);

// Moved from ports
logic [63:0]  	    consumed_bytes_network;
logic [63:0]  	    produced_bytes_network;
logic [63:0]  	    produced_pkt_network;
logic [63:0]          consumed_pkt_network;
logic [63:0]          net_device_down;
logic [63:0]          device_net_down;
logic [63:0]          net_tx_cmd_error;

// --
logic [0:0] ap_clr_pulse_reg;
logic [63:0] maxPkgWord_reg;

always @(posedge aclk) begin
	ap_clr_pulse_reg <= ap_clr_pulse;
    maxPkgWord_reg <= maxPkgWord;
end

// TCP interface
wire [127:0]tcp_notify_TDATA;
wire tcp_notify_TREADY;
wire tcp_notify_TVALID;

assign tcp_notify_TDATA[15:0] = tcp_0_notify.data.sid; //session
assign tcp_notify_TDATA[31:16] = tcp_0_notify.data.len; //length
assign tcp_notify_TDATA[63:32] = tcp_0_notify.data.ip_address; //ip_address
assign tcp_notify_TDATA[79:64] = tcp_0_notify.data.dst_port; //dst_port
assign tcp_notify_TDATA[80:80] = tcp_0_notify.data.closed; //closed
assign tcp_notify_TDATA[127:81] = 0;

assign tcp_notify_TVALID = tcp_0_notify.valid;
assign tcp_0_notify.ready = tcp_notify_TREADY;


wire [15:0]tcp_rx_meta_TDATA;
wire tcp_rx_meta_TREADY;
wire tcp_rx_meta_TVALID;

assign tcp_rx_meta_TDATA = tcp_0_rx_meta.data;

assign tcp_rx_meta_TVALID = tcp_0_rx_meta.valid;
assign tcp_0_rx_meta.ready = tcp_rx_meta_TREADY;

wire [63:0]tcp_tx_stat_TDATA;
wire tcp_tx_stat_TREADY;
wire tcp_tx_stat_TVALID;

assign tcp_tx_stat_TDATA[15:0] = tcp_0_tx_stat.data.sid;
assign tcp_tx_stat_TDATA[31:16] = tcp_0_tx_stat.data.len;
assign tcp_tx_stat_TDATA[61:32] = tcp_0_tx_stat.data.remaining_space;
assign tcp_tx_stat_TDATA[63:62] = tcp_0_tx_stat.data.error;

assign tcp_tx_stat_TVALID = tcp_0_tx_stat.valid;
assign tcp_0_tx_stat.ready = tcp_tx_stat_TREADY;

wire [31:0]tcp_tx_meta_TDATA;
wire tcp_tx_meta_TREADY;
wire tcp_tx_meta_TVALID;

assign tcp_0_tx_meta.data.sid = tcp_tx_meta_TDATA[15:0];
assign tcp_0_tx_meta.data.len = tcp_tx_meta_TDATA[31:16];

assign tcp_0_tx_meta.valid = tcp_tx_meta_TVALID;
assign tcp_tx_meta_TREADY = tcp_0_tx_meta.ready;

wire [31:0]tcp_rd_package_TDATA;
wire tcp_rd_package_TREADY;
wire tcp_rd_package_TVALID;

assign tcp_0_rd_pkg.data.sid = tcp_rd_package_TDATA[15:0];
assign tcp_0_rd_pkg.data.len = tcp_rd_package_TDATA[31:16];

assign tcp_0_rd_pkg.valid = tcp_rd_package_TVALID;
assign tcp_rd_package_TREADY = tcp_0_rd_pkg.ready;

logic [63:0] axis_tcp_0_sink_ready_down, axis_tcp_0_src_ready_down;

AXI4S #(.AXI4S_DATA_BITS(AXI_DATA_BITS)) axis_tcp_0_sink_reg();

axis_reg_array #(.N_STAGES(4), .DATA_BITS(AXI_DATA_BITS)) 
inst_axis_tcp_0_sink_reg_array 
(
    .aclk(aclk), 
    .aresetn(aresetn), 
    .reset(ap_clr_pulse_reg),
    .s_axis(axis_tcp_0_sink), 
    .m_axis(axis_tcp_0_sink_reg), 
    .byte_cnt(consumed_bytes_network), 
    .pkt_cnt(consumed_pkt_network), 
    .ready_down(axis_tcp_0_sink_ready_down)
);

assign net_device_down = axis_tcp_0_sink_ready_down;

AXI4S #(.AXI4S_DATA_BITS(AXI_DATA_BITS)) axis_tcp_0_src_reg();

axis_reg_array #(.N_STAGES(4), .DATA_BITS(AXI_DATA_BITS)) 
inst_axis_tcp_0_src_reg_array 
(
    .aclk(aclk), 
    .aresetn(aresetn), 
    .reset(ap_clr_pulse_reg),
    .s_axis(axis_tcp_0_src_reg), 
    .m_axis(axis_tcp_0_src), 
    .byte_cnt(produced_bytes_network), 
    .pkt_cnt(produced_pkt_network), 
    .ready_down(axis_tcp_0_src_ready_down)
);

assign device_net_down = axis_tcp_0_src_ready_down;

tcp_intf_wrapper tcp_intf_wrapper
   (
    .ap_clk(aclk),
    .ap_rst_n(aresetn),
    .axis_tcp_sink_tdata(axis_tcp_0_sink_reg.tdata),
    .axis_tcp_sink_tkeep(axis_tcp_0_sink_reg.tkeep),
    .axis_tcp_sink_tlast(axis_tcp_0_sink_reg.tlast),
    .axis_tcp_sink_tready(axis_tcp_0_sink_reg.tready),
    .axis_tcp_sink_tstrb(0),
    .axis_tcp_sink_tvalid(axis_tcp_0_sink_reg.tvalid),
    .axis_tcp_src_tdata(axis_tcp_0_src_reg.tdata),
    .axis_tcp_src_tkeep(axis_tcp_0_src_reg.tkeep),
    .axis_tcp_src_tlast(axis_tcp_0_src_reg.tlast),
    .axis_tcp_src_tready(axis_tcp_0_src_reg.tready),
    .axis_tcp_src_tstrb(),
    .axis_tcp_src_tvalid(axis_tcp_0_src_reg.tvalid),
    .rx_data_tdata(netRxData.tdata),
    .rx_data_tkeep(netRxData.tkeep),
    .rx_data_tlast(netRxData.tlast),
    .rx_data_tready(netRxData.tready),
    .rx_data_tstrb(),
    .rx_data_tvalid(netRxData.tvalid),
    .rx_meta_tdata(netRxMeta.data),
    .rx_meta_tready(netRxMeta.ready),
    .rx_meta_tvalid(netRxMeta.valid),
    .tcp_notify_tdata(tcp_notify_TDATA),
    .tcp_notify_tready(tcp_notify_TREADY),
    .tcp_notify_tvalid(tcp_notify_TVALID),
    .tcp_rd_package_tdata(tcp_rd_package_TDATA),
    .tcp_rd_package_tready(tcp_rd_package_TREADY),
    .tcp_rd_package_tvalid(tcp_rd_package_TVALID),
    .tcp_rx_meta_tdata(tcp_rx_meta_TDATA),
    .tcp_rx_meta_tready(tcp_rx_meta_TREADY),
    .tcp_rx_meta_tvalid(tcp_rx_meta_TVALID),
    .tx_meta_tdata(netTxMeta.data),
    .tx_meta_tready(netTxMeta.ready),
    .tx_meta_tvalid(netTxMeta.valid),
    .tcp_tx_meta_tdata(tcp_tx_meta_TDATA),
    .tcp_tx_meta_tready(tcp_tx_meta_TREADY),
    .tcp_tx_meta_tvalid(tcp_tx_meta_TVALID),
    .tcp_tx_stat_tdata(tcp_tx_stat_TDATA),
    .tcp_tx_stat_tready(tcp_tx_stat_TREADY),
    .tcp_tx_stat_tvalid(tcp_tx_stat_TVALID),
    .tx_data_tdata(netTxData.tdata),
    .tx_data_tkeep(netTxData.tkeep),
    .tx_data_tlast(netTxData.tlast),
    .tx_data_tready(netTxData.tready),
    .tx_data_tstrb(0),
    .tx_data_tvalid(netTxData.tvalid),
    .maxPkgWord (maxPkgWord_reg)
);

logic [63:0] tx_status_error_cnt;
logic [63:0] execution_cycles;

always @( posedge aclk ) begin 
	if (~aresetn) begin
		tx_status_error_cnt <= '0;
        execution_cycles <= '0;
	end
	else begin
		if (ap_clr_pulse) begin
			tx_status_error_cnt <= '0;
            execution_cycles <= '0;
		end
		else begin
            execution_cycles <= execution_cycles + 1'b1;

            if (tcp_0_tx_stat.valid & tcp_0_tx_stat.ready & tcp_0_tx_stat.data.error != 0) begin
                tx_status_error_cnt <= tx_status_error_cnt + 1'b1;
            end

		end
	end
end

assign net_tx_cmd_error = tx_status_error_cnt;

endmodule