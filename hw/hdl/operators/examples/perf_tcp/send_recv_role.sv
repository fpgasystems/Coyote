/*
 * Copyright (c) 2019, Systems Group, ETH Zurich
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
`default_nettype none

import lynxTypes::*;

module send_recv_role 
  #( 
  parameter integer  C_S_AXI_CONTROL_DATA_WIDTH = 32,
  parameter integer  C_S_AXI_CONTROL_ADDR_WIDTH = 12,
  parameter integer  NETWORK_STACK_WIDTH=512
)
(
    input wire      ap_clk,
    input wire      ap_rst_n,

    AXI4L.s                                       axi_ctrl,

    /* NETWORK  - TCP/IP INTERFACE */
    //Network TCP/IP

    input wire                                     s_axis_tcp_notification_tvalid ,
    output  wire                                   s_axis_tcp_notification_tready ,
    input wire [88-1:0]                            s_axis_tcp_notification_tdata  ,

    output  wire                                   m_axis_tcp_read_pkg_tvalid ,
    input wire                                     m_axis_tcp_read_pkg_tready ,
    output  wire [32-1:0]                          m_axis_tcp_read_pkg_tdata  ,

    input wire                                     s_axis_tcp_rx_meta_tvalid ,
    output  wire                                   s_axis_tcp_rx_meta_tready ,
    input wire [16-1:0]                            s_axis_tcp_rx_meta_tdata  ,

    input wire                                     s_axis_tcp_rx_data_tvalid ,
    output  wire                                   s_axis_tcp_rx_data_tready ,
    input wire [NETWORK_STACK_WIDTH-1:0]           s_axis_tcp_rx_data_tdata  ,
    input wire [NETWORK_STACK_WIDTH/8-1:0]         s_axis_tcp_rx_data_tkeep  ,
    input wire                                     s_axis_tcp_rx_data_tlast  ,

    output  wire                                   m_axis_tcp_tx_meta_tvalid ,
    input wire                                     m_axis_tcp_tx_meta_tready ,
    output  wire [32-1:0]                          m_axis_tcp_tx_meta_tdata  ,

    output  wire                                   m_axis_tcp_tx_data_tvalid ,
    input wire                                     m_axis_tcp_tx_data_tready ,
    output  wire [NETWORK_STACK_WIDTH-1:0]         m_axis_tcp_tx_data_tdata  ,
    output  wire [NETWORK_STACK_WIDTH/8-1:0]       m_axis_tcp_tx_data_tkeep  ,
    output  wire                                   m_axis_tcp_tx_data_tlast  ,

    input wire                                     s_axis_tcp_tx_status_tvalid ,
    output  wire                                   s_axis_tcp_tx_status_tready ,
    input wire [64-1:0]                            s_axis_tcp_tx_status_tdata  
    


);

wire ap_start, ap_done, ap_ready, ap_idle, interrupt;
wire [63:0] axi00_ptr0;
logic ap_start_pulse;
logic ap_start_r = 1'b0;
logic ap_idle_r = 1'b1;

logic       runExperiment;
logic       finishExperiment;
logic 		runTx, sentRunTx;

// create pulse when ap_start transitions to 1
always @(posedge ap_clk) begin
	begin
		ap_start_r <= ap_start;
	end
end

assign ap_start_pulse = ap_start & ~ap_start_r;
assign runExperiment = ap_start_pulse;

// ap_idle is asserted when done is asserted, it is de-asserted when ap_start_pulse
// is asserted
always @(posedge ap_clk) begin
	if (~ap_rst_n) begin
		ap_idle_r <= 1'b1;
	end
	else begin
		ap_idle_r <= ap_done ? 1'b1 :
		ap_start_pulse ? 1'b0 : ap_idle;
	end
end

assign ap_idle = ap_idle_r;

// Done logic

assign ap_done = finishExperiment;

// Ready Logic (non-pipelined case)
assign ap_ready = ap_done;


/*
 * TCP/IP Benchmark
 */



logic[63:0] execution_cycles;
logic running;

wire [31:0] useConn, useIpAddr, pkgWordCount, basePort ,baseIpAddress;

logic[31:0] timeInSeconds, transferSize, isServer;
logic[63:0] timeInCycles;

logic [15:0] useIpAddrReg;
logic [15:0] useConnReg;
logic [15:0] basePortReg;
logic [15:0] pkgWordCountReg;
logic [31:0] baseIpAddressReg;

reg[63:0] consumed_bytes;
reg[63:0] produced_bytes;

reg [47:0] rdRqstByteCnt;
reg [31:0] rcvPktCnt;

reg [31:0] tx_meta_down;
reg [31:0] tx_status_down;
reg [31:0] tx_data_down;

logic [15:0] sessionID, sessionIDReg, cnfg_sessionID;


always @ (posedge ap_clk) begin
	if (~ap_rst_n) begin
		baseIpAddressReg <= '0;
		basePortReg <= '0;
		pkgWordCountReg <= '0;
		useIpAddrReg <= '0;
		useConnReg <= '0;
		sessionIDReg <= '0;
	end
	else begin
		baseIpAddressReg <= baseIpAddress ;
		basePortReg <= basePort ;
		pkgWordCountReg <= pkgWordCount;
		useIpAddrReg <= useIpAddr;
		useConnReg <= useConn ;
		sessionIDReg <= sessionID;
	end

end

always @(posedge ap_clk) begin
	if (~ap_rst_n) begin
		running <= 1'b0;
		finishExperiment <= 1'b0;
		rdRqstByteCnt <= '0;
		rcvPktCnt <= '0;
		tx_meta_down <= '0;
		tx_data_down <= '0;
		tx_status_down <= '0;
		runTx <= 1'b0;
		sentRunTx <= 1'b0;
		sessionID <= 0;
	end
	else begin
		if (runExperiment) begin
			finishExperiment <= 1'b0;
			running <= 1'b1;
			execution_cycles <= '0;
			rdRqstByteCnt <= '0;
			rcvPktCnt <= '0;
			tx_meta_down <= '0;
			tx_data_down <= '0;
			tx_status_down <= '0;
			runTx <= 1'b0;
			sentRunTx <= 1'b0;
			sessionID <= 0;
		end

		if (isServer) begin
			if (s_axis_tcp_rx_meta_tvalid & s_axis_tcp_rx_meta_tready) begin
				sessionID <= s_axis_tcp_rx_meta_tdata;
			end
		end
		else if (!isServer) begin
			sessionID <= cnfg_sessionID;
		end

		// if server node, run tx when receive expected amount of bytes
		if (running) begin
			if (isServer) begin
				runTx <= (consumed_bytes >= transferSize) & !sentRunTx;
			end
		// if not server node, run tx when not sent runTx
			else begin
				runTx <= !sentRunTx;
			end
		end

		if (runTx) begin
			sentRunTx <= 1'b1;
		end

		if (running) begin
			execution_cycles <= execution_cycles + 1;
		end

		if ( running & (consumed_bytes >= transferSize) & (produced_bytes >= transferSize) ) begin
			running <= 1'b0;
			finishExperiment <= 1'b1;
		end
		
		if (m_axis_tcp_read_pkg_tvalid & m_axis_tcp_read_pkg_tready) begin
			rdRqstByteCnt <= rdRqstByteCnt + m_axis_tcp_read_pkg_tdata[31:16];
		end

		if (s_axis_tcp_rx_data_tvalid & s_axis_tcp_rx_data_tready & s_axis_tcp_rx_data_tlast) begin
			rcvPktCnt <= rcvPktCnt + 1'b1;
		end

		if (m_axis_tcp_tx_meta_tvalid & ~m_axis_tcp_tx_meta_tready) begin
			tx_meta_down <= tx_meta_down + 1'b1;
		end

		if (s_axis_tcp_tx_status_tvalid & ~s_axis_tcp_tx_status_tready) begin
			tx_status_down <= tx_status_down + 1'b1;
		end

		if (m_axis_tcp_tx_data_tvalid & ~m_axis_tcp_tx_data_tready) begin
			tx_data_down <= tx_data_down + 1'b1;
		end

	end
end

`ifdef VITIS_HLS
send_recv_ip send_recv (
	.m_axis_read_package_TVALID(m_axis_tcp_read_pkg_tvalid),              // output wire m_axis_read_package_TVALID
	.m_axis_read_package_TREADY(m_axis_tcp_read_pkg_tready),              // input wire m_axis_read_package_TREADY
	.m_axis_read_package_TDATA(m_axis_tcp_read_pkg_tdata),                // output wire [31 : 0] m_axis_read_package_TDATA
	.m_axis_tx_data_TVALID(m_axis_tcp_tx_data_tvalid),                        // output wire m_axis_tx_data_TVALID
	.m_axis_tx_data_TREADY(m_axis_tcp_tx_data_tready),                        // input wire m_axis_tx_data_TREADY
	.m_axis_tx_data_TDATA(m_axis_tcp_tx_data_tdata),                          // output wire [63 : 0] m_axis_tx_data_TDATA
	.m_axis_tx_data_TKEEP(m_axis_tcp_tx_data_tkeep),                          // output wire [7 : 0] m_axis_tx_data_TKEEP
	.m_axis_tx_data_TLAST(m_axis_tcp_tx_data_tlast),                          // output wire [0 : 0] m_axis_tx_data_TLAST
	.m_axis_tx_metadata_TVALID(m_axis_tcp_tx_meta_tvalid),                // output wire m_axis_tx_metadata_TVALID
	.m_axis_tx_metadata_TREADY(m_axis_tcp_tx_meta_tready),                // input wire m_axis_tx_metadata_TREADY
	.m_axis_tx_metadata_TDATA(m_axis_tcp_tx_meta_tdata),                  // output wire [15 : 0] m_axis_tx_metadata_TDATA
	.s_axis_notifications_TVALID(s_axis_tcp_notification_tvalid),            // input wire s_axis_notifications_TVALID
	.s_axis_notifications_TREADY(s_axis_tcp_notification_tready),            // output wire s_axis_notifications_TREADY
	.s_axis_notifications_TDATA(s_axis_tcp_notification_tdata),              // input wire [87 : 0] s_axis_notifications_TDATA
	.s_axis_rx_data_TVALID(s_axis_tcp_rx_data_tvalid),                        // input wire s_axis_rx_data_TVALID
	.s_axis_rx_data_TREADY(s_axis_tcp_rx_data_tready),                        // output wire s_axis_rx_data_TREADY
	.s_axis_rx_data_TDATA(s_axis_tcp_rx_data_tdata),                          // input wire [63 : 0] s_axis_rx_data_TDATA
	.s_axis_rx_data_TKEEP(s_axis_tcp_rx_data_tkeep),                          // input wire [7 : 0] s_axis_rx_data_TKEEP
	.s_axis_rx_data_TLAST(s_axis_tcp_rx_data_tlast),                          // input wire [0 : 0] s_axis_rx_data_TLAST
	.s_axis_rx_metadata_TVALID(s_axis_tcp_rx_meta_tvalid),                // input wire s_axis_rx_metadata_TVALID
	.s_axis_rx_metadata_TREADY(s_axis_tcp_rx_meta_tready),                // output wire s_axis_rx_metadata_TREADY
	.s_axis_rx_metadata_TDATA(s_axis_tcp_rx_meta_tdata),                  // input wire [15 : 0] s_axis_rx_metadata_TDATA
	.s_axis_tx_status_TVALID(s_axis_tcp_tx_status_tvalid),                    // input wire s_axis_tx_status_TVALID
	.s_axis_tx_status_TREADY(s_axis_tcp_tx_status_tready),                    // output wire s_axis_tx_status_TREADY
	.s_axis_tx_status_TDATA(s_axis_tcp_tx_status_tdata),                      // input wire [23 : 0] s_axis_tx_status_TDATA
	
	//Client only
	.runTx(runTx),
	.transferSize(transferSize),                                          // input wire [0 : 0] transferSize_V
	.sessionID(sessionIDReg),                                                // input wire [7 : 0] sessionID_V
	.pkgWordCount(pkgWordCountReg),                                      // input wire [7 : 0] pkgWordCount_V
	.ap_clk(ap_clk),                                                          // input wire aclk
	.ap_rst_n(ap_rst_n)                                                    // input wire aresetn
 );
`else
send_recv_ip send_recv (
	.m_axis_read_package_V_TVALID(m_axis_tcp_read_pkg_tvalid),              // output wire m_axis_read_package_TVALID
	.m_axis_read_package_V_TREADY(m_axis_tcp_read_pkg_tready),              // input wire m_axis_read_package_TREADY
	.m_axis_read_package_V_TDATA(m_axis_tcp_read_pkg_tdata),                // output wire [31 : 0] m_axis_read_package_TDATA
	.m_axis_tx_data_TVALID(m_axis_tcp_tx_data_tvalid),                        // output wire m_axis_tx_data_TVALID
	.m_axis_tx_data_TREADY(m_axis_tcp_tx_data_tready),                        // input wire m_axis_tx_data_TREADY
	.m_axis_tx_data_TDATA(m_axis_tcp_tx_data_tdata),                          // output wire [63 : 0] m_axis_tx_data_TDATA
	.m_axis_tx_data_TKEEP(m_axis_tcp_tx_data_tkeep),                          // output wire [7 : 0] m_axis_tx_data_TKEEP
	.m_axis_tx_data_TLAST(m_axis_tcp_tx_data_tlast),                          // output wire [0 : 0] m_axis_tx_data_TLAST
	.m_axis_tx_metadata_V_TVALID(m_axis_tcp_tx_meta_tvalid),                // output wire m_axis_tx_metadata_TVALID
	.m_axis_tx_metadata_V_TREADY(m_axis_tcp_tx_meta_tready),                // input wire m_axis_tx_metadata_TREADY
	.m_axis_tx_metadata_V_TDATA(m_axis_tcp_tx_meta_tdata),                  // output wire [15 : 0] m_axis_tx_metadata_TDATA
	.s_axis_notifications_V_TVALID(s_axis_tcp_notification_tvalid),            // input wire s_axis_notifications_TVALID
	.s_axis_notifications_V_TREADY(s_axis_tcp_notification_tready),            // output wire s_axis_notifications_TREADY
	.s_axis_notifications_V_TDATA(s_axis_tcp_notification_tdata),              // input wire [87 : 0] s_axis_notifications_TDATA
	.s_axis_rx_data_TVALID(s_axis_tcp_rx_data_tvalid),                        // input wire s_axis_rx_data_TVALID
	.s_axis_rx_data_TREADY(s_axis_tcp_rx_data_tready),                        // output wire s_axis_rx_data_TREADY
	.s_axis_rx_data_TDATA(s_axis_tcp_rx_data_tdata),                          // input wire [63 : 0] s_axis_rx_data_TDATA
	.s_axis_rx_data_TKEEP(s_axis_tcp_rx_data_tkeep),                          // input wire [7 : 0] s_axis_rx_data_TKEEP
	.s_axis_rx_data_TLAST(s_axis_tcp_rx_data_tlast),                          // input wire [0 : 0] s_axis_rx_data_TLAST
	.s_axis_rx_metadata_V_V_TVALID(s_axis_tcp_rx_meta_tvalid),                // input wire s_axis_rx_metadata_TVALID
	.s_axis_rx_metadata_V_V_TREADY(s_axis_tcp_rx_meta_tready),                // output wire s_axis_rx_metadata_TREADY
	.s_axis_rx_metadata_V_V_TDATA(s_axis_tcp_rx_meta_tdata),                  // input wire [15 : 0] s_axis_rx_metadata_TDATA
	.s_axis_tx_status_V_TVALID(s_axis_tcp_tx_status_tvalid),                    // input wire s_axis_tx_status_TVALID
	.s_axis_tx_status_V_TREADY(s_axis_tcp_tx_status_tready),                    // output wire s_axis_tx_status_TREADY
	.s_axis_tx_status_V_TDATA(s_axis_tcp_tx_status_tdata),                      // input wire [23 : 0] s_axis_tx_status_TDATA
	
	//Client only
	.runTx_V(runTx),
	.transferSize_V(transferSize),                                          // input wire [0 : 0] transferSize_V
	.sessionID_V(sessionIDReg),                                                // input wire [7 : 0] sessionID_V
	.pkgWordCount_V(pkgWordCountReg),                                      // input wire [7 : 0] pkgWordCount_V
	.ap_clk(ap_clk),                                                          // input wire aclk
	.ap_rst_n(ap_rst_n)                                                    // input wire aresetn
 );
`endif 

/*
 * Role Controller
 */

// AXI4-Lite slave interface

send_recv_slave send_recv_slave_inst (
	.aclk         (ap_clk),
	.aresetn      (ap_rst_n),
	.axi_ctrl     (axi_ctrl),
	.ap_start     (ap_start),
	.ap_done      (ap_done),
	.useConn      (useConn),
	.useIpAddr    (useIpAddr),
	.pkgWordCount (pkgWordCount),
	.basePort     (basePort),
	.baseIpAddress(baseIpAddress),
	.transferSize  (transferSize),
	.isServer    (isServer),
	.timeInSeconds(timeInSeconds),
	.timeInCycles (timeInCycles),
	.execution_cycles(execution_cycles),
	.consumed_bytes  (consumed_bytes),
	.produced_bytes  (produced_bytes),
	.sessionID (cnfg_sessionID)
);


/*
 * Statistics
 */


always @(posedge ap_clk) begin
    if (~ap_rst_n) begin
        consumed_bytes <= '0;
        produced_bytes <= '0;
    end
    else begin
        if (ap_start_pulse) begin
          consumed_bytes <= '0;
          produced_bytes <= '0;
        end

        if (s_axis_tcp_rx_data_tvalid && s_axis_tcp_rx_data_tready) begin
            case (s_axis_tcp_rx_data_tkeep)
                64'h1: consumed_bytes <= consumed_bytes + 1;
                64'h3: consumed_bytes <= consumed_bytes + 2;
                64'h7: consumed_bytes <= consumed_bytes + 4;
                64'hF: consumed_bytes <= consumed_bytes + 4;
                64'h1F: consumed_bytes <= consumed_bytes + 5;
                64'h3F: consumed_bytes <= consumed_bytes + 6;
                64'h7F: consumed_bytes <= consumed_bytes + 7;
                64'hFF: consumed_bytes <= consumed_bytes + 8;
                64'hFFFF: consumed_bytes <= consumed_bytes + 16;
                64'hFFFFF: consumed_bytes <= consumed_bytes + 20;
                64'hFFFFFF: consumed_bytes <= consumed_bytes + 24;
                64'hFFFFFFF: consumed_bytes <= consumed_bytes + 28;
                64'hFFFFFFFF: consumed_bytes <= consumed_bytes + 32;
                64'hFFFFFFFFF: consumed_bytes <= consumed_bytes + 36;
                64'hFFFFFFFFFF: consumed_bytes <= consumed_bytes + 40;
                64'hFFFFFFFFFFF: consumed_bytes <= consumed_bytes + 44;
                64'hFFFFFFFFFFFF: consumed_bytes <= consumed_bytes + 48;
                64'hFFFFFFFFFFFFF: consumed_bytes <= consumed_bytes + 52;
                64'hFFFFFFFFFFFFFF: consumed_bytes <= consumed_bytes + 56;
                64'hFFFFFFFFFFFFFFF: consumed_bytes <= consumed_bytes + 60;
                64'hFFFFFFFFFFFFFFFF: consumed_bytes <= consumed_bytes + 64;
            endcase
        end

        if (m_axis_tcp_tx_data_tvalid && m_axis_tcp_tx_data_tready) begin
            case (m_axis_tcp_tx_data_tkeep)
                64'hF: produced_bytes <= produced_bytes + 4;
                64'hFF: produced_bytes <= produced_bytes + 8;
                64'hFFFF: produced_bytes <= produced_bytes + 16;
                64'hFFFFF: produced_bytes <= produced_bytes + 20;
                64'hFFFFFF: produced_bytes <= produced_bytes + 24;
                64'hFFFFFFF: produced_bytes <= produced_bytes + 28;
                64'hFFFFFFFF: produced_bytes <= produced_bytes + 32;
                64'hFFFFFFFFF: produced_bytes <= produced_bytes + 36;
                64'hFFFFFFFFFF: produced_bytes <= produced_bytes + 40;
                64'hFFFFFFFFFFF: produced_bytes <= produced_bytes + 44;
                64'hFFFFFFFFFFFF: produced_bytes <= produced_bytes + 48;
                64'hFFFFFFFFFFFFF: produced_bytes <= produced_bytes + 52;
                64'hFFFFFFFFFFFFFF: produced_bytes <= produced_bytes + 56;
                64'hFFFFFFFFFFFFFFF: produced_bytes <= produced_bytes + 60;
                64'hFFFFFFFFFFFFFFFF: produced_bytes <= produced_bytes + 64;
            endcase
        end

    end
end


logic[31:0] tx_cmd_counter;
logic[31:0] tx_pkg_counter;
logic[31:0] tx_sts_counter;
logic[31:0] tx_sts_good_counter;
always @(posedge ap_clk) begin
    if (~ap_rst_n | runExperiment) begin
        tx_cmd_counter <= '0;
        tx_pkg_counter <= '0;
        tx_sts_counter <= '0;
        tx_sts_good_counter <= '0;
    end
    else begin
        if (m_axis_tcp_tx_meta_tvalid && m_axis_tcp_tx_meta_tready) begin
            tx_cmd_counter <= tx_cmd_counter + 1;
        end
        if (m_axis_tcp_tx_data_tvalid && m_axis_tcp_tx_data_tready && m_axis_tcp_tx_data_tlast) begin
            tx_pkg_counter <= tx_pkg_counter + 1;
        end
        if (s_axis_tcp_tx_status_tvalid && s_axis_tcp_tx_status_tready) begin
            tx_sts_counter <= tx_sts_counter + 1;
            if (s_axis_tcp_tx_status_tdata[63:62] == 0) begin
                tx_sts_good_counter <= tx_sts_good_counter + 1;
            end
        end
    end
end

`define DEBUG
`ifdef DEBUG

ila_controller controller_debug
(
.clk(ap_clk), // input wire clk
 .probe0(ap_start_pulse),                                      //1
 .probe1(isServer),                                          // 1
 .probe2(useConnReg),                                         // 16
 .probe3(pkgWordCountReg),                                    // 16
 .probe4(baseIpAddress),                                          //32
 .probe5(transferSize),                                      //32  
 .probe6(timeInCycles),                                       //64      
 .probe7(cnfg_sessionID),                                         //16
 .probe8(useIpAddrReg),                                        //16   
 .probe9(ap_start),                                            //1   
 .probe10(ap_done)                                           //1
);


ila_perf benchmark_debug (
  .clk(ap_clk), // input wire clk

  .probe0(s_axis_tcp_rx_data_tvalid), // input wire [0:0]  probe4    
  .probe1(s_axis_tcp_rx_data_tready), // input wire [0:0]  probe5                        
  .probe2(finishExperiment), // input wire [0:0]  probe6                        
  .probe3(runTx), // input wire [0:0]  probe7                        
  .probe4(m_axis_tcp_tx_data_tvalid),    //1                                                
  .probe5(m_axis_tcp_tx_data_tready),//1
  .probe6(m_axis_tcp_tx_meta_tvalid),//1
  .probe7(m_axis_tcp_tx_meta_tready),//1
  .probe8(s_axis_tcp_tx_status_tvalid),//1
  .probe9(s_axis_tcp_tx_status_tready), //1
  .probe10(s_axis_tcp_tx_status_tdata[63:62]), //2
  .probe11(produced_bytes[63:0]), // 64
  .probe12(consumed_bytes[63:0]),// 64 
  .probe13(sessionIDReg[15:0]), // input wire [15:0]  
  .probe14(tx_cmd_counter[31:0]), // input wire [31:0]  
  .probe15(running), //1
  .probe16(s_axis_tcp_notification_tvalid), //1
  .probe17(s_axis_tcp_notification_tready), //1
  .probe18(s_axis_tcp_tx_status_tdata[61:32]), //30
  .probe19(execution_cycles[63:0]), //64
  .probe20(transferSize[15:0]), //16
  .probe21(tx_pkg_counter[31:0]),//32
  .probe22(tx_sts_good_counter[31:0]), //32
  .probe23(s_axis_tcp_rx_meta_tvalid),                // 1
  .probe24(s_axis_tcp_rx_meta_tready),                // 1
  .probe25(m_axis_tcp_read_pkg_tvalid),              // 1
  .probe26(m_axis_tcp_read_pkg_tready),               //1 
  .probe27(tx_sts_counter), //32
  .probe28(tx_meta_down), //32
  .probe29(tx_status_down), //32
  .probe30(tx_data_down), //32
  .probe31(s_axis_tcp_rx_meta_tdata[15:0]) //16
);


`endif


endmodule
`default_nettype wire
