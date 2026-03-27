//////////////////////////////////////////////////////////////////////////////
// Copyright © 2015-2025 Advanced Micro Devices, Inc. All rights reserved.

// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”),
// to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
// and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
// IN THE SOFTWARE.
//////////////////////////////////////////////////////////////////////////////
//
// DO NOT MODIFY THIS FILE.
//////////////////////////////////////////////////////////////////////////////
//
// Company  		: Advanced Micro Devices
//
// Create Date      : 13/02/2024 10:36:53 AM
// Design Name      : AXIS segmented <=> unsegmented interface converter
// Module Name      : axis_seg_and_unseg_converter
// Project Name     :
// Target Devices   :
// Tool Versions    :
// Description      : Segmented AXI stream <-> unsegmented AXI stream converter for DCMAC
//                  : Supported mode - Coupled MAC+PHY mode (FixedE)
//                  : Supported data rates - 100 or 200 or 400Gbps
//					: Data width of each segment of segmented axis interface is considered as 128bits
//                  : Unsegmented AXIS interface configuration as below,
//                  : 100G - 1x256b @ >=450MHz, higher clock is needed to accomodate packet rate (considering 65Byte packets)
//					: 200G - 1x1024b @391MHz, data width is doubled to accomodate packet rate (considering 65Byte packets)
//					: 400G - 2x1024b @391MHz, two ports are used to accomodate packet rate (considering 129Byte packets)
//
// Revision 		: 1.00 - Initial version
//					: 1.01 - Critical path optimization and design improvements
//					: 1.02 - Added error transfer between seg & unseg interfaces( seg err <-> unseg tuser )
//
// Additional Notes :
//                  : 1. Backpressure is not supported by DCMAC at the segmented interface of RX side. Data must be consumed
//					: when the rx_tvalid signal is available. User need to consider required buffering at the input/output
//                  : of the seg to unseg converter. Overflow of the input buffer in the seg to unseg converter will lead
//                  : to packet loss and/or data corruption. To avoid this, input packets will be dropped when the packet
//					: buffer of the seg to unseg converter becomes full(tail drop performed). This feature can be disabled
//					: when using with other traffic masters which support back pressure.
//
//					: 2. At the TX side of the DCMAC, packets should not be sent with broken Valid signal (seg_val should
//					: not go low in between a SoP and EoP. seg_val deassertion should aligned with an EoP and seg_val
//					: assertion should aligned with SoP). Violation of this leads to packet loss and corruption at the
//                  : DCMAC. To overcome this limitation and also to improve segment packing efficiency, packets are processed as a
//                  : block(of packets) and sent to DCMAC when tx_tready signal of DCMAC segmented is available.
//					: This makes the unsegmented to segmented converter bulky and uses deep FIFOs aligned with the
//					: block size used. For optimal performance, preferred block size is 512
//
//					: 3. For 100G mode, the 2x128 segments are mapped to 1x256 bit AXI Stream interface. To accomodate the Packet
//					: rate, considering the worst case packet size of 65Bytes, the converter is designed to run at a
//					: higher clock than the DCMAC segmented interface clock(>=450MHz is preferred, least minimum is 425 MHz).
//
//					: 4. For 200G mode, the 4x128 segments are mapped to 1x1024 bit AXI Stream interface. Direct mapping of 4x128
//					: segments to 1x512 bit AXIS would need atleast 562MHz for the converter to accomodate the packet rate
//					: considering the worst case packet size of 65Bytes. Timing closure would be difficult for such high clocks
//					: and most of the AXIS based IPs would not support such high clocks. To accomodate the packet rate,
//					: 4x128 segments are mapped to 1x1024 bit AXI stream. The converter can run at the same DCMAC clock of the
//					: segmented interface
//
//					: 5. For 400G operation 8x128 segments are mapped to 2x1024 bit AXI Stream interfaces to accomodate the packet
//					: rate considering the worst case packet size of 129Bytes. Direct mapping of 8x128 segments to 1x1024 bit
//                  : AXIS would  need atleast 654MHz for the converter. To overcome the similar limitations mentioned
//					: for the 200G case, 8x128 segments are mapped to 2x1024 bit AXI Streams and the converter is designed to run
//					: at the same DCMAC clock of the segmented interface(391MHz).The first packet received from the DCMAC
//					: segmented interface is sent to the first AXIS port and next packet to the second AXIS port and so on
//					: in a Round Robin fashion. At the unsegmented to segmented side, packets are taken from the AXIS ports based
//					: on the availabily of packets and follow round robin arbitration.
//
//					: 6. Array based mechanism is implemented for packing and unpacking of segments in the converter. The design
//					: consumes considerable logic for the 200G and 400G configuration and also have timing closure challenges.
//
//					: 7. Critical path optimizations done and timing improved for all the configurations (with the DCMAC example design).
//					: however 400G & 200G configuration may have timing closure challenges when integrating with large designs.
//
//					: 8. Debug logic and statistic counters are included in the converter but it is recommened to disable them for
//					: synthesis/implementation to avoid timing violations. They were added only for simulation/verification purpose.
//
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

// User configuration defines; please refer IP documentation for more details

`define data_rate_200               // data rate of DCMAC port (update the suffix as per the requirement; 100,200 or 400)
`define en_seg_to_unseg_cnv         // Enable/disable segmented to unsegmented axi stream converter
`define en_unseg_to_seg_cnv       	// Enable/disable unsegmented to segmented axi stream converter
`define max_packet_size 9216      	// Maximum packet size expeted/to be supported
`define max_pkt_size_above_1k		// Comment off if max packet size is less than 1024Bytes
`define en_flow_control				// Enable/Disable flow control at the seg to unseg converter.
									// Enable if backpressure is not supported by the traffic source. Incomimg packets are dropped when
									// downstream ports backpressures and buffers become full. Disable if backpressure is supported by
									// the traffic master

// Enabling bleow defines is not recommended (shall be enabled for simulation)

//`define statistics_en             	// Enable Input & output port statistic (packet & byte counters)
//`define debug_en                  	// Enable error checks in the design

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Do not change the below derived defines except "independant_clk"

// derived Converter defines

`define segment_width 128			// data width of each segment of segmented axis interface
`ifdef data_rate_100
    `define num_segments 2			// number of segments of input segmented axis interface
    `define num_axis_ports 1		// number of ports of output unsegmented axis interface
    `define unseg_axis_w 256		// data width of output unsegmented axis interface
    `define pktarray_depth 4		// depth of the segment array used to unpack/pack the segments
    `define independant_clk			// if defined segmented and the unsegmented interface runs at different clocks.
									// for applications other than DCMAC and data rate less then 100Gbps user can run the interfaces
									// at the desired clock frequency, either single clock or dual clock as per the need. Same applies for
									// 200G and 400G configurations also
`elsif data_rate_200
    `define num_segments 4
    `define en_port1
	`define num_axis_ports 1
	`define unseg_axis_w 1024
	`define pktarray_depth 16
`elsif data_rate_400
    `define num_segments 8
    `define num_axis_ports 2
    `define en_port1
    `define en_port2
    `define en_port3
    `define en_axis1
    `define pktarray_depth 16
	`define unseg_axis_w 1024
`else
    `define invalid_config			// only 100, 200 or 400 data rate with the above configurations allowed
									// For other rates user can choose the nearest configuration and drive the clocks as needed
									// to meet the data rate
`endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

`ifndef invalid_config

module axis_seg_and_unseg_converter
    (
	`ifdef independant_clk
	(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk_axis_unseg_in CLK" *)
	(* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF m_axis_pktout, ASSOCIATED_RESET aresetn_axis_unseg_in" *)
	input aclk_axis_unseg_in,
	(* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn_axis_unseg_in RST" *)
	(* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
	input aresetn_axis_unseg_in,
    `endif

    `ifdef en_seg_to_unseg_cnv
	// AXIS Segment to Unsegment converter ports
	// Clock & Resets
	(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk_rx_seg_in CLK" *)
	(* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET aresetn_rx_seg_in" *)
	input aclk_rx_seg_in,
	(* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn_rx_seg_in RST" *)
	(* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
	input aresetn_rx_seg_in,

	// Input Segmented stream interface
	// Port0 (segments 0 & 1) is active for all valid configurations
	// Segment 0 input
	input                                     	Seg2UnSegEna0_in,
	input [`segment_width-1:0]                	Seg2UnSegDat0_in,
	input                                     	Seg2UnSegSop0_in,
	input                                     	Seg2UnSegEop0_in,
	input                                     	Seg2UnSegErr0_in,
	input [($clog2(`segment_width/8))-1:0]    	Seg2UnSegMty0_in,
	// Segment 1 input
	input                                     	Seg2UnSegEna1_in,
	input  [`segment_width-1:0]               	Seg2UnSegDat1_in,
	input                                     	Seg2UnSegSop1_in,
	input                                     	Seg2UnSegEop1_in,
	input                                     	Seg2UnSegErr1_in,
	input  [($clog2(`segment_width/8))-1:0]   	Seg2UnSegMty1_in,
	`ifdef en_port1
	// Segment 2 input
	input                                     	Seg2UnSegEna2_in,
	input  [`segment_width-1:0]               	Seg2UnSegDat2_in,
	input                                     	Seg2UnSegSop2_in,
	input                                     	Seg2UnSegEop2_in,
	input                                     	Seg2UnSegErr2_in,
	input  [($clog2(`segment_width/8))-1:0]   	Seg2UnSegMty2_in,
	// Segment 3 input
	input                                     	Seg2UnSegEna3_in,
	input  [`segment_width-1:0]               	Seg2UnSegDat3_in,
	input                                     	Seg2UnSegSop3_in,
	input                                     	Seg2UnSegEop3_in,
	input                                     	Seg2UnSegErr3_in,
	input  [($clog2(`segment_width/8))-1:0]   	Seg2UnSegMty3_in,
	`endif
	`ifdef en_port2
	// Segment 4 input
	input                                     	Seg2UnSegEna4_in,
	input  [`segment_width-1:0]               	Seg2UnSegDat4_in,
	input                                     	Seg2UnSegSop4_in,
	input                                     	Seg2UnSegEop4_in,
	input                                     	Seg2UnSegErr4_in,
	input  [($clog2(`segment_width/8))-1:0]	  	Seg2UnSegMty4_in,
	// Segment 5 input
	input                                     	Seg2UnSegEna5_in,
	input  [`segment_width-1:0]               	Seg2UnSegDat5_in,
	input                                     	Seg2UnSegSop5_in,
	input                                     	Seg2UnSegEop5_in,
	input                                     	Seg2UnSegErr5_in,
	input  [($clog2(`segment_width/8))-1:0]   	Seg2UnSegMty5_in,
	`endif
	`ifdef en_port3
	// Segment 6 input
	input                                     	Seg2UnSegEna6_in,
	input  [`segment_width-1:0]               	Seg2UnSegDat6_in,
	input                                     	Seg2UnSegSop6_in,
	input                                     	Seg2UnSegEop6_in,
	input                                     	Seg2UnSegErr6_in,
	input  [($clog2(`segment_width/8))-1:0]   	Seg2UnSegMty6_in,
	// Segment 7 input
	input                                     	Seg2UnSegEna7_in,
	input  [`segment_width-1:0]               	Seg2UnSegDat7_in,
	input                                     	Seg2UnSegSop7_in,
	input                                     	Seg2UnSegEop7_in,
	input                                     	Seg2UnSegErr7_in,
	input  [($clog2(`segment_width/8))-1:0]   	Seg2UnSegMty7_in,
	`endif
	input wire                                	Seg2UnSeg_tvalid_in,

	// Packet output interface - Unsegmented AXI Stream
	// AXIS-0 is active for all valid configurations
	// Unsegmented AXIS-0 interface
	(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis0_pkt_out TDATA" *)
	output [`unseg_axis_w-1:0]      			m_axis0_tdata,
	(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis0_pkt_out TKEEP" *)
	output [(`unseg_axis_w/8)-1:0]    			m_axis0_tkeep,
	(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis0_pkt_out TLAST" *)
	output                            			m_axis0_tlast,
	(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis0_pkt_out TVALID" *)
	output                            			m_axis0_tvalid,
	(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis0_pkt_out TUSER" *)
	output                            			m_axis0_tuser,
	(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis0_pkt_out TREADY" *)
	input                             			m_axis0_tready,

	`ifdef en_axis1
	// Unsegmented AXIS-1 interface
	(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis1_pkt_out TDATA" *)
	output [`unseg_axis_w-1:0]        			m_axis1_tdata,
	(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis1_pkt_out TKEEP" *)
	output [(`unseg_axis_w/8)-1:0]    			m_axis1_tkeep,
	(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis1_pkt_out TLAST" *)
	output                            			m_axis1_tlast,
	(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis1_pkt_out TVALID" *)
	output                            			m_axis1_tvalid,
	(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis1_pkt_out TUSER" *)
	output                            			m_axis1_tuser,
	(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis1_pkt_out TREADY" *)
	input                             			m_axis1_tready,
	`endif

	`ifdef en_flow_control
	output wire seg2unseg_buff_full,
	`else
	output wire	seg2unseg_inbuff_overflow,
	output wire	seg2unseg_inbuff_afull,
	`endif

	// Statistics
	`ifdef statistics_en
	`ifdef en_axis1
	output wire [63: 0]	stat_rx_p1_pkt_out_cnt,
	output wire [63: 0]	stat_rx_p1_err_pkt_out_cnt,
	output wire [63: 0] stat_rx_p1_pkt_out_byte_cnt,
	output wire [63: 0] stat_rx_p0_pkt_out_cnt,
	output wire [63: 0] stat_rx_p0_err_pkt_out_cnt,
	output wire [63: 0] stat_rx_p0_pkt_out_byte_cnt,
	`endif
	output wire [63: 0] stat_rx_total_pkt_in_cnt,
	output wire [63: 0] stat_rx_total_err_pkt_in_cnt,
	output wire [63: 0] stat_rx_total_pkt_in_byte_cnt,
	output wire [63: 0] stat_rx_total_pkt_out_cnt,
	output wire [63: 0] stat_rx_total_err_pkt_out_cnt,
	output wire [63: 0] stat_rx_total_pkt_out_byte_cnt,
	`endif
    `endif

	`ifdef debug_en
	output wire seg2unseg_broken_packet_out_error,
	output wire seg2unseg_rx_packet_error,
	`endif

    `ifdef en_unseg_to_seg_cnv
	// AXIS Segment to Unsegment converter ports

    // Clock & Resets
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk_tx_seg_in CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET aresetn_tx_seg_in" *)
    input aclk_tx_seg_in,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn_tx_seg_in RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input aresetn_tx_seg_in,

    // Output Segmented stream interface
    // Port0 (segments 0 & 1) is active for all valid configurations
    // Segment 0 output
    output                                     	Unseg2SegEna0_out,
    output [`segment_width-1:0]                	Unseg2SegDat0_out,
    output                                     	Unseg2SegSop0_out,
    output                                     	Unseg2SegEop0_out,
    output                                     	Unseg2SegErr0_out,
    output [($clog2(`segment_width/8))-1:0]	   	Unseg2SegMty0_out,
    // Segment 1 output
    output                                     	Unseg2SegEna1_out,
    output  [`segment_width-1:0]               	Unseg2SegDat1_out,
    output                                     	Unseg2SegSop1_out,
    output                                     	Unseg2SegEop1_out,
    output                                     	Unseg2SegErr1_out,
    output  [($clog2(`segment_width/8))-1:0]   	Unseg2SegMty1_out,
    `ifdef en_port1
    // Segment 2 output
    output                                     	Unseg2SegEna2_out,
    output  [`segment_width-1:0]               	Unseg2SegDat2_out,
    output                                     	Unseg2SegSop2_out,
    output                                     	Unseg2SegEop2_out,
    output                                     	Unseg2SegErr2_out,
    output  [($clog2(`segment_width/8))-1:0]   	Unseg2SegMty2_out,
    // Segment 3 output
    output                                     	Unseg2SegEna3_out,
    output  [`segment_width-1:0]               	Unseg2SegDat3_out,
    output                                     	Unseg2SegSop3_out,
    output                                     	Unseg2SegEop3_out,
    output                                     	Unseg2SegErr3_out,
    output  [($clog2(`segment_width/8))-1:0]   	Unseg2SegMty3_out,
    `endif
    `ifdef en_port2
    // Segment 4 output
    output                                     	Unseg2SegEna4_out,
    output  [`segment_width-1:0]               	Unseg2SegDat4_out,
    output                                     	Unseg2SegSop4_out,
    output                                     	Unseg2SegEop4_out,
    output                                     	Unseg2SegErr4_out,
    output  [($clog2(`segment_width/8))-1:0]   	Unseg2SegMty4_out,
    // Segment 5 output
    output                                     	Unseg2SegEna5_out,
    output  [`segment_width-1:0]               	Unseg2SegDat5_out,
    output                                     	Unseg2SegSop5_out,
    output                                     	Unseg2SegEop5_out,
    output                                     	Unseg2SegErr5_out,
    output  [($clog2(`segment_width/8))-1:0]   	Unseg2SegMty5_out,
    `endif
    `ifdef en_port3
    // Segment 6 output
    output                                     	Unseg2SegEna6_out,
    output  [`segment_width-1:0]               	Unseg2SegDat6_out,
    output                                     	Unseg2SegSop6_out,
    output                                     	Unseg2SegEop6_out,
    output                                     	Unseg2SegErr6_out,
    output  [($clog2(`segment_width/8))-1:0]   	Unseg2SegMty6_out,
    // Segment 7 output
    output                                     	Unseg2SegEna7_out,
    output  [`segment_width-1:0]               	Unseg2SegDat7_out,
    output                                     	Unseg2SegSop7_out,
    output                                     	Unseg2SegEop7_out,
    output                                     	Unseg2SegErr7_out,
    output  [($clog2(`segment_width/8))-1:0]   	Unseg2SegMty7_out,
    `endif

    // Packet input interface - Unsegmented AXI Stream
    // AXI-0 is active for all valid configurations
    // Unsegmented AXIS-0 interface
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis0_pkt_in TDATA" *)
    input [`unseg_axis_w-1:0]       			s_axis0_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis0_pkt_in TKEEP" *)
    input [(`unseg_axis_w/8)-1:0]   			s_axis0_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis0_pkt_in TLAST" *)
    input                           			s_axis0_tlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis0_pkt_in TVALID" *)
    input                           			s_axis0_tvalid,
	(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis0_pkt_in TUSER" *)
    input                           			s_axis0_tuser,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis0_pkt_in TREADY" *)
    output                          			s_axis0_tready,

    `ifdef en_axis1
    // Unsegmented AXIS-1 interface
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis1_pkt_in TDATA" *)
    input [`unseg_axis_w-1:0]       			s_axis1_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis1_pkt_in TKEEP" *)
    input [(`unseg_axis_w/8)-1:0]   			s_axis1_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis1_pkt_in TLAST" *)
    input                           			s_axis1_tlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis1_pkt_in TVALID" *)
    input                           			s_axis1_tvalid,
	(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis1_pkt_in TUSER" *)
    input                           			s_axis1_tuser,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis1_pkt_in TREADY" *)
    output                          			s_axis1_tready,
    `endif

    `ifdef debug_en
    output wire unseg2seg_missing_sop_error,
    output wire unseg2seg_broken_pkt_out_error,
    output wire unseg2seg_broken_pkt_in_error,
    `endif

	// Statistics
    `ifdef statistics_en
    `ifdef en_axis1
    output wire [63: 0] stat_tx_p1_pkt_in_cnt,
    output wire [63: 0] stat_tx_p1_err_pkt_in_cnt,
    output wire [63: 0] stat_tx_p1_pkt_in_byte_cnt,
    output wire [63: 0] stat_tx_p0_pkt_in_cnt,
    output wire [63: 0] stat_tx_p0_err_pkt_in_cnt,
    output wire [63: 0] stat_tx_p0_pkt_in_byte_cnt,
    `endif
    output wire [63: 0] stat_tx_total_pkt_in_cnt,
    output wire [63: 0] stat_tx_total_err_pkt_in_cnt,
    output wire [63: 0] stat_tx_total_pkt_in_byte_cnt,
    output wire [63: 0] stat_tx_total_pkt_out_cnt,
    output wire [63: 0] stat_tx_total_err_pkt_out_cnt,
    output wire [63: 0] stat_tx_total_pkt_out_byte_cnt,
    `endif

	input wire	Unseg2Seg_tready_in,
	output wire	Unseg2Seg_tvalid_out
    `endif
	);

//-----------------------------------------------------------------------------------------------------------------------

//------------------- AXIS Segment to Unsegment Converter

`ifdef en_seg_to_unseg_cnv

axis_seg_to_unseg_converter u_axis_seg_to_unseg_converter
	(
	// Clock & Resets
	.aclk_axis_seg_in(aclk_rx_seg_in),
	.aresetn_axis_seg_in(aresetn_rx_seg_in),
	`ifdef independant_clk
	.aclk_axis_unseg_in(aclk_axis_unseg_in),
	.aresetn_axis_unseg_in(aresetn_axis_unseg_in),
	`endif
	// Segmented interface
	// Port0 (segments 0 & 1) is active for all valid configurations
	// Segment 0 input
	.Seg2UnSegEna0_in(Seg2UnSegEna0_in),
	.Seg2UnSegDat0_in(Seg2UnSegDat0_in),
	.Seg2UnSegSop0_in(Seg2UnSegSop0_in),
	.Seg2UnSegEop0_in(Seg2UnSegEop0_in),
	.Seg2UnSegErr0_in(Seg2UnSegErr0_in),
	.Seg2UnSegMty0_in(Seg2UnSegMty0_in),
	// Segment 1 input
	.Seg2UnSegEna1_in(Seg2UnSegEna1_in),
	.Seg2UnSegDat1_in(Seg2UnSegDat1_in),
	.Seg2UnSegSop1_in(Seg2UnSegSop1_in),
	.Seg2UnSegEop1_in(Seg2UnSegEop1_in),
	.Seg2UnSegErr1_in(Seg2UnSegErr1_in),
	.Seg2UnSegMty1_in(Seg2UnSegMty1_in),
	`ifdef en_port1
	// Segment 2 input
	.Seg2UnSegEna2_in(Seg2UnSegEna2_in),
	.Seg2UnSegDat2_in(Seg2UnSegDat2_in),
	.Seg2UnSegSop2_in(Seg2UnSegSop2_in),
	.Seg2UnSegEop2_in(Seg2UnSegEop2_in),
	.Seg2UnSegErr2_in(Seg2UnSegErr2_in),
	.Seg2UnSegMty2_in(Seg2UnSegMty2_in),
	// Segment 3 input
	.Seg2UnSegEna3_in(Seg2UnSegEna3_in),
	.Seg2UnSegDat3_in(Seg2UnSegDat3_in),
	.Seg2UnSegSop3_in(Seg2UnSegSop3_in),
	.Seg2UnSegEop3_in(Seg2UnSegEop3_in),
	.Seg2UnSegErr3_in(Seg2UnSegErr3_in),
	.Seg2UnSegMty3_in(Seg2UnSegMty3_in),
	`endif
	`ifdef en_port2
	// Segment 4 input
	.Seg2UnSegEna4_in(Seg2UnSegEna4_in),
	.Seg2UnSegDat4_in(Seg2UnSegDat4_in),
	.Seg2UnSegSop4_in(Seg2UnSegSop4_in),
	.Seg2UnSegEop4_in(Seg2UnSegEop4_in),
	.Seg2UnSegErr4_in(Seg2UnSegErr4_in),
	.Seg2UnSegMty4_in(Seg2UnSegMty4_in),
	// Segment 5 input
	.Seg2UnSegEna5_in(Seg2UnSegEna5_in),
	.Seg2UnSegDat5_in(Seg2UnSegDat5_in),
	.Seg2UnSegSop5_in(Seg2UnSegSop5_in),
	.Seg2UnSegEop5_in(Seg2UnSegEop5_in),
	.Seg2UnSegErr5_in(Seg2UnSegErr5_in),
	.Seg2UnSegMty5_in(Seg2UnSegMty5_in),
	`endif
	`ifdef en_port3
	// Segment 6 input
	.Seg2UnSegEna6_in(Seg2UnSegEna6_in),
	.Seg2UnSegDat6_in(Seg2UnSegDat6_in),
	.Seg2UnSegSop6_in(Seg2UnSegSop6_in),
	.Seg2UnSegEop6_in(Seg2UnSegEop6_in),
	.Seg2UnSegErr6_in(Seg2UnSegErr6_in),
	.Seg2UnSegMty6_in(Seg2UnSegMty6_in),
	// Segment 7 input
	.Seg2UnSegEna7_in(Seg2UnSegEna7_in),
	.Seg2UnSegDat7_in(Seg2UnSegDat7_in),
	.Seg2UnSegSop7_in(Seg2UnSegSop7_in),
	.Seg2UnSegEop7_in(Seg2UnSegEop7_in),
	.Seg2UnSegErr7_in(Seg2UnSegErr7_in),
	.Seg2UnSegMty7_in(Seg2UnSegMty7_in),
	`endif
	// Packet output interface - Unsegmented AXI Stream
    // AXI-0 is active for all valid configurations
    // Unsegmented AXIS-0 interface
	.m_axis0_tdata(m_axis0_tdata),
	.m_axis0_tkeep(m_axis0_tkeep),
	.m_axis0_tlast(m_axis0_tlast),
	.m_axis0_tvalid(m_axis0_tvalid),
	.m_axis0_tuser(m_axis0_tuser),
	.m_axis0_tready(m_axis0_tready),
	`ifdef en_axis1
	// Unsegmented AXIS-1 interface
	.m_axis1_tdata(m_axis1_tdata),
	.m_axis1_tkeep(m_axis1_tkeep),
	.m_axis1_tlast(m_axis1_tlast),
	.m_axis1_tvalid(m_axis1_tvalid),
	.m_axis1_tuser(m_axis1_tuser),
	.m_axis1_tready(m_axis1_tready),
	`endif

	`ifdef en_flow_control
	.buff_full(seg2unseg_buff_full),
	`else
	.inbuff_overflow(seg2unseg_inbuff_overflow),
	.inbuff_afull(seg2unseg_inbuff_afull),
	`endif

	// Statistics
	`ifdef statistics_en
	`ifdef en_axis1
	.p1_pkt_out_cnt(stat_rx_p1_pkt_out_cnt),
	.p1_err_pkt_out_cnt(stat_rx_p1_err_pkt_out_cnt),
	.p1_pkt_out_byte_cnt(stat_rx_p1_pkt_out_byte_cnt),
	.p0_pkt_out_cnt(stat_rx_p0_pkt_out_cnt),
	.p0_err_pkt_out_cnt(stat_rx_p0_err_pkt_out_cnt),
	.p0_pkt_out_byte_cnt(stat_rx_p0_pkt_out_byte_cnt),
	`endif
	.total_pkt_in_cnt(stat_rx_total_pkt_in_cnt),
	.total_err_pkt_in_cnt(stat_rx_total_err_pkt_in_cnt),
	.total_pkt_in_byte_cnt(stat_rx_total_pkt_in_byte_cnt),
	.total_pkt_out_cnt(stat_rx_total_pkt_out_cnt),
	.total_err_pkt_out_cnt(stat_rx_total_err_pkt_out_cnt),
	.total_pkt_out_byte_cnt(stat_rx_total_pkt_out_byte_cnt),
	`endif

	`ifdef debug_en
	.error_broken_packet_out(seg2unseg_broken_packet_out_error),
	.seg_rx_err_packet(seg2unseg_rx_packet_error),
	`endif

	.rx_axis_tvalid_i(Seg2UnSeg_tvalid_in)
	);
 `endif

`ifdef en_unseg_to_seg_cnv

axis_unseg_to_seg_converter u_axis_unseg_to_seg_converter
	(
	// AXIS Segment to Unsegment converter ports
	// Clock & Resets
	.aclk_axis_seg_in(aclk_tx_seg_in),
	.aresetn_axis_seg_in(aresetn_tx_seg_in),
	`ifdef independant_clk
	.aclk_axis_unseg_in(aclk_axis_unseg_in),
	.aresetn_axis_unseg_in(aresetn_axis_unseg_in),
	`endif
	// Segmented interface
	// port0 is active for all valid configurations
	// Segment 0 input
	.Unseg2SegEna0_out(Unseg2SegEna0_out),
	.Unseg2SegDat0_out(Unseg2SegDat0_out),
	.Unseg2SegSop0_out(Unseg2SegSop0_out),
	.Unseg2SegEop0_out(Unseg2SegEop0_out),
	.Unseg2SegErr0_out(Unseg2SegErr0_out),
	.Unseg2SegMty0_out(Unseg2SegMty0_out),
	// Segment 1 input
	.Unseg2SegEna1_out(Unseg2SegEna1_out),
	.Unseg2SegDat1_out(Unseg2SegDat1_out),
	.Unseg2SegSop1_out(Unseg2SegSop1_out),
	.Unseg2SegEop1_out(Unseg2SegEop1_out),
	.Unseg2SegErr1_out(Unseg2SegErr1_out),
	.Unseg2SegMty1_out(Unseg2SegMty1_out),
	`ifdef en_port1
	// Segment 2 input
	.Unseg2SegEna2_out(Unseg2SegEna2_out),
	.Unseg2SegDat2_out(Unseg2SegDat2_out),
	.Unseg2SegSop2_out(Unseg2SegSop2_out),
	.Unseg2SegEop2_out(Unseg2SegEop2_out),
	.Unseg2SegErr2_out(Unseg2SegErr2_out),
	.Unseg2SegMty2_out(Unseg2SegMty2_out),
	// Segment 3 input
	.Unseg2SegEna3_out(Unseg2SegEna3_out),
	.Unseg2SegDat3_out(Unseg2SegDat3_out),
	.Unseg2SegSop3_out(Unseg2SegSop3_out),
	.Unseg2SegEop3_out(Unseg2SegEop3_out),
	.Unseg2SegErr3_out(Unseg2SegErr3_out),
	.Unseg2SegMty3_out(Unseg2SegMty3_out),
	`endif
	`ifdef en_port2
	// Segment 4 input
	.Unseg2SegEna4_out(Unseg2SegEna4_out),
	.Unseg2SegDat4_out(Unseg2SegDat4_out),
	.Unseg2SegSop4_out(Unseg2SegSop4_out),
	.Unseg2SegEop4_out(Unseg2SegEop4_out),
	.Unseg2SegErr4_out(Unseg2SegErr4_out),
	.Unseg2SegMty4_out(Unseg2SegMty4_out),
	// Segment 5 input
	.Unseg2SegEna5_out(Unseg2SegEna5_out),
	.Unseg2SegDat5_out(Unseg2SegDat5_out),
	.Unseg2SegSop5_out(Unseg2SegSop5_out),
	.Unseg2SegEop5_out(Unseg2SegEop5_out),
	.Unseg2SegErr5_out(Unseg2SegErr5_out),
	.Unseg2SegMty5_out(Unseg2SegMty5_out),
	`endif
	`ifdef en_port3
	// Segment 6 input
	.Unseg2SegEna6_out(Unseg2SegEna6_out),
	.Unseg2SegDat6_out(Unseg2SegDat6_out),
	.Unseg2SegSop6_out(Unseg2SegSop6_out),
	.Unseg2SegEop6_out(Unseg2SegEop6_out),
	.Unseg2SegErr6_out(Unseg2SegErr6_out),
	.Unseg2SegMty6_out(Unseg2SegMty6_out),
	// Segment 7 input
	.Unseg2SegEna7_out(Unseg2SegEna7_out),
	.Unseg2SegDat7_out(Unseg2SegDat7_out),
	.Unseg2SegSop7_out(Unseg2SegSop7_out),
	.Unseg2SegEop7_out(Unseg2SegEop7_out),
	.Unseg2SegErr7_out(Unseg2SegErr7_out),
	.Unseg2SegMty7_out(Unseg2SegMty7_out),
	`endif

	// Packet input interface - Unsegmented AXI Stream
    // AXI-0 is active for all valid configurations
    // Unsegmented AXIS-0 interface
	.s_axis0_tdata(s_axis0_tdata),
	.s_axis0_tkeep(s_axis0_tkeep),
	.s_axis0_tlast(s_axis0_tlast),
	.s_axis0_tvalid(s_axis0_tvalid),
	.s_axis0_tuser(s_axis0_tuser),
	.s_axis0_tready(s_axis0_tready),
	`ifdef en_axis1
	// Unsegmented AXIS-1 interface
	.s_axis1_tdata(s_axis1_tdata),
	.s_axis1_tkeep(s_axis1_tkeep),
	.s_axis1_tlast(s_axis1_tlast),
	.s_axis1_tvalid(s_axis1_tvalid),
	.s_axis1_tuser(s_axis1_tuser),
	.s_axis1_tready(s_axis1_tready),
	`endif

	`ifdef debug_en
	.error_missing_sop(unseg2seg_missing_sop_error),
	.error_broken_pkt_out(unseg2seg_broken_pkt_out_error),
	.error_broken_pkt_in(unseg2seg_broken_pkt_in_error),
	`endif

	// Statistics
	`ifdef statistics_en
	`ifdef en_axis1
	.p1_pkt_in_cnt(stat_tx_p1_pkt_in_cnt),
	.p1_err_pkt_in_cnt(stat_tx_p1_err_pkt_in_cnt),
	.p1_pkt_in_byte_cnt(stat_tx_p1_pkt_in_byte_cnt),
	.p0_pkt_in_cnt(stat_tx_p0_pkt_in_cnt),
	.p0_err_pkt_in_cnt(stat_tx_p0_err_pkt_in_cnt),
	.p0_pkt_in_byte_cnt(stat_tx_p0_pkt_in_byte_cnt),
	`endif
	.total_pkt_in_cnt(stat_tx_total_pkt_in_cnt),
	.total_err_pkt_in_cnt(stat_tx_total_err_pkt_in_cnt),
	.total_pkt_in_byte_cnt(stat_tx_total_pkt_in_byte_cnt),
	.total_pkt_out_cnt(stat_tx_total_pkt_out_cnt),
	.total_err_pkt_out_cnt(stat_tx_total_err_pkt_out_cnt),
	.total_pkt_out_byte_cnt(stat_tx_total_pkt_out_byte_cnt),
	`endif

	.tx_axis_tready_in(Unseg2Seg_tready_in),
	.tx_axis_tvalid_out(Unseg2Seg_tvalid_out)
	);

`endif

endmodule

`endif

//########################################################################################################################

//------------------------------------ AXIS Segmented to Unsegmented Stream Converter ------------------------------------

module axis_seg_to_unseg_converter
    (
    // Clock & Resets
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk_axis_seg_in CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET aresetn_axis_seg_in" *)
    input aclk_axis_seg_in,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn_axis_seg_in RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input aresetn_axis_seg_in,
    `ifdef independant_clk
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk_axis_unseg_in CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF m_axis_pktout, ASSOCIATED_RESET aresetn_axis_unseg_in" *)
    input aclk_axis_unseg_in,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn_axis_unseg_in RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input aresetn_axis_unseg_in,
    `endif
    // Segmented interface
    // port0 is active for all valid configurations
    // Segment 0 input
    input                                   Seg2UnSegEna0_in,
    input [`segment_width-1:0]              Seg2UnSegDat0_in,
    input                                   Seg2UnSegSop0_in,
    input                                   Seg2UnSegEop0_in,
    input                                   Seg2UnSegErr0_in,
    input [($clog2(`segment_width/8))-1:0]  Seg2UnSegMty0_in,
    // Segment 1 input
    input                                   Seg2UnSegEna1_in,
    input  [`segment_width-1:0]             Seg2UnSegDat1_in,
    input                                   Seg2UnSegSop1_in,
    input                                   Seg2UnSegEop1_in,
    input                                   Seg2UnSegErr1_in,
    input  [($clog2(`segment_width/8))-1:0] Seg2UnSegMty1_in,
    `ifdef en_port1
    // Segment 2 input
    input                                   Seg2UnSegEna2_in,
    input  [`segment_width-1:0]             Seg2UnSegDat2_in,
    input                                   Seg2UnSegSop2_in,
    input                                   Seg2UnSegEop2_in,
    input                                   Seg2UnSegErr2_in,
    input  [($clog2(`segment_width/8))-1:0] Seg2UnSegMty2_in,
    // Segment 3 input
    input                                   Seg2UnSegEna3_in,
    input  [`segment_width-1:0]             Seg2UnSegDat3_in,
    input                                   Seg2UnSegSop3_in,
    input                                   Seg2UnSegEop3_in,
    input                                   Seg2UnSegErr3_in,
    input  [($clog2(`segment_width/8))-1:0] Seg2UnSegMty3_in,
    `endif
    `ifdef en_port2
    // Segment 4 input
    input                                   Seg2UnSegEna4_in,
    input  [`segment_width-1:0]             Seg2UnSegDat4_in,
    input                                   Seg2UnSegSop4_in,
    input                                   Seg2UnSegEop4_in,
    input                                   Seg2UnSegErr4_in,
    input  [($clog2(`segment_width/8))-1:0] Seg2UnSegMty4_in,
    // Segment 5 input
    input                                   Seg2UnSegEna5_in,
    input  [`segment_width-1:0]             Seg2UnSegDat5_in,
    input                                   Seg2UnSegSop5_in,
    input                                   Seg2UnSegEop5_in,
    input                                   Seg2UnSegErr5_in,
    input  [($clog2(`segment_width/8))-1:0] Seg2UnSegMty5_in,
    `endif
    `ifdef en_port3
    // Segment 6 input
    input                                   Seg2UnSegEna6_in,
    input  [`segment_width-1:0]             Seg2UnSegDat6_in,
    input                                   Seg2UnSegSop6_in,
    input                                   Seg2UnSegEop6_in,
    input                                   Seg2UnSegErr6_in,
    input  [($clog2(`segment_width/8))-1:0] Seg2UnSegMty6_in,
    // Segment 7 input
    input                                   Seg2UnSegEna7_in,
    input  [`segment_width-1:0]             Seg2UnSegDat7_in,
    input                                   Seg2UnSegSop7_in,
    input                                   Seg2UnSegEop7_in,
    input                                   Seg2UnSegErr7_in,
    input  [($clog2(`segment_width/8))-1:0]	Seg2UnSegMty7_in,
    `endif

    // Packet output interface - Unsegmented AXI Stream
	// AXI-0 is active for all valid configurations
    // Unsegmented AXIS-0 interface
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis0_pkt_out TDATA" *)
    output [`unseg_axis_w-1:0]        		m_axis0_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis0_pkt_out TKEEP" *)
    output [(`unseg_axis_w/8)-1:0]    		m_axis0_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis0_pkt_out TLAST" *)
    output                            		m_axis0_tlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis0_pkt_out TVALID" *)
    output                            		m_axis0_tvalid,
	(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis0_pkt_out TUSER" *)
    output                            		m_axis0_tuser,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis0_pkt_out TREADY" *)
    input                             		m_axis0_tready,

    `ifdef en_axis1
    // Unsegmented AXIS-1 interface
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis1_pkt_out TDATA" *)
    output [`unseg_axis_w-1:0]        		m_axis1_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis1_pkt_out TKEEP" *)
    output [(`unseg_axis_w/8)-1:0]    		m_axis1_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis1_pkt_out TLAST" *)
    output                            		m_axis1_tlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis1_pkt_out TVALID" *)
    output                            		m_axis1_tvalid,
	(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis1_pkt_out TUSER" *)
    output                            		m_axis1_tuser,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis1_pkt_out TREADY" *)
    input                             		m_axis1_tready,
    `endif

	`ifdef en_flow_control
	output wire buff_full,
	`else
	output wire inbuff_overflow,
	output wire inbuff_afull,
	`endif

	// Statistics
    `ifdef statistics_en
    `ifdef en_axis1
    output wire [63: 0] p1_pkt_out_cnt,
    output wire [63: 0] p1_err_pkt_out_cnt,
    output wire [63: 0] p1_pkt_out_byte_cnt,
	output wire [63: 0] p0_pkt_out_cnt,
	output wire [63: 0] p0_err_pkt_out_cnt,
    output wire [63: 0] p0_pkt_out_byte_cnt,
    `endif
    output wire [63: 0] total_pkt_in_cnt,
    output wire [63: 0] total_err_pkt_in_cnt,
    output wire [63: 0] total_pkt_in_byte_cnt,
    output wire [63: 0] total_pkt_out_cnt,
    output wire [63: 0] total_err_pkt_out_cnt,
    output wire [63: 0] total_pkt_out_byte_cnt,
    `endif

	`ifdef debug_en
	output wire error_broken_packet_out,
	output reg seg_rx_err_packet,
	`endif

    input wire rx_axis_tvalid_i
    );

//-----------------------------------------------------------------------------------------------------------------------

localparam P_MARK_DEBUG = "false";

// Derive local parameters

localparam seg_mty_w = $clog2(`segment_width/8);
localparam pkt_array_depth = `pktarray_depth;
localparam local_buff_depth = 32;
localparam max_pkt_burst_size = $ceil(`max_packet_size/((`pktarray_depth/2)*(`segment_width/8)));
localparam max_pkt_burst_size_p2 = $ceil($clog2(`max_packet_size));

`ifdef max_pkt_size_above_1k
	localparam pktarry_buff_depth = $ceil((2**(max_pkt_burst_size_p2+1))/((`pktarray_depth/2)*(`segment_width/8)));
	localparam pktarry_buff_pfull_thresh = pktarry_buff_depth - max_pkt_burst_size;
`else
	localparam pktarry_buff_depth = 32;
	localparam pktarry_buff_pfull_thresh = pktarry_buff_depth-7;
`endif

localparam in_buff_depth = pktarry_buff_depth/2;
localparam out_buff_depth = pktarry_buff_depth*4;
localparam out_buff_pfull_thresh = out_buff_depth - max_pkt_burst_size;

//-----------------------------------------------------------------------------------------------------------------------

wire [`num_segments-1:0] seg2unseg_val;
wire [`num_segments-1:0] seg2unseg_sop;
wire [`num_segments-1:0] seg2unseg_eop;
wire [`num_segments-1:0] seg2unseg_err;
wire [`segment_width-1:0] seg2unseg_dat [`num_segments-1:0];
wire [seg_mty_w-1:0] seg2unseg_mty [`num_segments-1:0];

assign seg2unseg_val[0] = Seg2UnSegEna0_in & rx_axis_tvalid_i; assign seg2unseg_sop[0] = Seg2UnSegSop0_in; assign seg2unseg_eop[0] = Seg2UnSegEop0_in; assign seg2unseg_err[0] = Seg2UnSegErr0_in; assign seg2unseg_dat[0] = Seg2UnSegDat0_in; assign seg2unseg_mty[0] = Seg2UnSegMty0_in;
assign seg2unseg_val[1] = Seg2UnSegEna1_in & rx_axis_tvalid_i; assign seg2unseg_sop[1] = Seg2UnSegSop1_in; assign seg2unseg_eop[1] = Seg2UnSegEop1_in; assign seg2unseg_err[1] = Seg2UnSegErr1_in; assign seg2unseg_dat[1] = Seg2UnSegDat1_in; assign seg2unseg_mty[1] = Seg2UnSegMty1_in;
`ifdef en_port1
assign seg2unseg_val[2] = Seg2UnSegEna2_in & rx_axis_tvalid_i; assign seg2unseg_sop[2] = Seg2UnSegSop2_in; assign seg2unseg_eop[2] = Seg2UnSegEop2_in; assign seg2unseg_err[2] = Seg2UnSegErr2_in; assign seg2unseg_dat[2] = Seg2UnSegDat2_in; assign seg2unseg_mty[2] = Seg2UnSegMty2_in;
assign seg2unseg_val[3] = Seg2UnSegEna3_in & rx_axis_tvalid_i; assign seg2unseg_sop[3] = Seg2UnSegSop3_in; assign seg2unseg_eop[3] = Seg2UnSegEop3_in; assign seg2unseg_err[3] = Seg2UnSegErr3_in; assign seg2unseg_dat[3] = Seg2UnSegDat3_in; assign seg2unseg_mty[3] = Seg2UnSegMty3_in;
`endif
`ifdef en_port2
assign seg2unseg_val[4] = Seg2UnSegEna4_in & rx_axis_tvalid_i; assign seg2unseg_sop[4] = Seg2UnSegSop4_in; assign seg2unseg_eop[4] = Seg2UnSegEop4_in; assign seg2unseg_err[4] = Seg2UnSegErr4_in; assign seg2unseg_dat[4] = Seg2UnSegDat4_in; assign seg2unseg_mty[4] = Seg2UnSegMty4_in;
assign seg2unseg_val[5] = Seg2UnSegEna5_in & rx_axis_tvalid_i; assign seg2unseg_sop[5] = Seg2UnSegSop5_in; assign seg2unseg_eop[5] = Seg2UnSegEop5_in; assign seg2unseg_err[5] = Seg2UnSegErr5_in; assign seg2unseg_dat[5] = Seg2UnSegDat5_in; assign seg2unseg_mty[5] = Seg2UnSegMty5_in;
`endif
`ifdef en_port3
assign seg2unseg_val[6] = Seg2UnSegEna6_in & rx_axis_tvalid_i; assign seg2unseg_sop[6] = Seg2UnSegSop6_in; assign seg2unseg_eop[6] = Seg2UnSegEop6_in; assign seg2unseg_err[6] = Seg2UnSegErr6_in; assign seg2unseg_dat[6] = Seg2UnSegDat6_in; assign seg2unseg_mty[6] = Seg2UnSegMty6_in;
assign seg2unseg_val[7] = Seg2UnSegEna7_in & rx_axis_tvalid_i; assign seg2unseg_sop[7] = Seg2UnSegSop7_in; assign seg2unseg_eop[7] = Seg2UnSegEop7_in; assign seg2unseg_err[7] = Seg2UnSegErr7_in; assign seg2unseg_dat[7] = Seg2UnSegDat7_in; assign seg2unseg_mty[7] = Seg2UnSegMty7_in;
`endif

wire aclk_axis_unseg;
wire aresetn_axis_unseg;

`ifdef independant_clk
    assign aclk_axis_unseg = aclk_axis_unseg_in;
    assign aresetn_axis_unseg = aresetn_axis_unseg_in;
`else
    assign aclk_axis_unseg = aclk_axis_seg_in;
    assign aresetn_axis_unseg = aresetn_axis_seg_in;
`endif

`ifdef debug_en

	always @ (posedge aclk_axis_unseg) begin
		seg_rx_err_packet	<= |(seg2unseg_err & seg2unseg_val);
	end

`endif

//-----------------------------------------------------------------------------------------------------------------------

//----------------- Input buffer

reg [`num_segments-1:0] seg2unseg_val_1;
reg [`num_segments-1:0] seg2unseg_sop_1;
reg [`num_segments-1:0] seg2unseg_eop_1;
reg [`num_segments-1:0] seg2unseg_err_1;
reg [`segment_width-1:0] seg2unseg_dat_1 [`num_segments-1:0];
reg [seg_mty_w-1:0] seg2unseg_mty_1 [`num_segments-1:0];

wire [`num_segments-1:0] seg2unseg_val_c;
wire [`num_segments-1:0] seg2unseg_sop_c;
wire [`num_segments-1:0] seg2unseg_eop_c;
wire [`num_segments-1:0] seg2unseg_err_c;
wire [(`segment_width*`num_segments)-1:0] seg2unseg_dat_c;
wire [(seg_mty_w*`num_segments)-1:0] seg2unseg_mty_c;

genvar a0;
generate
    for (a0=0; a0<`num_segments; a0=a0+1) begin
		assign seg2unseg_val_c[a0] = seg2unseg_val[a0];
		assign seg2unseg_sop_c[a0] = seg2unseg_sop[a0];
		assign seg2unseg_eop_c[a0] = seg2unseg_eop[a0];
		assign seg2unseg_err_c[a0] = seg2unseg_err[a0];
		assign seg2unseg_dat_c[((a0+1)*`segment_width)-1:a0*`segment_width] = seg2unseg_dat[a0];
		assign seg2unseg_mty_c[((a0+1)*seg_mty_w)-1:a0*seg_mty_w] = seg2unseg_mty[a0];
	end
endgenerate

wire wr_rst_busy;
wire rd_rst_busy;
wire seg_in_aempty;
wire seg_in_empty;
wire data_valid;
wire seg_inbuff_afull;
wire seg_inbuff_overflow;

wire ports_not_rdy;
wire [`num_axis_ports-1:0] port_unseg_out_pfull;

`ifdef independant_clk	// Input segmented intreface stream clock domain to unsegmented axis clock domain

wire [`num_segments-1:0] seg2unseg_val_cdc;
wire [`num_segments-1:0] seg2unseg_sop_cdc;
wire [`num_segments-1:0] seg2unseg_eop_cdc;
wire [`num_segments-1:0] seg2unseg_err_cdc;
wire [(`segment_width*`num_segments)-1:0] seg2unseg_dat_cdc;
wire [(seg_mty_w*`num_segments)-1:0] seg2unseg_mty_cdc;

xpm_fifo_async #(
    .CASCADE_HEIGHT(0),
    .CDC_SYNC_STAGES(3),
    .DOUT_RESET_VALUE("0"),
    .ECC_MODE("no_ecc"),
    .FIFO_MEMORY_TYPE("auto"),
    .FIFO_READ_LATENCY(2),
    .FIFO_WRITE_DEPTH(in_buff_depth),
    .FULL_RESET_VALUE(0),
    .PROG_EMPTY_THRESH(10),
    .PROG_FULL_THRESH(in_buff_depth-5),
    .RD_DATA_COUNT_WIDTH(1),
    .READ_DATA_WIDTH((`segment_width+seg_mty_w+4)*`num_segments),
    .READ_MODE("std"),
    .RELATED_CLOCKS(0),
    .SIM_ASSERT_CHK(0),
    .USE_ADV_FEATURES("1009"),
    .WAKEUP_TIME(0),
    .WRITE_DATA_WIDTH((`segment_width+seg_mty_w+4)*`num_segments),
    .WR_DATA_COUNT_WIDTH(1)
    )
xpm_fifo_async_seg_in (
    .almost_empty(seg_in_aempty),
    .almost_full(seg_inbuff_afull),
    .data_valid(data_valid),
    .dbiterr(),
    .dout({seg2unseg_val_cdc,seg2unseg_sop_cdc,seg2unseg_eop_cdc,seg2unseg_err_cdc,seg2unseg_mty_cdc,seg2unseg_dat_cdc}),
    .empty(seg_in_empty),
    .full(),
    .overflow(seg_inbuff_overflow),
    .prog_empty(),
    .prog_full(),
    .rd_data_count(),
    .rd_rst_busy(rd_rst_busy),
    .sbiterr(),
    .underflow(),
    .wr_ack(),
    .wr_data_count(),
    .wr_rst_busy(wr_rst_busy),
    .din({seg2unseg_val_c,seg2unseg_sop_c,seg2unseg_eop_c,seg2unseg_err_c,seg2unseg_mty_c,seg2unseg_dat_c}),
    .injectdbiterr(1'b0),
    .injectsbiterr(1'b0),
    .rd_clk(aclk_axis_unseg),
	`ifdef en_flow_control
	.rd_en(!seg_in_empty & !rd_rst_busy),
	`else
	.rd_en(!ports_not_rdy & !seg_in_empty & !rd_rst_busy),
	`endif
    .rst(!aresetn_axis_seg_in),
    .sleep(1'b0),
    .wr_clk(aclk_axis_seg_in),
    .wr_en(|seg2unseg_val_c & !wr_rst_busy)
    );

genvar i;
generate
    for (i=0; i<`num_segments; i=i+1) begin
		always @ (posedge aclk_axis_unseg) begin
			seg2unseg_val_1[i] <= seg2unseg_val_cdc[i] & data_valid;
			seg2unseg_sop_1[i] <= seg2unseg_sop_cdc[i];
			seg2unseg_eop_1[i] <= seg2unseg_eop_cdc[i];
			seg2unseg_err_1[i] <= seg2unseg_err_cdc[i];
			seg2unseg_dat_1[i] <= seg2unseg_dat_cdc[((i+1)*`segment_width)-1:i*`segment_width];
			seg2unseg_mty_1[i] <= seg2unseg_mty_cdc[((i+1)*seg_mty_w)-1:i*seg_mty_w];
		end
	end
endgenerate

`else	// Input segmented stream intreface and unsegmented axis interface runs at same clock domain

wire [`num_segments-1:0] seg2unseg_val_ibuf;
wire [`num_segments-1:0] seg2unseg_sop_ibuf;
wire [`num_segments-1:0] seg2unseg_eop_ibuf;
wire [`num_segments-1:0] seg2unseg_err_ibuf;
wire [(`segment_width*`num_segments)-1:0] seg2unseg_dat_ibuf;
wire [(seg_mty_w*`num_segments)-1:0] seg2unseg_mty_ibuf;

xpm_fifo_sync #(
    .CASCADE_HEIGHT(0),
    .DOUT_RESET_VALUE("0"),
    .ECC_MODE("no_ecc"),
    .FIFO_MEMORY_TYPE("auto"),
    .FIFO_READ_LATENCY(2),
    .FIFO_WRITE_DEPTH(in_buff_depth),
    .FULL_RESET_VALUE(0),
    .PROG_EMPTY_THRESH(10),
    .PROG_FULL_THRESH(in_buff_depth-5),
    .RD_DATA_COUNT_WIDTH(1),
    .READ_DATA_WIDTH((`segment_width+seg_mty_w+4)*`num_segments),
    .READ_MODE("std"),
    .SIM_ASSERT_CHK(0),
    .USE_ADV_FEATURES("1009"),
    .WAKEUP_TIME(0),
    .WRITE_DATA_WIDTH((`segment_width+seg_mty_w+4)*`num_segments),
    .WR_DATA_COUNT_WIDTH(1)
    )
xpm_fifo_sync_seg_in (
    .almost_empty(seg_in_aempty),
    .almost_full(seg_inbuff_afull),
    .data_valid(data_valid),
    .dbiterr(),
    .dout({seg2unseg_val_ibuf,seg2unseg_sop_ibuf,seg2unseg_eop_ibuf,seg2unseg_err_ibuf,seg2unseg_mty_ibuf,seg2unseg_dat_ibuf}),
    .empty(seg_in_empty),
    .full(),
    .overflow(seg_inbuff_overflow),
    .prog_empty(),
    .prog_full(),
    .rd_data_count(),
    .rd_rst_busy(rd_rst_busy),
    .sbiterr(),
    .underflow(),
    .wr_ack(),
    .wr_data_count(),
    .wr_rst_busy(wr_rst_busy),
    .din({seg2unseg_val_c,seg2unseg_sop_c,seg2unseg_eop_c,seg2unseg_err_c,seg2unseg_mty_c,seg2unseg_dat_c}),
    .injectdbiterr(1'b0),
    .injectsbiterr(1'b0),
	`ifdef en_flow_control
    .rd_en(!seg_in_empty & !rd_rst_busy),
	`else
	.rd_en(!ports_not_rdy & !seg_in_empty & !rd_rst_busy),
	`endif
    .rst(!aresetn_axis_unseg),
    .sleep(1'b0),
    .wr_clk(aclk_axis_unseg),
    .wr_en(|seg2unseg_val_c & !wr_rst_busy)
);

genvar j;
generate
    for (j=0; j < `num_segments; j = j+1) begin
        always @ (posedge aclk_axis_unseg) begin
			seg2unseg_val_1[j] <= seg2unseg_val_ibuf[j] & data_valid;
			seg2unseg_sop_1[j] <= seg2unseg_sop_ibuf[j];
			seg2unseg_eop_1[j] <= seg2unseg_eop_ibuf[j];
			seg2unseg_err_1[j] <= seg2unseg_err_ibuf[j];
			seg2unseg_dat_1[j] <= seg2unseg_dat_ibuf[((j+1)*`segment_width)-1:j*`segment_width];
			seg2unseg_mty_1[j] <= seg2unseg_mty_ibuf[((j+1)*seg_mty_w)-1:j*seg_mty_w];
        end
    end
endgenerate

`endif

assign inbuff_overflow = seg_inbuff_overflow;
assign inbuff_afull = seg_inbuff_afull;

//-----------------------------------------------------------------------------------------------------------------------

// Arbitrate packets to different channels based on number of output axis ports (applicable for 400G with 2 AXIS ports)

reg [`segment_width-1:0] pkt_data [`num_axis_ports-1:0] [`num_segments-1:0];
reg [seg_mty_w-1:0] pkt_mty [`num_axis_ports-1:0] [`num_segments-1:0];
reg [`num_segments-1:0] pkt_val [`num_axis_ports-1:0];
reg [`num_segments-1:0] pkt_eop [`num_axis_ports-1:0];
reg [`num_segments-1:0] pkt_err [`num_axis_ports-1:0];

`ifdef data_rate_400		// two output AXI stream ports available for 400G

genvar k, l;
generate
for (k=0; k < `num_axis_ports; k = k+1) begin
    for(l=0; l < `num_segments; l = l+1) begin
        always @ (posedge aclk_axis_unseg) begin
            pkt_data [k][l]  <= seg2unseg_dat_1[l];
            pkt_mty [k][l]   <= seg2unseg_mty_1[l];
            pkt_eop [k][l]   <= seg2unseg_eop_1[l];
            pkt_err [k][l]   <= seg2unseg_err_1[l];
        end
    end
end
endgenerate

// Probe output AXI ports (after power ON / system reset), to initialize the port pointer for port arbiter

reg [12:0] cnt_port_init;
reg port_init_q, port_init_qq;
wire port_init_rp;

reg [11:0] out_port_idle_cnt [`num_axis_ports-1:0];
reg [11:0] out_port_active_cnt [`num_axis_ports-1:0];
reg [`num_axis_ports-1:0] out_port_active_q;
reg [`num_axis_ports-1:0] out_port_idle_q;
wire [`num_axis_ports-1:0] out_port_active_rp;
wire [`num_axis_ports-1:0] out_port_idle_rp;
wire [`num_axis_ports-1:0] out_port_rdy;
reg [`num_axis_ports-1:0] out_port_not_active;

assign out_port_rdy[0] = m_axis0_tready;
`ifdef en_axis1
assign out_port_rdy[1] = m_axis1_tready;
`endif

reg only_port1_active, only_port0_active;

always @ (posedge aclk_axis_unseg) begin
	if (!aresetn_axis_unseg)
		cnt_port_init	<= 'd0;
	else if (cnt_port_init[12])
		cnt_port_init	<= cnt_port_init;
	else
		cnt_port_init	<= cnt_port_init + 1;
end

always @ (posedge aclk_axis_unseg) begin
	port_init_q		<= cnt_port_init[12];
	port_init_qq	<= port_init_q;
end

assign port_init_rp = port_init_q & ~port_init_qq;

genvar kk;

generate
	for (kk=0; kk < `num_axis_ports; kk = kk+1) begin
		always @ (posedge aclk_axis_unseg) begin
			out_port_active_q[kk]	<= out_port_active_cnt[kk][11];
			if (!aresetn_axis_unseg)
				out_port_active_cnt[kk]	<= 'd0;
			else if (out_port_idle_rp[kk])
				out_port_active_cnt[kk]	<= 'd0;
			else if (!out_port_rdy[kk])
				out_port_active_cnt[kk]	<= 'd0;
			else if (out_port_active_q[kk])
				out_port_active_cnt[kk]	<= out_port_active_cnt[kk];
			else
				out_port_active_cnt[kk]	<= out_port_active_cnt[kk] + 1;
		end

		assign out_port_active_rp[kk]	= out_port_active_cnt[kk][11] & ~out_port_active_q[kk];

		always @ (posedge aclk_axis_unseg) begin
			out_port_not_active[kk]	<= out_port_idle_cnt[kk][11];
			out_port_idle_q[kk]		<= out_port_idle_cnt[kk][11];
			if (!aresetn_axis_unseg)
				out_port_idle_cnt[kk]	<= 'd0;
			else if (out_port_active_rp[kk])
				out_port_idle_cnt[kk]	<= 'd0;
			else if (out_port_rdy[kk])
				out_port_idle_cnt[kk]	<= 'd0;
			else if (out_port_idle_q[kk])
				out_port_idle_cnt[kk]	<= out_port_idle_cnt[kk];
			else
				out_port_idle_cnt[kk]	<= out_port_idle_cnt[kk] + 1;
		end

		assign out_port_idle_rp[kk]	= out_port_idle_cnt[kk][11] & ~out_port_idle_q[kk];
	end
endgenerate

always @ (posedge aclk_axis_unseg) begin						// Update port status when input stream is not active
	if (!seg2unseg_val_1[0])
		if (out_port_not_active == 2'b01)
			only_port1_active	<= 1'b1;
		else
			only_port1_active	<= 1'b0;
	else
		only_port1_active	<= only_port1_active;
end

always @ (posedge aclk_axis_unseg) begin
	if (!seg2unseg_val_1[0])
		if (out_port_not_active == 2'b10)
			only_port0_active	<= 1'b1;
		else
			only_port0_active	<= 1'b0;
	else
		only_port0_active	<=	only_port0_active;
end

integer m, n;

reg [$clog2(`num_axis_ports)-1:0] cur_port;
reg nxt_pkt_vld;

`ifdef en_flow_control											// port arbitration with flow control

generate

always @ (posedge aclk_axis_unseg) begin
    if (!aresetn_axis_unseg) begin
        cur_port = 1'b0;
		nxt_pkt_vld = 1'b1;
        for (m=0; m < `num_axis_ports; m = m+1) begin
            for(n=0; n < `num_segments; n = n+1) begin
                pkt_val [m][n] <= 1'b0;
            end
        end
	end else if (port_init_rp) begin							// Initialize with the active port after power On/systen reset
		if (only_port1_active)
			cur_port = 1'b1;
		else
			cur_port = 1'b0;
    end else begin
        for (m=0; m < `num_axis_ports; m = m+1) begin
            for(n=0; n < `num_segments; n = n+1) begin
                pkt_val [m][n] <= 1'b0;
            end
        end
        for(n=0; n < `num_segments; n = n+1) begin
            pkt_val [cur_port][n] <= 1'b0;
            if(seg2unseg_val_1[n]) begin
				pkt_val [cur_port][n]   <= nxt_pkt_vld;
				if (seg2unseg_eop_1[n]) begin					// Arbitrate at current packet end
					if (only_port1_active) begin				// Only out port1 is active
						cur_port = 1'b1;
						if (port_unseg_out_pfull[1])			// tail drop; drop input packets when segment buffer is full
							nxt_pkt_vld = 1'b0;
						else
							nxt_pkt_vld = 1'b1;
					end else if (only_port0_active) begin		// Only out port0 is active
						cur_port = 1'b0;
						if (port_unseg_out_pfull[0])			// tail drop; drop input packets when segment buffer is full
							nxt_pkt_vld = 1'b0;
						else
							nxt_pkt_vld = 1'b1;
                    end else begin								// Both output ports are active
						if (cur_port == (`num_axis_ports-1))  begin
							if (port_unseg_out_pfull[0]) begin
								cur_port = 1'b1;
								if (port_unseg_out_pfull[1])	// tail drop; drop input packets when segment buffer is full
									nxt_pkt_vld = 1'b0;
								else
									nxt_pkt_vld = 1'b1;
							end else begin
								cur_port = 1'b0;
								nxt_pkt_vld = 1'b1;
							end
						end else begin
							if (port_unseg_out_pfull[1]) begin
								cur_port = 1'b0;
								if (port_unseg_out_pfull[0])	// tail drop; drop input packets when segment buffer is full
									nxt_pkt_vld = 1'b0;
								else
									nxt_pkt_vld = 1'b1;
							end else begin
								cur_port = 1'b1;
								nxt_pkt_vld = 1'b1;
							end
						end
					end
                end
            end
        end
    end
end
endgenerate

assign buff_full = |port_unseg_out_pfull;

`else															// port arbitration without flow control

generate

always @ (posedge aclk_axis_unseg) begin
    if (!aresetn_axis_unseg) begin
        cur_port = 1'b0;
        for (m=0; m < `num_axis_ports; m = m+1) begin
            for(n=0; n < `num_segments; n = n+1) begin
                pkt_val [m][n] <= 1'b0;
            end
        end
	end else if (port_init_rp) begin							// Initialize with the active port after power On/systen reset
		if (only_port1_active)
			cur_port = 1'b1;
		else
			cur_port = 1'b0;
    end else begin
        for (m=0; m < `num_axis_ports; m = m+1) begin
            for(n=0; n < `num_segments; n = n+1) begin
                pkt_val [m][n] <= 1'b0;
            end
        end
        for(n=0; n < `num_segments; n = n+1) begin
            pkt_val [cur_port][n] <= 1'b0;
            if(seg2unseg_val_1[n]) begin
				pkt_val [cur_port][n]   <= 1'b1;
				if (seg2unseg_eop_1[n]) begin
					if (only_port1_active) begin
						cur_port = 1'b1;
					end else if (only_port0_active) begin
						cur_port = 1'b0;
                    end else begin
						if (cur_port == (`num_axis_ports-1))  begin
							if (port_unseg_out_pfull[0]) begin
								cur_port = 1'b1;
							end else
								cur_port = 1'b0;
						end else begin
							if (port_unseg_out_pfull[1]) begin
								cur_port = 1'b0;
							end else
								cur_port = 1'b1;
						end
					end
                end
            end
        end
    end
end
endgenerate

`endif

`else		// data rate 100 or 200 Gbps, only one output AXI stream port is available

`ifdef en_flow_control

genvar k, l;
generate
for (k=0; k < `num_axis_ports; k = k+1) begin
    for(l=0; l < `num_segments; l = l+1) begin
        always @ (posedge aclk_axis_unseg) begin
            pkt_data [k][l]  <= seg2unseg_dat_1[l];
            pkt_mty [k][l]   <= seg2unseg_mty_1[l];
            pkt_eop [k][l]   <= seg2unseg_eop_1[l];
            pkt_err [k][l]   <= seg2unseg_err_1[l];
        end
    end
end
endgenerate

reg [$clog2(`num_axis_ports)-1:0] cur_port;
reg nxt_pkt_vld;

integer m, n;

generate
    always @ (posedge aclk_axis_unseg) begin
		if (!aresetn_axis_unseg) begin
			nxt_pkt_vld = 1'b1;
			cur_port	<= 1'b0;
        for (m=0; m < `num_axis_ports; m = m+1) begin
            for(n=0; n < `num_segments; n = n+1) begin
                pkt_val [m][n] <= 1'b0;
				cur_port	<= 1'b0;
            end
        end
		end else begin
        for (m=0; m < `num_axis_ports; m = m+1) begin
            for(n=0; n < `num_segments; n = n+1) begin
                pkt_val [m][n] <= 1'b0;
            end
        end
			for(n=0; n < `num_segments; n = n+1) begin
				if(seg2unseg_val_1[n]) begin
					pkt_val [cur_port][n]	<= nxt_pkt_vld;
					if (seg2unseg_eop_1[n])
						if (port_unseg_out_pfull[0])		// tail drop; drop input packets when segment buffer is full
							nxt_pkt_vld = 1'b0;
						else
							nxt_pkt_vld = 1'b1;
				end
			end
		end
	end
endgenerate

assign buff_full = port_unseg_out_pfull[0];

`else

genvar k,l;

generate
for (k=0; k < `num_axis_ports; k = k+1) begin
    for(l=0; l < `num_segments; l = l+1) begin
        always @ (posedge aclk_axis_unseg) begin
            pkt_data [k][l]  <= seg2unseg_dat_1[l];
            pkt_mty [k][l]   <= seg2unseg_mty_1[l];
            pkt_eop [k][l]   <= seg2unseg_eop_1[l];
            pkt_err [k][l]   <= seg2unseg_err_1[l];
            pkt_val [k][l]   <= seg2unseg_val_1[l];
        end
    end
end
endgenerate

`endif

`endif

reg [`segment_width-1:0] pkt_data1 [`num_axis_ports-1:0] [`num_segments-1:0];
reg [seg_mty_w-1:0] pkt_mty1 [`num_axis_ports-1:0] [`num_segments-1:0];
reg [`num_segments-1:0] pkt_val1 [`num_axis_ports-1:0];
reg [`num_segments-1:0] pkt_eop1 [`num_axis_ports-1:0];
reg [`num_segments-1:0] pkt_err1 [`num_axis_ports-1:0];

reg [`segment_width-1:0] pkt_data2 [`num_axis_ports-1:0] [`num_segments-1:0];
reg [seg_mty_w-1:0] pkt_mty2 [`num_axis_ports-1:0] [`num_segments-1:0];
reg [`num_segments-1:0] pkt_val2 [`num_axis_ports-1:0];
reg [`num_segments-1:0] pkt_eop2 [`num_axis_ports-1:0];
reg [`num_segments-1:0] pkt_err2 [`num_axis_ports-1:0];

genvar o, p;
generate
for (o=0; o < `num_axis_ports; o = o+1) begin
    for(p=0; p < `num_segments; p = p+1) begin
        always @ (posedge aclk_axis_unseg) begin
            pkt_data1[o][p]	<= pkt_data [o][p];
            pkt_mty1 [o][p] <= pkt_mty  [o][p];
            pkt_eop1 [o][p] <= pkt_eop  [o][p];
            pkt_err1 [o][p] <= pkt_err  [o][p];
            pkt_val1 [o][p] <= pkt_val  [o][p];
        end
		always @ (posedge aclk_axis_unseg) begin
            pkt_data2[o][p]	<= pkt_data1 [o][p];
            pkt_mty2 [o][p] <= pkt_mty1  [o][p];
            pkt_eop2 [o][p] <= pkt_eop1  [o][p];
            pkt_err2 [o][p] <= pkt_err1  [o][p];
            pkt_val2 [o][p] <= pkt_val1  [o][p];
        end
    end
end
endgenerate

reg [`segment_width-1:0] pkt_tdata [`num_axis_ports-1:0] [(pkt_array_depth/2)-1:0];
reg [(`segment_width/8)-1:0] pkt_tkeep [`num_axis_ports-1:0] [(pkt_array_depth/2)-1:0];
reg [(pkt_array_depth/2)-1:0] pkt_tvalid [`num_axis_ports-1:0];
reg [(pkt_array_depth/2)-1:0] pkt_tuser [`num_axis_ports-1:0];
reg [(pkt_array_depth/2)-1:0] pkt_tlast [`num_axis_ports-1:0];
reg [(`segment_width*(pkt_array_depth/2))-1:0] axis_tdata_buf_in [`num_axis_ports-1:0];
reg [((`segment_width/8)*(pkt_array_depth/2))-1:0] axis_tkeep_buf_in [`num_axis_ports-1:0];
reg [`num_axis_ports-1:0] axis_tvalid_buf_in;
reg [`num_axis_ports-1:0] axis_tlast_buf_in;
reg [`num_axis_ports-1:0] axis_tuser_buf_in;
wire [`num_axis_ports-1:0] axis_tready_buf_in;
reg [`segment_width-1:0] pkt_data_out_0 [`num_axis_ports-1:0] [(pkt_array_depth/2)-1:0];
reg [seg_mty_w-1:0] pkt_mty_out_0 [`num_axis_ports-1:0] [(pkt_array_depth/2)-1:0];
reg [(pkt_array_depth/2)-1:0] pkt_val_out_0 [`num_axis_ports-1:0];
reg [(pkt_array_depth/2)-1:0] pkt_eop_out_0 [`num_axis_ports-1:0];
reg [(pkt_array_depth/2)-1:0] pkt_err_out_0 [`num_axis_ports-1:0];

//-----------------------------------------------------------------------------------------------------------------------

//----------------- Segment array

// pack the packet segments in array (to align with unsegmented axis stream data width)

wire [`num_axis_ports-1:0] outbuff_pfull;

`ifdef data_rate_400

reg [`segment_width-1:0] pkt_data_array [`num_axis_ports-1:0] [pkt_array_depth-1:0];
reg [seg_mty_w-1:0] pkt_mty_array [`num_axis_ports-1:0] [pkt_array_depth-1:0];
reg [pkt_array_depth-1:0] pkt_val_array0 [`num_axis_ports-1:0];
reg [pkt_array_depth-1:0] pkt_val_array00 [`num_axis_ports-1:0];
reg [pkt_array_depth-1:0] pkt_val_array1 [`num_axis_ports-1:0];
reg [pkt_array_depth-1:0] pkt_val_array2 [`num_axis_ports-1:0];
reg [pkt_array_depth-1:0] pkt_val_array [`num_axis_ports-1:0];
reg [pkt_array_depth-1:0] pkt_eop_array [`num_axis_ports-1:0];
reg [pkt_array_depth-1:0] pkt_err_array [`num_axis_ports-1:0];

reg [$clog2(pkt_array_depth)-1:0] pkt_array_ptr [`num_axis_ports-1:0];
reg [$clog2(pkt_array_depth)-1:0] pkt_seg_sel_reg [`num_axis_ports-1:0] [pkt_array_depth-1:0];
reg [$clog2(pkt_array_depth)-1:0] pkt_seg_sel_reg1 [`num_axis_ports-1:0] [pkt_array_depth-1:0];

wire [`num_axis_ports-1:0] wr_en_c0;
wire [`num_axis_ports-1:0] wr_en_c1;

reg [`num_axis_ports-1:0] wr_en_0;
reg [`num_axis_ports-1:0] wr_en_1;

genvar q;
integer r, rr;
generate
for (q=0; q < `num_axis_ports; q = q+1) begin
    always @ (posedge aclk_axis_unseg) begin
        if (!aresetn_axis_unseg) begin
            pkt_array_ptr[q] = 0;
            for(r=0; r < pkt_array_depth/2; r = r+1) begin
                pkt_val_array0 [q][r]	<= 1'b0;
                pkt_val_array1 [q][r] 	<= 1'b0;
                pkt_seg_sel_reg[q][r] 	<= 'd0;
            end
            for(rr=pkt_array_depth/2; rr < pkt_array_depth; rr = rr+1) begin
                pkt_val_array0 [q][rr] 	<= 1'b0;
                pkt_val_array1 [q][rr] 	<= 1'b0;
                pkt_seg_sel_reg[q][rr] 	<= 'd0;
            end
        end else begin
                for(r=0; r < pkt_array_depth/2; r = r+1) begin
                    pkt_val_array0 [q][r]		<= 1'b0;
                end
                for(rr=pkt_array_depth/2; rr < pkt_array_depth; rr = rr+1) begin
                    pkt_val_array0 [q][rr] 		<= 1'b0;
                end
                if (wr_en_c0[q]) begin
                    for(rr=0; rr < pkt_array_depth/2; rr = rr+1) begin
                        pkt_val_array1 [q][rr]	<= 1'b0;
                    end
                end
                if (wr_en_c1[q]) begin
                    for(rr=pkt_array_depth/2; rr < pkt_array_depth; rr = rr+1) begin
                        pkt_val_array1 [q][rr]	<= 1'b0;
                    end
                end
                for(r=0; r < `num_segments; r = r+1) begin
                    if (pkt_val[q][r]) begin
                        pkt_val_array0 [q][pkt_array_ptr[q]]	<= 1'b1;
                        pkt_val_array1 [q][pkt_array_ptr[q]] 	<= 1'b1;
                        pkt_seg_sel_reg[q][pkt_array_ptr[q]] 	<= r;
						if (pkt_eop[q][r]) begin
                            if (pkt_array_ptr[q][$clog2(pkt_array_depth)-1] == 1)
                                pkt_array_ptr[q]	= 0;
                            else
                                pkt_array_ptr[q] 	= pkt_array_depth/2;
                        end else
                            pkt_array_ptr[q]	= pkt_array_ptr[q] + 1;
                    end
                end
        end
    end
end
endgenerate

genvar s, array_depth;
generate
for (s=0; s < `num_axis_ports; s = s+1) begin
    always @ (posedge aclk_axis_unseg) begin
        pkt_val_array2[s]	<= pkt_val_array1[s];
        pkt_val_array[s]	<= pkt_val_array2[s];
        pkt_val_array00[s]	<= pkt_val_array0[s];
    end
	for (array_depth=0; array_depth < pkt_array_depth; array_depth = array_depth+1) begin
        always @ (posedge aclk_axis_unseg) begin
			pkt_seg_sel_reg1[s][array_depth]	<= pkt_seg_sel_reg[s][array_depth];
		end
	end
    for (array_depth=0; array_depth < pkt_array_depth; array_depth = array_depth+1) begin
        always @ (posedge aclk_axis_unseg) begin
            if (!aresetn_axis_unseg) begin
                pkt_eop_array[s][array_depth] 	<= 1'b0;
                pkt_err_array[s][array_depth] 	<= 1'b0;
                pkt_mty_array[s][array_depth] 	<= 'd0;
                pkt_data_array[s][array_depth]	<= 'd0;
            end else begin
                if (pkt_val_array00[s][array_depth]) begin
                    pkt_eop_array[s][array_depth]   <= pkt_eop2 [s][pkt_seg_sel_reg1[s][array_depth]];
                    pkt_err_array[s][array_depth]   <= pkt_err2 [s][pkt_seg_sel_reg1[s][array_depth]];
                    pkt_mty_array[s][array_depth]   <= pkt_mty2 [s][pkt_seg_sel_reg1[s][array_depth]];
                    pkt_data_array[s][array_depth]  <= pkt_data2[s][pkt_seg_sel_reg1[s][array_depth]];
                end else begin
                    pkt_eop_array[s][array_depth] 	<= 1'b0;
                    pkt_err_array[s][array_depth] 	<= 1'b0;
                end
            end
        end
    end
end
endgenerate

//-----------------------------------------------------------------------------------------------------------------------

//----------------- Buffering packed segments

reg [`num_axis_ports-1:0] rd_en_0;
reg [`num_axis_ports-1:0] rd_en_1;

genvar t;

generate
for (t=0; t<`num_axis_ports; t=t+1) begin
    assign wr_en_c0[t] = pkt_val_array1[t][(pkt_array_depth/2)-1] | (|pkt_eop_array[t][(pkt_array_depth/2)-1:0]);
    assign wr_en_c1[t] = pkt_val_array1[t][pkt_array_depth-1] | (|pkt_eop_array[t][pkt_array_depth-1:(pkt_array_depth/2)]);
    always @ (posedge aclk_axis_unseg) begin
        if (!aresetn_axis_unseg) begin
            wr_en_0[t] <= 1'b0;
            wr_en_1[t] <= 1'b0;
        end else begin
            wr_en_0[t] <= pkt_val_array[t][(pkt_array_depth/2)-1] | (|pkt_eop_array[t][(pkt_array_depth/2)-1:0]);
            wr_en_1[t] <= pkt_val_array[t][pkt_array_depth-1] | (|pkt_eop_array[t][pkt_array_depth-1:(pkt_array_depth/2)]);
        end
    end
end
endgenerate

reg [`segment_width-1:0] pkt_data_buf_in_p0 [`num_axis_ports-1:0] [(pkt_array_depth/2)-1:0];
reg [seg_mty_w-1:0] pkt_mty_buf_in_p0 [`num_axis_ports-1:0] [(pkt_array_depth/2)-1:0];
reg [(pkt_array_depth/2)-1:0] pkt_val_buf_in_p0 [`num_axis_ports-1:0];
reg [(pkt_array_depth/2)-1:0] pkt_eop_buf_in_p0 [`num_axis_ports-1:0];
reg [(pkt_array_depth/2)-1:0] pkt_err_buf_in_p0 [`num_axis_ports-1:0];
reg [`segment_width-1:0] pkt_data_buf_in_p1 [`num_axis_ports-1:0] [(pkt_array_depth/2)-1:0];
reg [seg_mty_w-1:0] pkt_mty_buf_in_p1 [`num_axis_ports-1:0] [(pkt_array_depth/2)-1:0];
reg [(pkt_array_depth/2)-1:0] pkt_val_buf_in_p1 [`num_axis_ports-1:0];
reg [(pkt_array_depth/2)-1:0] pkt_eop_buf_in_p1 [`num_axis_ports-1:0];
reg [(pkt_array_depth/2)-1:0] pkt_err_buf_in_p1 [`num_axis_ports-1:0];

wire [(pkt_array_depth/2)-1:0] unseg_buf1_aempty_0 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_buf1_aempty_1 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_buf1_empty_0 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_buf1_empty_1 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_data_valid_0 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_data_valid_1 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_rd_rst_busy_0 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_rd_rst_busy_1 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_wr_rst_busy_0 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_wr_rst_busy_1 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_out_buf1_pfull_0 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_out_buf1_pfull_1 [`num_axis_ports-1:0];

wire [`segment_width-1:0] pkt_data_buf_out_p0 [`num_axis_ports-1:0] [(pkt_array_depth/2)-1:0];
wire [seg_mty_w-1:0] pkt_mty_buf_out_p0 [`num_axis_ports-1:0] [(pkt_array_depth/2)-1:0];
wire [(pkt_array_depth/2)-1:0] pkt_val_buf_out_p0 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] pkt_eop_buf_out_p0 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] pkt_err_buf_out_p0 [`num_axis_ports-1:0];
wire [`segment_width-1:0] pkt_data_buf_out_p1 [`num_axis_ports-1:0] [(pkt_array_depth/2)-1:0];
wire [seg_mty_w-1:0] pkt_mty_buf_out_p1 [`num_axis_ports-1:0] [(pkt_array_depth/2)-1:0];
wire [(pkt_array_depth/2)-1:0] pkt_val_buf_out_p1 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] pkt_eop_buf_out_p1 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] pkt_err_buf_out_p1 [`num_axis_ports-1:0];

genvar u,v;

generate
for (u=0; u<`num_axis_ports; u=u+1) begin
    for (v=0; v<(pkt_array_depth/2); v=v+1) begin
        always @ (posedge aclk_axis_unseg) begin
            if (!aresetn_axis_unseg) begin
                pkt_val_buf_in_p0[u][v] 	<= 1'b0;
                pkt_eop_buf_in_p0[u][v] 	<= 1'b0;
                pkt_err_buf_in_p0[u][v] 	<= 1'b0;
                pkt_val_buf_in_p1[u][v] 	<= 1'b0;
                pkt_eop_buf_in_p1[u][v] 	<= 1'b0;
                pkt_err_buf_in_p1[u][v] 	<= 1'b0;
            end else begin
                pkt_val_buf_in_p0[u][v]     <= pkt_val_array[u][v];
                pkt_data_buf_in_p0[u][v]    <= pkt_data_array[u][v];
                pkt_mty_buf_in_p0[u][v]     <= pkt_mty_array[u][v];
                pkt_eop_buf_in_p0[u][v]     <= pkt_eop_array[u][v];
                pkt_err_buf_in_p0[u][v]     <= pkt_err_array[u][v];
                pkt_val_buf_in_p1[u][v]     <= pkt_val_array[u][v+(pkt_array_depth/2)];
                pkt_data_buf_in_p1[u][v]    <= pkt_data_array[u][v+(pkt_array_depth/2)];
                pkt_mty_buf_in_p1[u][v]     <= pkt_mty_array[u][v+(pkt_array_depth/2)];
                pkt_eop_buf_in_p1[u][v]     <= pkt_eop_array[u][v+(pkt_array_depth/2)];
                pkt_err_buf_in_p1[u][v]     <= pkt_err_array[u][v+(pkt_array_depth/2)];
            end
        end
    end
end
endgenerate

genvar w,x;
generate
for (w=0; w<`num_axis_ports; w=w+1) begin
    for (x=0; x<(pkt_array_depth/2); x=x+1) begin
        xpm_fifo_sync #(
           .CASCADE_HEIGHT(0),
           .DOUT_RESET_VALUE("0"),
           .ECC_MODE("no_ecc"),
           .FIFO_MEMORY_TYPE("auto"),
           .FIFO_READ_LATENCY(1),
           .FIFO_WRITE_DEPTH(pktarry_buff_depth),
           .FULL_RESET_VALUE(0),
           .PROG_EMPTY_THRESH(10),
           .PROG_FULL_THRESH(pktarry_buff_pfull_thresh),
           .RD_DATA_COUNT_WIDTH(1),
           .READ_DATA_WIDTH(`segment_width+seg_mty_w+3),
           .READ_MODE("std"),
           .SIM_ASSERT_CHK(0),
           .USE_ADV_FEATURES("1002"),
           .WAKEUP_TIME(0),
           .WRITE_DATA_WIDTH(`segment_width+seg_mty_w+3),
           .WR_DATA_COUNT_WIDTH(1)
        )
        xpm_fifo_sync_unseg_stage1_p0 (
           .almost_empty(unseg_buf1_aempty_0[w][x]),
           .almost_full(),
           .data_valid(unseg_data_valid_0[w][x]),
           .dbiterr(),
           .dout({pkt_mty_buf_out_p0[w][x],pkt_err_buf_out_p0[w][x],pkt_eop_buf_out_p0[w][x],pkt_val_buf_out_p0[w][x],pkt_data_buf_out_p0[w][x]}),
           .empty(unseg_buf1_empty_0[w][x]),
           .full(),
           .overflow(),
           .prog_empty(),
           .prog_full(unseg_out_buf1_pfull_0[w][x]),
           .rd_data_count(),
           .rd_rst_busy(unseg_rd_rst_busy_0[w][x]),
           .sbiterr(),
           .underflow(),
           .wr_ack(),
           .wr_data_count(),
           .wr_rst_busy(unseg_wr_rst_busy_0[w][x]),
           .din({pkt_mty_buf_in_p0[w][x],pkt_err_buf_in_p0[w][x],pkt_eop_buf_in_p0[w][x],pkt_val_buf_in_p0[w][x],pkt_data_buf_in_p0[w][x]}),
           .injectdbiterr(1'b0),
           .injectsbiterr(1'b0),
		   .rd_en(rd_en_0[w] & !outbuff_pfull[w] & !unseg_data_valid_0[w][x]),
           .rst(!aresetn_axis_unseg),
           .sleep(1'b0),
           .wr_clk(aclk_axis_unseg),
           .wr_en(wr_en_0[w] & !unseg_wr_rst_busy_0[w][x])
        );

        xpm_fifo_sync #(
           .CASCADE_HEIGHT(0),
           .DOUT_RESET_VALUE("0"),
           .ECC_MODE("no_ecc"),
           .FIFO_MEMORY_TYPE("auto"),
           .FIFO_READ_LATENCY(1),
           .FIFO_WRITE_DEPTH(pktarry_buff_depth),
           .FULL_RESET_VALUE(0),
           .PROG_EMPTY_THRESH(10),
           .PROG_FULL_THRESH(pktarry_buff_pfull_thresh),
           .RD_DATA_COUNT_WIDTH(1),
           .READ_DATA_WIDTH(`segment_width+seg_mty_w+3),
           .READ_MODE("std"),
           .SIM_ASSERT_CHK(0),
           .USE_ADV_FEATURES("1002"),
           .WAKEUP_TIME(0),
           .WRITE_DATA_WIDTH(`segment_width+seg_mty_w+3),
           .WR_DATA_COUNT_WIDTH(1)
        )
        xpm_fifo_sync_unseg_stage1_p1 (
           .almost_empty(unseg_buf1_aempty_1[w][x]),
           .almost_full(),
           .data_valid(unseg_data_valid_1[w][x]),
           .dbiterr(),
           .dout({pkt_mty_buf_out_p1[w][x],pkt_err_buf_out_p1[w][x],pkt_eop_buf_out_p1[w][x],pkt_val_buf_out_p1[w][x],pkt_data_buf_out_p1[w][x]}),
           .empty(unseg_buf1_empty_1[w][x]),
           .full(),
           .overflow(),
           .prog_empty(),
           .prog_full(unseg_out_buf1_pfull_1[w][x]),
           .rd_data_count(),
           .rd_rst_busy(unseg_rd_rst_busy_1[w][x]),
           .sbiterr(),
           .underflow(),
           .wr_ack(),
           .wr_data_count(),
           .wr_rst_busy(unseg_wr_rst_busy_1[w][x]),
           .din({pkt_mty_buf_in_p1[w][x],pkt_err_buf_in_p1[w][x],pkt_eop_buf_in_p1[w][x],pkt_val_buf_in_p1[w][x],pkt_data_buf_in_p1[w][x]}),
           .injectdbiterr(1'b0),
           .injectsbiterr(1'b0),
		   .rd_en(rd_en_1[w] & !outbuff_pfull[w] & !unseg_data_valid_1[w][x]),
           .rst(!aresetn_axis_unseg),
           .sleep(1'b0),
           .wr_clk(aclk_axis_unseg),
           .wr_en(wr_en_1[w] & !unseg_wr_rst_busy_1[w][x])
        );
    end
	assign port_unseg_out_pfull[w] = (|unseg_out_buf1_pfull_0[w]) | (|unseg_out_buf1_pfull_1[w]);
end
endgenerate

assign ports_not_rdy = &port_unseg_out_pfull;

//-----------------------------------------------------------------------------------------------------------------------

//----------------- Packet readout / array port arbitration

reg [`num_axis_ports-1:0] port_sel;
reg [`num_axis_ports-1:0] port_sel_1;

genvar y;

generate
for (y=0; y<`num_axis_ports; y=y+1) begin
    always @ (posedge aclk_axis_unseg) begin
        if (!aresetn_axis_unseg) begin
            rd_en_0[y]		<= 1'b0;
            rd_en_1[y] 		<= 1'b0;
            port_sel[y] 	<= 1'b0;
            port_sel_1[y] 	<= 1'b0;
        end else if (!outbuff_pfull[y]) begin
            rd_en_0[y]  	<= 1'b0;
            rd_en_1[y]  	<= 1'b0;
            port_sel_1[y] 	<= port_sel[y];
            if (port_sel[y]) begin
                rd_en_0[y]	<= 1'b0;
                if (!(|unseg_buf1_empty_1[y]) && !(|unseg_rd_rst_busy_1[y])) begin
                    rd_en_1[y]	<= 1'b1;
                    port_sel[y] <= 1'b0;
                end else begin
                    rd_en_1[y]  <= 1'b0;
                    port_sel[y] <= port_sel[y];
                end
            end else begin
                rd_en_1[y]	<= 1'b0;
                if (!(|unseg_buf1_empty_0[y]) && !(|unseg_rd_rst_busy_0[y])) begin
                    rd_en_0[y]	<= 1'b1;
                    port_sel[y] <= 1'b1;
                end else begin
                    rd_en_0[y]  <= 1'b0;
                    port_sel[y] <= port_sel[y];
                end
            end
        end
    end
end
endgenerate

genvar z, zz;

generate
for (z=0; z<`num_axis_ports; z=z+1) begin  :packet_out_mux
    for (zz=0; zz<(pkt_array_depth/2); zz=zz+1) begin
        always @ (posedge aclk_axis_unseg) begin
            if (!aresetn_axis_unseg) begin
                pkt_val_out_0[z][zz] 	<= 1'b0;
                pkt_mty_out_0[z][zz] 	<= {seg_mty_w{1'b1}};
                pkt_eop_out_0[z][zz] 	<= 1'b0;
                pkt_err_out_0[z][zz] 	<= 1'b0;
            end else begin
				pkt_val_out_0[z][zz]   	<= 1'b0;
                if (port_sel_1[z]) begin
                    pkt_val_out_0[z][zz]    <= pkt_val_buf_out_p0[z][zz] & unseg_data_valid_0[z][zz];
                    pkt_mty_out_0[z][zz]    <= pkt_mty_buf_out_p0[z][zz];
                    pkt_eop_out_0[z][zz]    <= pkt_eop_buf_out_p0[z][zz];
                    pkt_err_out_0[z][zz]    <= pkt_err_buf_out_p0[z][zz];
                    pkt_data_out_0[z][zz]   <= pkt_data_buf_out_p0[z][zz];
                end else begin
                    pkt_val_out_0[z][zz]    <= pkt_val_buf_out_p1[z][zz] & unseg_data_valid_1[z][zz];
                    pkt_mty_out_0[z][zz]    <= pkt_mty_buf_out_p1[z][zz];
                    pkt_eop_out_0[z][zz]    <= pkt_eop_buf_out_p1[z][zz];
                    pkt_err_out_0[z][zz]    <= pkt_err_buf_out_p1[z][zz];
                    pkt_data_out_0[z][zz]   <= pkt_data_buf_out_p1[z][zz];
                end
            end
        end
    end
end
endgenerate

`else 			// 100G or 200G

reg [`segment_width-1:0] pktout_data_array [`num_axis_ports-1:0] [pkt_array_depth*2-1:0];
reg [seg_mty_w-1:0] pktout_mty_array [`num_axis_ports-1:0] [pkt_array_depth*2-1:0];
reg [pkt_array_depth*2-1:0] pktout_val_array0 [`num_axis_ports-1:0];
reg [pkt_array_depth*2-1:0] pktout_val_array00 [`num_axis_ports-1:0];
reg [pkt_array_depth*2-1:0] pktout_val_array1 [`num_axis_ports-1:0];
reg [pkt_array_depth*2-1:0] pktout_val_array2 [`num_axis_ports-1:0];
reg [pkt_array_depth*2-1:0] pktout_val_array [`num_axis_ports-1:0];
reg [pkt_array_depth*2-1:0] pktout_eop_array [`num_axis_ports-1:0];
reg [pkt_array_depth*2-1:0] pktout_err_array [`num_axis_ports-1:0];

reg [$clog2(pkt_array_depth*2)-1:0] pktout_array_ptr [`num_axis_ports-1:0];
reg [$clog2(pkt_array_depth)-1:0] pktout_seg_sel_reg [`num_axis_ports-1:0] [pkt_array_depth*2-1:0];
reg [$clog2(pkt_array_depth)-1:0] pktout_seg_sel_reg1 [`num_axis_ports-1:0] [pkt_array_depth*2-1:0];

wire [`num_axis_ports-1:0] wr_en_c0;
wire [`num_axis_ports-1:0] wr_en_c1;
wire [`num_axis_ports-1:0] wr_en_c2;
wire [`num_axis_ports-1:0] wr_en_c3;

reg [`num_axis_ports-1:0] wr_en0;
reg [`num_axis_ports-1:0] wr_en1;
reg [`num_axis_ports-1:0] wr_en2;
reg [`num_axis_ports-1:0] wr_en3;

genvar q;
integer r, rr;
generate
for (q=0; q < `num_axis_ports; q = q+1) begin
    always @ (posedge aclk_axis_unseg) begin
        if (!aresetn_axis_unseg) begin
            pktout_array_ptr[q]	= 0;
            for(r=0; r < pkt_array_depth/2; r = r+1) begin
                pktout_val_array0 [q][r]						<= 1'b0;
                pktout_val_array1 [q][r] 						<= 1'b0;
                pktout_seg_sel_reg[q][r] 						<= 'd0;
                pktout_val_array0 [q][r+pkt_array_depth/2]		<= 1'b0;
                pktout_val_array1 [q][r+pkt_array_depth/2] 		<= 1'b0;
                pktout_seg_sel_reg[q][r+pkt_array_depth/2] 		<= 'd0;
                pktout_val_array0 [q][r+(pkt_array_depth/2)*2]	<= 1'b0;
                pktout_val_array1 [q][r+(pkt_array_depth/2)*2] 	<= 1'b0;
                pktout_seg_sel_reg[q][r+(pkt_array_depth/2)*2] 	<= 'd0;
                pktout_val_array0 [q][r+(pkt_array_depth/2)*3] 	<= 1'b0;
                pktout_val_array1 [q][r+(pkt_array_depth/2)*3] 	<= 1'b0;
                pktout_seg_sel_reg[q][r+(pkt_array_depth/2)*3] 	<= 'd0;
            end
        end else begin
                for(r=0; r < pkt_array_depth/2; r = r+1) begin
                    pktout_val_array0 [q][r] 						<= 1'b0;
                    pktout_val_array0 [q][r+pkt_array_depth/2] 		<= 1'b0;
					pktout_val_array0 [q][r+(pkt_array_depth/2)*2] 	<= 1'b0;
					pktout_val_array0 [q][r+(pkt_array_depth/2)*3] 	<= 1'b0;
                end
                if (wr_en_c0[q]) begin
                    for(rr=0; rr < pkt_array_depth/2; rr = rr+1) begin
                        pktout_val_array1 [q][rr]	<= 1'b0;
                    end
                end
                if (wr_en_c1[q]) begin
                    for(rr=pkt_array_depth/2; rr < pkt_array_depth; rr = rr+1) begin
                        pktout_val_array1 [q][rr]	<= 1'b0;
                    end
                end
				if (wr_en_c2[q]) begin
                    for(rr=pkt_array_depth; rr < (pkt_array_depth/2)*3; rr = rr+1) begin
                        pktout_val_array1 [q][rr]	<= 1'b0;
                    end
                end
				if (wr_en_c3[q]) begin
                    for(rr=(pkt_array_depth/2)*3; rr < (pkt_array_depth/2)*4; rr = rr+1) begin
                        pktout_val_array1 [q][rr]	<= 1'b0;
                    end
                end
                for(r=0; r < `num_segments; r = r+1) begin
                    if (pkt_val[q][r]) begin
                        pktout_val_array0 [q][pktout_array_ptr[q]] <= 1'b1;
                        pktout_val_array1 [q][pktout_array_ptr[q]] <= 1'b1;
                        pktout_seg_sel_reg[q][pktout_array_ptr[q]] <= r;
						if (pkt_eop[q][r]) begin
                            if (pktout_array_ptr[q][$clog2(pkt_array_depth*2)-1:$clog2(pkt_array_depth*2)-2] == 2'b11)
                                pktout_array_ptr[q] = 0;
                            else if (pktout_array_ptr[q][$clog2(pkt_array_depth*2)-1:$clog2(pkt_array_depth*2)-2] == 2'b10)
                                pktout_array_ptr[q] = (pkt_array_depth/2)*3;
							else if (pktout_array_ptr[q][$clog2(pkt_array_depth*2)-1:$clog2(pkt_array_depth*2)-2] == 2'b01)
                                pktout_array_ptr[q] = pkt_array_depth;
							else
								pktout_array_ptr[q] = pkt_array_depth/2;
                        end else
                            pktout_array_ptr[q] = pktout_array_ptr[q] + 1;
                    end
                end
        end
    end
end
endgenerate

genvar s, array_depth0;
generate
for (s=0; s < `num_axis_ports; s = s+1) begin
    always @ (posedge aclk_axis_unseg) begin
        pktout_val_array2[s]	<= pktout_val_array1[s];
        pktout_val_array[s]		<= pktout_val_array2[s];
        pktout_val_array00[s]	<= pktout_val_array0[s];
    end
	for (array_depth0=0; array_depth0 < pkt_array_depth*2; array_depth0 = array_depth0+1) begin
        always @ (posedge aclk_axis_unseg) begin
			pktout_seg_sel_reg1[s][array_depth0]	<= pktout_seg_sel_reg[s][array_depth0];
		end
	end
    for (array_depth0=0; array_depth0 < pkt_array_depth*2; array_depth0 = array_depth0+1) begin
        always @ (posedge aclk_axis_unseg) begin
            if (!aresetn_axis_unseg) begin
                pktout_eop_array[s][array_depth0]	<= 1'b0;
                pktout_err_array[s][array_depth0]	<= 1'b0;
                pktout_mty_array[s][array_depth0] 	<= 'd0;
                pktout_data_array[s][array_depth0] 	<= 'd0;
            end else begin
                if (pktout_val_array00[s][array_depth0]) begin
                    pktout_eop_array[s][array_depth0]   <= pkt_eop2 [s][pktout_seg_sel_reg1[s][array_depth0]];
                    pktout_err_array[s][array_depth0]   <= pkt_err2 [s][pktout_seg_sel_reg1[s][array_depth0]];
                    pktout_mty_array[s][array_depth0]   <= pkt_mty2 [s][pktout_seg_sel_reg1[s][array_depth0]];
                    pktout_data_array[s][array_depth0]  <= pkt_data2[s][pktout_seg_sel_reg1[s][array_depth0]];
                end else begin
                    pktout_eop_array[s][array_depth0]	<= 1'b0;
                    pktout_err_array[s][array_depth0]	<= 1'b0;
                end
            end
        end
    end
end
endgenerate

//-----------------------------------------------------------------------------------------------------------------------

//----------------- Buffering packed segments

reg rd_en0;
reg rd_en1;
reg rd_en2;
reg rd_en3;

genvar t;

generate
for (t=0; t<`num_axis_ports; t=t+1) begin
    assign wr_en_c0[t] = pktout_val_array1[t][(pkt_array_depth/2)-1] | (|pktout_eop_array[t][(pkt_array_depth/2)-1:0]);
    assign wr_en_c1[t] = pktout_val_array1[t][((pkt_array_depth/2)*2)-1] | (|pktout_eop_array[t][((pkt_array_depth/2)*2)-1:(pkt_array_depth/2)]);
    assign wr_en_c2[t] = pktout_val_array1[t][((pkt_array_depth/2)*3)-1] | (|pktout_eop_array[t][((pkt_array_depth/2)*3)-1:((pkt_array_depth/2)*2)]);
    assign wr_en_c3[t] = pktout_val_array1[t][(pkt_array_depth*2)-1] | (|pktout_eop_array[t][(pkt_array_depth*2)-1:((pkt_array_depth/2)*3)]);
    always @ (posedge aclk_axis_unseg) begin
        if (!aresetn_axis_unseg) begin
            wr_en0[t] <= 1'b0;
            wr_en1[t] <= 1'b0;
            wr_en2[t] <= 1'b0;
            wr_en3[t] <= 1'b0;
        end else begin
            wr_en0[t] <= pktout_val_array[t][(pkt_array_depth/2)-1] | (|pktout_eop_array[t][(pkt_array_depth/2)-1:0]);
            wr_en1[t] <= pktout_val_array[t][((pkt_array_depth/2)*2)-1] | (|pktout_eop_array[t][((pkt_array_depth/2)*2)-1:(pkt_array_depth/2)]);
            wr_en2[t] <= pktout_val_array[t][((pkt_array_depth/2)*3)-1] | (|pktout_eop_array[t][((pkt_array_depth/2)*3)-1:((pkt_array_depth/2)*2)]);
            wr_en3[t] <= pktout_val_array[t][(pkt_array_depth*2)-1] | (|pktout_eop_array[t][(pkt_array_depth*2)-1:((pkt_array_depth/2)*3)]);
        end
    end
end
endgenerate

reg [`segment_width-1:0] pktout_data_buf_in_p0 [`num_axis_ports-1:0] [(pkt_array_depth/2)-1:0];
reg [seg_mty_w-1:0] pktout_mty_buf_in_p0 [`num_axis_ports-1:0] [(pkt_array_depth/2)-1:0];
reg [(pkt_array_depth/2)-1:0] pktout_val_buf_in_p0 [`num_axis_ports-1:0];
reg [(pkt_array_depth/2)-1:0] pktout_eop_buf_in_p0 [`num_axis_ports-1:0];
reg [(pkt_array_depth/2)-1:0] pktout_err_buf_in_p0 [`num_axis_ports-1:0];
reg [`segment_width-1:0] pktout_data_buf_in_p1 [`num_axis_ports-1:0] [(pkt_array_depth/2)-1:0];
reg [seg_mty_w-1:0] pktout_mty_buf_in_p1 [`num_axis_ports-1:0] [(pkt_array_depth/2)-1:0];
reg [(pkt_array_depth/2)-1:0] pktout_val_buf_in_p1 [`num_axis_ports-1:0];
reg [(pkt_array_depth/2)-1:0] pktout_eop_buf_in_p1 [`num_axis_ports-1:0];
reg [(pkt_array_depth/2)-1:0] pktout_err_buf_in_p1 [`num_axis_ports-1:0];
reg [`segment_width-1:0] pktout_data_buf_in_p2 [`num_axis_ports-1:0] [(pkt_array_depth/2)-1:0];
reg [seg_mty_w-1:0] pktout_mty_buf_in_p2 [`num_axis_ports-1:0] [(pkt_array_depth/2)-1:0];
reg [(pkt_array_depth/2)-1:0] pktout_val_buf_in_p2 [`num_axis_ports-1:0];
reg [(pkt_array_depth/2)-1:0] pktout_eop_buf_in_p2 [`num_axis_ports-1:0];
reg [(pkt_array_depth/2)-1:0] pktout_err_buf_in_p2 [`num_axis_ports-1:0];
reg [`segment_width-1:0] pktout_data_buf_in_p3 [`num_axis_ports-1:0] [(pkt_array_depth/2)-1:0];
reg [seg_mty_w-1:0] pktout_mty_buf_in_p3 [`num_axis_ports-1:0] [(pkt_array_depth/2)-1:0];
reg [(pkt_array_depth/2)-1:0] pktout_val_buf_in_p3 [`num_axis_ports-1:0];
reg [(pkt_array_depth/2)-1:0] pktout_eop_buf_in_p3 [`num_axis_ports-1:0];
reg [(pkt_array_depth/2)-1:0] pktout_err_buf_in_p3 [`num_axis_ports-1:0];

wire [(pkt_array_depth/2)-1:0] unseg_out_buf1_aempty_0 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_out_buf1_aempty_1 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_out_buf1_empty_0 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_out_buf1_empty_1 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_out_data_valid_0 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_out_data_valid_1 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_out_rd_rst_busy_0 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_out_rd_rst_busy_1 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_out_wr_rst_busy_0 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_out_wr_rst_busy_1 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_out_buf1_aempty_2 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_out_buf1_aempty_3 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_out_buf1_empty_2 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_out_buf1_empty_3 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_out_data_valid_2 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_out_data_valid_3 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_out_rd_rst_busy_2 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_out_rd_rst_busy_3 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_out_wr_rst_busy_2 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_out_wr_rst_busy_3 [`num_axis_ports-1:0];

wire [(pkt_array_depth/2)-1:0] unseg_out_buf1_afull_0 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_out_buf1_afull_1 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_out_buf1_afull_2 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_out_buf1_afull_3 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_out_buf1_pfull_0 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_out_buf1_pfull_1 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_out_buf1_pfull_2 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] unseg_out_buf1_pfull_3 [`num_axis_ports-1:0];

wire [`segment_width-1:0] pktout_data_buf_out_p0 [`num_axis_ports-1:0] [(pkt_array_depth/2)-1:0];
wire [seg_mty_w-1:0] pktout_mty_buf_out_p0 [`num_axis_ports-1:0] [(pkt_array_depth/2)-1:0];
wire [(pkt_array_depth/2)-1:0] pktout_val_buf_out_p0 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] pktout_eop_buf_out_p0 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] pktout_err_buf_out_p0 [`num_axis_ports-1:0];
wire [`segment_width-1:0] pktout_data_buf_out_p1 [`num_axis_ports-1:0] [(pkt_array_depth/2)-1:0];
wire [seg_mty_w-1:0] pktout_mty_buf_out_p1 [`num_axis_ports-1:0] [(pkt_array_depth/2)-1:0];
wire [(pkt_array_depth/2)-1:0] pktout_val_buf_out_p1 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] pktout_eop_buf_out_p1 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] pktout_err_buf_out_p1 [`num_axis_ports-1:0];
wire [`segment_width-1:0] pktout_data_buf_out_p2 [`num_axis_ports-1:0] [(pkt_array_depth/2)-1:0];
wire [seg_mty_w-1:0] pktout_mty_buf_out_p2 [`num_axis_ports-1:0] [(pkt_array_depth/2)-1:0];
wire [(pkt_array_depth/2)-1:0] pktout_val_buf_out_p2 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] pktout_eop_buf_out_p2 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1:0] pktout_err_buf_out_p2 [`num_axis_ports-1:0];
wire [`segment_width-1:0] pktout_data_buf_out_p3 [`num_axis_ports-1:0] [(pkt_array_depth/2)-1:0];
wire [seg_mty_w-1:0] pktout_mty_buf_out_p3 [`num_axis_ports-1:0] [(pkt_array_depth/2)-1:0];
wire [(pkt_array_depth/2)-1:0] pktout_val_buf_out_p3 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1: 0] pktout_eop_buf_out_p3 [`num_axis_ports-1:0];
wire [(pkt_array_depth/2)-1: 0] pktout_err_buf_out_p3 [`num_axis_ports-1:0];

genvar u1,v1;

generate
for (u1=0; u1<`num_axis_ports; u1=u1+1) begin
    for (v1=0; v1<(pkt_array_depth/2); v1=v1+1) begin
        always @ (posedge aclk_axis_unseg) begin
            if (!aresetn_axis_unseg) begin
                pktout_val_buf_in_p0[u1][v1]	<= 1'b0;
                pktout_eop_buf_in_p0[u1][v1]	<= 1'b0;
                pktout_err_buf_in_p0[u1][v1]	<= 1'b0;
                pktout_val_buf_in_p1[u1][v1]	<= 1'b0;
                pktout_eop_buf_in_p1[u1][v1]	<= 1'b0;
                pktout_err_buf_in_p1[u1][v1]	<= 1'b0;
				pktout_val_buf_in_p2[u1][v1]	<= 1'b0;
                pktout_eop_buf_in_p2[u1][v1]	<= 1'b0;
                pktout_err_buf_in_p2[u1][v1]	<= 1'b0;
                pktout_val_buf_in_p3[u1][v1]	<= 1'b0;
                pktout_eop_buf_in_p3[u1][v1]	<= 1'b0;
                pktout_err_buf_in_p3[u1][v1]	<= 1'b0;
            end else begin
                pktout_val_buf_in_p0[u1][v1]	<= pktout_val_array[u1][v1];
                pktout_data_buf_in_p0[u1][v1]   <= pktout_data_array[u1][v1];
                pktout_mty_buf_in_p0[u1][v1]   	<= pktout_mty_array[u1][v1];
                pktout_eop_buf_in_p0[u1][v1]   	<= pktout_eop_array[u1][v1];
                pktout_err_buf_in_p0[u1][v1]   	<= pktout_err_array[u1][v1];
                pktout_val_buf_in_p1[u1][v1]   	<= pktout_val_array[u1][v1+(pkt_array_depth/2)];
                pktout_data_buf_in_p1[u1][v1]  	<= pktout_data_array[u1][v1+(pkt_array_depth/2)];
                pktout_mty_buf_in_p1[u1][v1]   	<= pktout_mty_array[u1][v1+(pkt_array_depth/2)];
                pktout_eop_buf_in_p1[u1][v1]   	<= pktout_eop_array[u1][v1+(pkt_array_depth/2)];
                pktout_err_buf_in_p1[u1][v1]   	<= pktout_err_array[u1][v1+(pkt_array_depth/2)];
                pktout_val_buf_in_p2[u1][v1]   	<= pktout_val_array[u1][v1+((pkt_array_depth/2)*2)];
                pktout_data_buf_in_p2[u1][v1]  	<= pktout_data_array[u1][v1+((pkt_array_depth/2)*2)];
                pktout_mty_buf_in_p2[u1][v1]   	<= pktout_mty_array[u1][v1+((pkt_array_depth/2)*2)];
                pktout_eop_buf_in_p2[u1][v1]   	<= pktout_eop_array[u1][v1+((pkt_array_depth/2)*2)];
                pktout_err_buf_in_p2[u1][v1]   	<= pktout_err_array[u1][v1+((pkt_array_depth/2)*2)];
                pktout_val_buf_in_p3[u1][v1]   	<= pktout_val_array[u1][v1+((pkt_array_depth/2)*3)];
                pktout_data_buf_in_p3[u1][v1]  	<= pktout_data_array[u1][v1+((pkt_array_depth/2)*3)];
                pktout_mty_buf_in_p3[u1][v1]   	<= pktout_mty_array[u1][v1+((pkt_array_depth/2)*3)];
                pktout_eop_buf_in_p3[u1][v1]   	<= pktout_eop_array[u1][v1+((pkt_array_depth/2)*3)];
                pktout_err_buf_in_p3[u1][v1]   	<= pktout_err_array[u1][v1+((pkt_array_depth/2)*3)];
            end
        end
    end
end
endgenerate

genvar w1,x1;
generate
for (w1=0; w1<`num_axis_ports; w1=w1+1) begin
    for (x1=0; x1<(pkt_array_depth/2); x1=x1+1) begin
        xpm_fifo_sync #(
           .CASCADE_HEIGHT(0),
           .DOUT_RESET_VALUE("0"),
           .ECC_MODE("no_ecc"),
           .FIFO_MEMORY_TYPE("auto"),
           .FIFO_READ_LATENCY(1),
           .FIFO_WRITE_DEPTH(pktarry_buff_depth),
           .FULL_RESET_VALUE(0),
           .PROG_EMPTY_THRESH(3),
           .PROG_FULL_THRESH(pktarry_buff_pfull_thresh),
           .RD_DATA_COUNT_WIDTH(1),
           .READ_DATA_WIDTH(`segment_width+seg_mty_w+3),
           .READ_MODE("std"),
           .SIM_ASSERT_CHK(0),
           .USE_ADV_FEATURES("100A"),
           .WAKEUP_TIME(0),
           .WRITE_DATA_WIDTH(`segment_width+seg_mty_w+3),
           .WR_DATA_COUNT_WIDTH(1)
        )
        xpm_fifo_sync_unseg_out_stage1_p0 (
           .almost_empty(unseg_out_buf1_aempty_0[w1][x1]),
           .almost_full(unseg_out_buf1_afull_0[w1][x1]),
           .data_valid(unseg_out_data_valid_0[w1][x1]),
           .dbiterr(),
           .dout({pktout_mty_buf_out_p0[w1][x1],pktout_err_buf_out_p0[w1][x1],pktout_eop_buf_out_p0[w1][x1],pktout_val_buf_out_p0[w1][x1],pktout_data_buf_out_p0[w1][x1]}),
           .empty(unseg_out_buf1_empty_0[w1][x1]),
           .full(),
           .overflow(),
           .prog_empty(),
           .prog_full(unseg_out_buf1_pfull_0[w1][x1]),
           .rd_data_count(),
           .rd_rst_busy(unseg_out_rd_rst_busy_0[w1][x1]),
           .sbiterr(),
           .underflow(),
           .wr_ack(),
           .wr_data_count(),
           .wr_rst_busy(unseg_out_wr_rst_busy_0[w1][x1]),
           .din({pktout_mty_buf_in_p0[w1][x1],pktout_err_buf_in_p0[w1][x1],pktout_eop_buf_in_p0[w1][x1],pktout_val_buf_in_p0[w1][x1],pktout_data_buf_in_p0[w1][x1]}),
           .injectdbiterr(1'b0),
           .injectsbiterr(1'b0),
		   .rd_en(rd_en0 & !outbuff_pfull & !unseg_out_data_valid_0[w1][x1]),
           .rst(!aresetn_axis_unseg),
           .sleep(1'b0),
           .wr_clk(aclk_axis_unseg),
           .wr_en(wr_en0[w1] & !unseg_out_wr_rst_busy_0[w1][x1])
        );

        xpm_fifo_sync #(
           .CASCADE_HEIGHT(0),
           .DOUT_RESET_VALUE("0"),
           .ECC_MODE("no_ecc"),
           .FIFO_MEMORY_TYPE("auto"),
           .FIFO_READ_LATENCY(1),
           .FIFO_WRITE_DEPTH(pktarry_buff_depth),
           .FULL_RESET_VALUE(0),
           .PROG_EMPTY_THRESH(3),
           .PROG_FULL_THRESH(pktarry_buff_pfull_thresh),
           .RD_DATA_COUNT_WIDTH(1),
           .READ_DATA_WIDTH(`segment_width+seg_mty_w+3),
           .READ_MODE("std"),
           .SIM_ASSERT_CHK(0),
           .USE_ADV_FEATURES("100A"),
           .WAKEUP_TIME(0),
           .WRITE_DATA_WIDTH(`segment_width+seg_mty_w+3),
           .WR_DATA_COUNT_WIDTH(1)
        )
        xpm_fifo_sync_unseg_out_stage1_p1 (
           .almost_empty(unseg_out_buf1_aempty_1[w1][x1]),
           .almost_full(unseg_out_buf1_afull_1[w1][x1]),
           .data_valid(unseg_out_data_valid_1[w1][x1]),
           .dbiterr(),
           .dout({pktout_mty_buf_out_p1[w1][x1],pktout_err_buf_out_p1[w1][x1],pktout_eop_buf_out_p1[w1][x1],pktout_val_buf_out_p1[w1][x1],pktout_data_buf_out_p1[w1][x1]}),
           .empty(unseg_out_buf1_empty_1[w1][x1]),
           .full(),
           .overflow(),
           .prog_empty(),
           .prog_full(unseg_out_buf1_pfull_1[w1][x1]),
           .rd_data_count(),
           .rd_rst_busy(unseg_out_rd_rst_busy_1[w1][x1]),
           .sbiterr(),
           .underflow(),
           .wr_ack(),
           .wr_data_count(),
           .wr_rst_busy(unseg_out_wr_rst_busy_1[w1][x1]),
           .din({pktout_mty_buf_in_p1[w1][x1],pktout_err_buf_in_p1[w1][x1],pktout_eop_buf_in_p1[w1][x1],pktout_val_buf_in_p1[w1][x1],pktout_data_buf_in_p1[w1][x1]}),
           .injectdbiterr(1'b0),
           .injectsbiterr(1'b0),
		   .rd_en(rd_en1 & !outbuff_pfull & !unseg_out_data_valid_1[w1][x1]),
           .rst(!aresetn_axis_unseg),
           .sleep(1'b0),
           .wr_clk(aclk_axis_unseg),
           .wr_en(wr_en1[w1] & !unseg_out_wr_rst_busy_1[w1][x1])
        );

        xpm_fifo_sync #(
           .CASCADE_HEIGHT(0),
           .DOUT_RESET_VALUE("0"),
           .ECC_MODE("no_ecc"),
           .FIFO_MEMORY_TYPE("auto"),
           .FIFO_READ_LATENCY(1),
           .FIFO_WRITE_DEPTH(pktarry_buff_depth),
           .FULL_RESET_VALUE(0),
           .PROG_EMPTY_THRESH(3),
           .PROG_FULL_THRESH(pktarry_buff_pfull_thresh),
           .RD_DATA_COUNT_WIDTH(1),
           .READ_DATA_WIDTH(`segment_width+seg_mty_w+3),
           .READ_MODE("std"),
           .SIM_ASSERT_CHK(0),
           .USE_ADV_FEATURES("100A"),
           .WAKEUP_TIME(0),
           .WRITE_DATA_WIDTH(`segment_width+seg_mty_w+3),
           .WR_DATA_COUNT_WIDTH(1)
        )
        xpm_fifo_sync_unseg_out_stage1_p2 (
           .almost_empty(unseg_out_buf1_aempty_2[w1][x1]),
           .almost_full(unseg_out_buf1_afull_2[w1][x1]),
           .data_valid(unseg_out_data_valid_2[w1][x1]),
           .dbiterr(),
           .dout({pktout_mty_buf_out_p2[w1][x1],pktout_err_buf_out_p2[w1][x1],pktout_eop_buf_out_p2[w1][x1],pktout_val_buf_out_p2[w1][x1],pktout_data_buf_out_p2[w1][x1]}),
           .empty(unseg_out_buf1_empty_2[w1][x1]),
           .full(),
           .overflow(),
           .prog_empty(),
           .prog_full(unseg_out_buf1_pfull_2[w1][x1]),
           .rd_data_count(),
           .rd_rst_busy(unseg_out_rd_rst_busy_2[w1][x1]),
           .sbiterr(),
           .underflow(),
           .wr_ack(),
           .wr_data_count(),
           .wr_rst_busy(unseg_out_wr_rst_busy_2[w1][x1]),
           .din({pktout_mty_buf_in_p2[w1][x1],pktout_err_buf_in_p2[w1][x1],pktout_eop_buf_in_p2[w1][x1],pktout_val_buf_in_p2[w1][x1],pktout_data_buf_in_p2[w1][x1]}),
           .injectdbiterr(1'b0),
           .injectsbiterr(1'b0),
		   .rd_en(rd_en2 & !outbuff_pfull & !unseg_out_data_valid_2[w1][x1]),
           .rst(!aresetn_axis_unseg),
           .sleep(1'b0),
           .wr_clk(aclk_axis_unseg),
           .wr_en(wr_en2[w1] & !unseg_out_wr_rst_busy_2[w1][x1])
        );

        xpm_fifo_sync #(
           .CASCADE_HEIGHT(0),
           .DOUT_RESET_VALUE("0"),
           .ECC_MODE("no_ecc"),
           .FIFO_MEMORY_TYPE("auto"),
           .FIFO_READ_LATENCY(1),
           .FIFO_WRITE_DEPTH(pktarry_buff_depth),
           .FULL_RESET_VALUE(0),
           .PROG_EMPTY_THRESH(3),
           .PROG_FULL_THRESH(pktarry_buff_pfull_thresh),
           .RD_DATA_COUNT_WIDTH(1),
           .READ_DATA_WIDTH(`segment_width+seg_mty_w+3),
           .READ_MODE("std"),
           .SIM_ASSERT_CHK(0),
           .USE_ADV_FEATURES("100A"),
           .WAKEUP_TIME(0),
           .WRITE_DATA_WIDTH(`segment_width+seg_mty_w+3),
           .WR_DATA_COUNT_WIDTH(1)
        )
        xpm_fifo_sync_unseg_out_stage1_p3 (
           .almost_empty(unseg_out_buf1_aempty_3[w1][x1]),
           .almost_full(unseg_out_buf1_afull_3[w1][x1]),
           .data_valid(unseg_out_data_valid_3[w1][x1]),
           .dbiterr(),
           .dout({pktout_mty_buf_out_p3[w1][x1],pktout_err_buf_out_p3[w1][x1],pktout_eop_buf_out_p3[w1][x1],pktout_val_buf_out_p3[w1][x1],pktout_data_buf_out_p3[w1][x1]}),
           .empty(unseg_out_buf1_empty_3[w1][x1]),
           .full(),
           .overflow(),
           .prog_empty(),
           .prog_full(unseg_out_buf1_pfull_3[w1][x1]),
           .rd_data_count(),
           .rd_rst_busy(unseg_out_rd_rst_busy_3[w1][x1]),
           .sbiterr(),
           .underflow(),
           .wr_ack(),
           .wr_data_count(),
           .wr_rst_busy(unseg_out_wr_rst_busy_3[w1][x1]),
           .din({pktout_mty_buf_in_p3[w1][x1],pktout_err_buf_in_p3[w1][x1],pktout_eop_buf_in_p3[w1][x1],pktout_val_buf_in_p3[w1][x1],pktout_data_buf_in_p3[w1][x1]}),
           .injectdbiterr(1'b0),
           .injectsbiterr(1'b0),
		   .rd_en(rd_en3 & !outbuff_pfull & !unseg_out_data_valid_3[w1][x1]),
           .rst(!aresetn_axis_unseg),
           .sleep(1'b0),
           .wr_clk(aclk_axis_unseg),
           .wr_en(wr_en3[w1] & !unseg_out_wr_rst_busy_3[w1][x1])
        );

    end
	assign port_unseg_out_pfull[w1] = (|unseg_out_buf1_pfull_0[w1]) | (|unseg_out_buf1_pfull_1[w1]) | (|unseg_out_buf1_pfull_2[w1]) | (|unseg_out_buf1_pfull_3[w1]);
end
endgenerate

assign ports_not_rdy = &port_unseg_out_pfull;

//-----------------------------------------------------------------------------------------------------------------------

//----------------- Packet readout / array port arbitration

reg [1:0] outport_sel;
reg [1:0] outport_sel_1;
reg [1:0] outport_sel_2;

wire pktout_buff_rdy;

always @ (posedge aclk_axis_unseg) begin
    if (!aresetn_axis_unseg) begin
        rd_en0 			<= 1'b0;
        rd_en1 			<= 1'b0;
        rd_en2 			<= 1'b0;
        rd_en3 			<= 1'b0;
        outport_sel		<= 2'b00;
        outport_sel_1	<= 2'b00;
        outport_sel_2 	<= 2'b00;
    end else if (!outbuff_pfull) begin
		rd_en0 			<= 1'b0;
		rd_en1 			<= 1'b0;
		rd_en2 			<= 1'b0;
		rd_en3 			<= 1'b0;
		outport_sel_1 	<= outport_sel;
		outport_sel_2 	<= outport_sel_1;
		if (outport_sel == 2'b11) begin
			rd_en0  	<= 1'b0;
			rd_en1  	<= 1'b0;
			rd_en2  	<= 1'b0;
			if (!(|unseg_out_buf1_empty_3[0]) && !(|unseg_out_rd_rst_busy_3[0])) begin
				rd_en3  	<= 1'b1;
				outport_sel <= outport_sel+1;
			end else begin
				rd_en3  	<= 1'b0;
				outport_sel <= outport_sel;
			end
		end else if (outport_sel == 2'b10) begin
			rd_en0	<= 1'b0;
			rd_en1	<= 1'b0;
			rd_en3	<= 1'b0;
			if (!(|unseg_out_buf1_empty_2[0]) && !(|unseg_out_rd_rst_busy_2[0])) begin
				rd_en2  	<= 1'b1;
				outport_sel <= outport_sel+1;
			end else begin
				rd_en2  	<= 1'b0;
				outport_sel <= outport_sel;
			end
		end else if (outport_sel == 2'b01) begin
			rd_en0  <= 1'b0;
			rd_en2  <= 1'b0;
			rd_en3  <= 1'b0;
			if (!(|unseg_out_buf1_empty_1[0]) && !(|unseg_out_rd_rst_busy_1[0])) begin
				rd_en1  <= 1'b1;
				outport_sel <= outport_sel+1;
			end else begin
				rd_en1  <= 1'b0;
				outport_sel <= outport_sel;
			end
		end else begin
			rd_en1	<= 1'b0;
			rd_en2	<= 1'b0;
			rd_en3	<= 1'b0;
			if (!(|unseg_out_buf1_empty_0[0]) && !(|unseg_out_rd_rst_busy_0[0])) begin
				rd_en0  	<= 1'b1;
				outport_sel <= outport_sel+1;
			end else begin
				rd_en0  	<= 1'b0;
				outport_sel <= outport_sel;
			end
		end
	end
end

genvar z1, z2;

generate
for (z1=0; z1<`num_axis_ports; z1=z1+1) begin   : packetout_mux
    for (z2=0; z2<(pkt_array_depth/2); z2=z2+1) begin
        always @ (posedge aclk_axis_unseg) begin
            if (!aresetn_axis_unseg) begin
                pkt_val_out_0[z1][z2] 	<= 1'b0;
                pkt_mty_out_0[z1][z2] 	<= {seg_mty_w{1'b1}};
                pkt_eop_out_0[z1][z2] 	<= 1'b0;
                pkt_err_out_0[z1][z2] 	<= 1'b0;
            end else begin
                pkt_val_out_0[z1][z2]	<= 1'b0;
				if (outport_sel_2 == 2'b11) begin
                    pkt_val_out_0[z1][z2]    <= pktout_val_buf_out_p3[z1][z2] & unseg_out_data_valid_3[z1][z2];
                    pkt_mty_out_0[z1][z2]    <= pktout_mty_buf_out_p3[z1][z2];
                    pkt_eop_out_0[z1][z2]    <= pktout_eop_buf_out_p3[z1][z2];
                    pkt_err_out_0[z1][z2]    <= pktout_err_buf_out_p3[z1][z2];
                    pkt_data_out_0[z1][z2]   <= pktout_data_buf_out_p3[z1][z2];
				end else if (outport_sel_2 == 2'b10) begin
                    pkt_val_out_0[z1][z2]    <= pktout_val_buf_out_p2[z1][z2] & unseg_out_data_valid_2[z1][z2];
                    pkt_mty_out_0[z1][z2]    <= pktout_mty_buf_out_p2[z1][z2];
                    pkt_eop_out_0[z1][z2]    <= pktout_eop_buf_out_p2[z1][z2];
                    pkt_err_out_0[z1][z2]    <= pktout_err_buf_out_p2[z1][z2];
                    pkt_data_out_0[z1][z2]   <= pktout_data_buf_out_p2[z1][z2];
                end else if (outport_sel_2 == 2'b01) begin
                    pkt_val_out_0[z1][z2]    <= pktout_val_buf_out_p1[z1][z2] & unseg_out_data_valid_1[z1][z2];
                    pkt_mty_out_0[z1][z2]    <= pktout_mty_buf_out_p1[z1][z2];
                    pkt_eop_out_0[z1][z2]    <= pktout_eop_buf_out_p1[z1][z2];
                    pkt_err_out_0[z1][z2]    <= pktout_err_buf_out_p1[z1][z2];
                    pkt_data_out_0[z1][z2]   <= pktout_data_buf_out_p1[z1][z2];
                end else begin
                    pkt_val_out_0[z1][z2]    <= pktout_val_buf_out_p0[z1][z2] & unseg_out_data_valid_0[z1][z2];
                    pkt_mty_out_0[z1][z2]    <= pktout_mty_buf_out_p0[z1][z2];
                    pkt_eop_out_0[z1][z2]    <= pktout_eop_buf_out_p0[z1][z2];
                    pkt_err_out_0[z1][z2]    <= pktout_err_buf_out_p0[z1][z2];
                    pkt_data_out_0[z1][z2]   <= pktout_data_buf_out_p0[z1][z2];
                end
            end
        end
    end
end
endgenerate

`endif

//-----------------------------------------------------------------------------------------------------------------------

//----------------- Packet segments to axi stream conversion (each segments as independant streams)

integer a, b;
reg [`num_axis_ports-1:0] eop_flag;

generate
always @ (posedge aclk_axis_unseg) begin : packet_to_axi_stream
    if (!aresetn_axis_unseg) begin
        for (a=0; a<`num_axis_ports; a=a+1) begin
            eop_flag[a] = 0;
            for (b=0; b<(pkt_array_depth/2); b=b+1) begin
                pkt_tvalid[a][b]  <= 1'b0;
                pkt_tkeep[a][b]   <= {(`segment_width/8){1'b0}};
                pkt_tlast[a][b]   <= 1'b0;
                pkt_tuser[a][b]   <= 1'b0;
            end
        end
    end else begin
        for (a=0; a<`num_axis_ports; a=a+1) begin
		   eop_flag[a] = 0;
            for (b=0; b<(pkt_array_depth/2); b=b+1) begin
                pkt_tvalid[a][b]  <= pkt_val_out_0[a][b];
                pkt_tdata[a][b]   <= pkt_data_out_0[a][b];
                pkt_tlast[a][b]   <= pkt_eop_out_0[a][b];
                pkt_tuser[a][b]   <= pkt_err_out_0[a][b];
                pkt_tkeep[a][b]   <= {(`segment_width/8){1'b0}};
                if (eop_flag[a])
                    pkt_tkeep[a][b]   <= {(`segment_width/8){1'b0}};
                else begin
                    pkt_tkeep[a][b]   <= (2**((2**(seg_mty_w)) - pkt_mty_out_0[a][b]))-1;
                    if (pkt_eop_out_0[a][b])
                        eop_flag[a] = 1;
                    else
                        eop_flag[a] = 0;
                end
            end
        end
    end
end
endgenerate

//----------------- Combine to single axi stream

genvar c, d;
generate
for (c=0; c<`num_axis_ports; c=c+1) begin   : axi_stream_combine
    always @ (posedge aclk_axis_unseg) begin
        if (!aresetn_axis_unseg) begin
            axis_tvalid_buf_in[c]   <= 1'b0;
            axis_tlast_buf_in[c]    <= 1'b0;
            axis_tuser_buf_in[c]    <= 1'b0;
        end else begin
            if (axis_tready_buf_in[c]) begin
                axis_tvalid_buf_in[c]   <= | pkt_tvalid[c];
                axis_tlast_buf_in[c]    <= | pkt_tlast[c];
                axis_tuser_buf_in[c]    <= | pkt_tuser[c];
            end
        end
    end
    for (d=0; d<(pkt_array_depth/2); d=d+1) begin
        always @ (posedge aclk_axis_unseg) begin
            axis_tdata_buf_in[c][(`segment_width+(`segment_width*d))-1:(`segment_width*d)]                <= pkt_tdata[c][d];
            axis_tkeep_buf_in[c][((`segment_width/8)+((`segment_width/8)*d))-1:((`segment_width/8)*d)]    <= pkt_tkeep[c][d];
        end
    end
end
endgenerate

//----------------- Output buffer

wire [(`segment_width*(pkt_array_depth/2))-1:0] axis_tdata_buf_out [`num_axis_ports-1:0];
wire [((`segment_width/8)*(pkt_array_depth/2))-1:0] axis_tkeep_buf_out [`num_axis_ports-1:0];
wire [`num_axis_ports-1:0] axis_tvalid_buf_out;
wire [`num_axis_ports-1:0] axis_tlast_buf_out;
wire [`num_axis_ports-1:0] axis_tuser_buf_out;
wire [`num_axis_ports-1:0] axis_tready_buf_out;
wire [`num_axis_ports-1:0] axis_out_buff_pfull;

genvar e;

generate
for (e=0; e<`num_axis_ports; e=e+1) begin : axis_out_buffer
    xpm_fifo_axis #(
        .CASCADE_HEIGHT(0),
        .CDC_SYNC_STAGES(3),
        .CLOCKING_MODE("common_clock"),
        .ECC_MODE("no_ecc"),
        .FIFO_DEPTH(out_buff_depth),
        .FIFO_MEMORY_TYPE("auto"),
        .PACKET_FIFO("true"),
        .PROG_EMPTY_THRESH(10),
        .PROG_FULL_THRESH(out_buff_depth-5),
        .RD_DATA_COUNT_WIDTH(1),
        .RELATED_CLOCKS(0),
        .SIM_ASSERT_CHK(0),
        .TDATA_WIDTH((pkt_array_depth/2)*`segment_width),
        .TDEST_WIDTH(1),
        .TID_WIDTH(1),
        .TUSER_WIDTH(1),
        .USE_ADV_FEATURES("0003"),
        .WR_DATA_COUNT_WIDTH(1)
        )
    xpm_fifo_axis_unseg_out (
        .m_aclk(aclk_axis_unseg),
        .m_axis_tready(axis_tready_buf_out[e]),
        .m_axis_tdata(axis_tdata_buf_out[e]),
        .m_axis_tkeep(axis_tkeep_buf_out[e]),
        .m_axis_tlast(axis_tlast_buf_out[e]),
        .m_axis_tuser(axis_tuser_buf_out[e]),
        .m_axis_tvalid(axis_tvalid_buf_out[e]),
        .s_aclk(aclk_axis_unseg),
        .s_aresetn(aresetn_axis_unseg),
        .prog_full_axis(axis_out_buff_pfull[e]),
        .injectdbiterr_axis(1'b0),
        .injectsbiterr_axis(1'b0),
        .s_axis_tready(axis_tready_buf_in[e]),
        .s_axis_tdata(axis_tdata_buf_in[e]),
        .s_axis_tkeep(axis_tkeep_buf_in[e]),
        .s_axis_tlast(axis_tlast_buf_in[e]),
        .s_axis_tuser(axis_tuser_buf_in[e]),
        .s_axis_tvalid(axis_tvalid_buf_in[e])
        );
end
endgenerate

assign outbuff_pfull = axis_out_buff_pfull;

assign m_axis0_tdata 			= axis_tdata_buf_out[0];
assign m_axis0_tkeep 			= axis_tkeep_buf_out[0];
assign m_axis0_tlast 			= axis_tlast_buf_out[0];
assign m_axis0_tuser 			= axis_tuser_buf_out[0];
assign m_axis0_tvalid 			= axis_tvalid_buf_out[0];
assign axis_tready_buf_out[0]	= m_axis0_tready;

`ifdef en_axis1
assign m_axis1_tdata 			= axis_tdata_buf_out[1];
assign m_axis1_tkeep 			= axis_tkeep_buf_out[1];
assign m_axis1_tlast 			= axis_tlast_buf_out[1];
assign m_axis1_tuser 			= axis_tuser_buf_out[1];
assign m_axis1_tvalid 			= axis_tvalid_buf_out[1];
assign axis_tready_buf_out[1]	= m_axis1_tready;
`endif

//-----------------------------------------------------------------------------------------------------------------------

//----------------- Port Statistics

`ifdef statistics_en
    localparam statistics_en = 1;
`else
    localparam statistics_en = 0;
`endif

generate

if (statistics_en) begin

//----------------- Input packet count

reg [63:0] segment_pkt_cnt [`num_segments-1:0];
reg [63:0] segment_err_cnt [`num_segments-1:0];
reg [63:0] segment_byte_cnt [`num_segments-1:0];
wire [($clog2(`segment_width/8)):0] segment_validbytes [`num_segments-1:0];
reg [63:0] total_pktin_cnt;
reg [63:0] total_err_pktin_cnt;
reg [63:0] total_pktin_byte_cnt;

genvar ab;

for (ab=0; ab<`num_segments; ab=ab+1) begin
    mty_to_validbytes u_mty_to_valbytes
        (
        .mty_in(seg2unseg_mty[ab]),
        .valid_bytes_out(segment_validbytes[ab])
        );
end

genvar cd;

for (cd=0; cd<`num_segments; cd=cd+1) begin
    always @ (posedge aclk_axis_seg_in) begin
        if (!aresetn_axis_seg_in)
            segment_byte_cnt[cd] <= 'd0;
        else if (seg2unseg_val[cd])
            segment_byte_cnt[cd] <=  segment_byte_cnt[cd] + segment_validbytes[cd];
    end
end

integer ef;

always @ (*) begin
    total_pktin_byte_cnt   = 'd0;
    for (ef=0; ef<`num_segments; ef=ef+1) begin
        total_pktin_byte_cnt   = total_pktin_byte_cnt + segment_byte_cnt[ef];
    end
end

genvar gh;

for (gh=0; gh<`num_segments; gh=gh+1) begin
    always @ (posedge aclk_axis_seg_in) begin
        if (!aresetn_axis_seg_in)
            segment_pkt_cnt[gh] <= 'd0;
        else if (seg2unseg_val[gh] && seg2unseg_eop[gh])
            segment_pkt_cnt[gh] <= segment_pkt_cnt[gh] + 1;
    end
    always @ (posedge aclk_axis_seg_in) begin
        if (!aresetn_axis_seg_in)
            segment_err_cnt[gh] <= 'd0;
        else if (seg2unseg_val[gh] && seg2unseg_eop[gh] && seg2unseg_err[gh])
            segment_err_cnt[gh] <= segment_err_cnt[gh] + 1;
    end
end

integer ij;

always @ (*) begin
    total_pktin_cnt   = 'd0;
    total_err_pktin_cnt   = 'd0;
    for (ij=0; ij<`num_segments; ij=ij+1) begin
        total_pktin_cnt   = total_pktin_cnt + segment_pkt_cnt[ij];
		total_err_pktin_cnt   = total_err_pktin_cnt + segment_err_cnt[ij];
    end
end

//----------------- Output packet count

reg [63:0] port_pkt_out_cnt [`num_axis_ports-1:0];
reg [63:0] port_err_out_cnt [`num_axis_ports-1:0];
reg [63:0] port_pkt_byte_cnt [`num_axis_ports-1:0];
reg [63:0] total_pktout_cnt;
reg [63:0] total_err_pktout_cnt;
reg [63:0] total_pktout_byte_cnt;

wire [($clog2(`unseg_axis_w/8)):0] port_valid_bytes [`num_axis_ports-1:0];

genvar g;
for (g=0; g<`num_axis_ports; g=g+1) begin
    tkeep_to_validbytes u_tkeep_to_valbytes
        (
        .tkeep_in(axis_tkeep_buf_out[g]),
        .valid_bytes_out(port_valid_bytes[g])
        );
end

genvar i;
for (i=0; i<`num_axis_ports; i=i+1) begin
    always @ (posedge aclk_axis_unseg) begin
        if (!aresetn_axis_unseg)
            port_pkt_out_cnt[i] <= 'd0;
        else
            if (axis_tvalid_buf_out[i] && axis_tready_buf_out[i] && axis_tlast_buf_out[i])
                port_pkt_out_cnt[i] <= port_pkt_out_cnt[i] + 'd1;
    end
    always @ (posedge aclk_axis_unseg) begin
        if (!aresetn_axis_unseg)
            port_err_out_cnt[i] <= 'd0;
        else
            if (axis_tvalid_buf_out[i] && axis_tready_buf_out[i] && axis_tlast_buf_out[i] && axis_tuser_buf_out[i])
                port_err_out_cnt[i] <= port_err_out_cnt[i] + 'd1;
    end
end

genvar j;
for (j=0; j<`num_axis_ports; j=j+1) begin
    always @ (posedge aclk_axis_unseg) begin
        if (!aresetn_axis_unseg)
            port_pkt_byte_cnt[j] <= 'd0;
        else
            if (axis_tvalid_buf_out[j] && axis_tready_buf_out[j])
                port_pkt_byte_cnt[j] <= port_pkt_byte_cnt[j] + port_valid_bytes[j];
    end
end

integer k;
always @ (*) begin
    total_pktout_cnt   = 'd0;
    total_err_pktout_cnt   = 'd0;
    total_pktout_byte_cnt   = 'd0;
    for (k=0; k<`num_axis_ports; k=k+1) begin
        total_pktout_cnt   = total_pktout_cnt + port_pkt_out_cnt[k];
        total_err_pktout_cnt   = total_err_pktout_cnt + port_err_out_cnt[k];
        total_pktout_byte_cnt   = total_pktout_byte_cnt + port_pkt_byte_cnt[k];
    end
end

assign total_pkt_in_cnt 		= total_pktin_cnt;
assign total_err_pkt_in_cnt 	= total_err_pktin_cnt;
assign total_pkt_in_byte_cnt 	= total_pktin_byte_cnt;
assign total_pkt_out_cnt 		= total_pktout_cnt;
assign total_err_pkt_out_cnt 	= total_err_pktout_cnt;
assign total_pkt_out_byte_cnt	= total_pktout_byte_cnt;
`ifdef en_axis1
assign p1_pkt_out_cnt 			= port_pkt_out_cnt[1];
assign p1_err_pkt_out_cnt 		= port_err_out_cnt[1];
assign p1_pkt_out_byte_cnt 		= port_pkt_byte_cnt[1];
assign p0_pkt_out_cnt 			= port_pkt_out_cnt[0];
assign p0_err_pkt_out_cnt 		= port_err_out_cnt[0];
assign p0_pkt_out_byte_cnt		= port_pkt_byte_cnt[0];
`endif

end

endgenerate

`ifdef debug_en

reg [`num_axis_ports-1:0] err_boken_pkt, err_boken_pkt_tlst;

genvar k0;
integer k1;

generate

for (k0=0; k0<`num_axis_ports; k0=k0+1) begin
    always @ (posedge aclk_axis_unseg) begin
        if (!aresetn_axis_unseg)
			err_boken_pkt[k0]	<= 1'b0;
		else
			err_boken_pkt[k0]	<= axis_tvalid_buf_out[k0] & axis_tready_buf_out[k0] & ~axis_tlast_buf_out[k0] & ~(&axis_tkeep_buf_out[k0]);
	end
end

for (k0=0; k0<`num_axis_ports; k0=k0+1) begin
    always @ (posedge aclk_axis_unseg) begin
        if (!aresetn_axis_unseg)
			err_boken_pkt_tlst[k0] = 1'b0;
		else begin
			err_boken_pkt_tlst[k0] = 1'b0;
			if (axis_tlast_buf_out[k0]) begin
				if (!err_boken_pkt_tlst[k0]) begin
					for (k1=0; k1<(`unseg_axis_w/8)-2; k1=k1+1) begin
						if (axis_tkeep_buf_out[k0][k1+1] && !axis_tkeep_buf_out[k0][k1])
							err_boken_pkt_tlst[k0] = 1'b1;
						else
							err_boken_pkt_tlst[k0] = 1'b0;
					end
				end
			end else
				err_boken_pkt_tlst[k0] = 1'b0;
		end
	end
end


endgenerate

assign error_broken_packet_out = (|err_boken_pkt) | (|(err_boken_pkt_tlst & axis_tlast_buf_out & axis_tvalid_buf_out & axis_tready_buf_out));

`endif

endmodule

//-----------------------------------------------------------------------------------------------------------------------

module tkeep_to_validbytes
    (
     input [(`unseg_axis_w/8)-1:0] tkeep_in,
     output wire [($clog2(`unseg_axis_w/8)):0] valid_bytes_out
    );

integer i;

reg [($clog2(`unseg_axis_w/8)):0] valid_bytes;

always @ (tkeep_in) begin
    valid_bytes = 0;
    for (i=0; i<(`unseg_axis_w/8); i=i+1)
        valid_bytes = valid_bytes + tkeep_in[i];
end

assign valid_bytes_out = valid_bytes;

endmodule

//-----------------------------------------------------------------------------------------------------------------------

module mty_to_validbytes
    (
     input [($clog2(`segment_width/8))-1:0] mty_in,
     output wire [($clog2(`segment_width/8)):0] valid_bytes_out
    );

integer i;

reg [($clog2(`segment_width/8)):0] valid_bytes;

always @ (mty_in) begin
    valid_bytes <= (2**($clog2(`segment_width/8))) - mty_in;
end

assign valid_bytes_out = valid_bytes;

endmodule


//########################################################################################################################

//------------------------------------ AXIS Unsegmented to Segmented stream Converter ------------------------------------

module axis_unseg_to_seg_converter
        (
        // AXIS Segment to Unsegment converter ports
        // Clock & Resets
        (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk_axis_seg_in CLK" *)
        (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET aresetn_axis_seg_in" *)
        input aclk_axis_seg_in,
        (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn_axis_seg_in RST" *)
        (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
        input aresetn_axis_seg_in,
        `ifdef independant_clk
        (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk_axis_unseg_in CLK" *)
        (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF m_axis_pktout, ASSOCIATED_RESET aresetn_axis_unseg_in" *)
        input aclk_axis_unseg_in,
        (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn_axis_unseg_in RST" *)
        (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
        input aresetn_axis_unseg_in,
        `endif
        // Segmented interface
        // port0 is active for all valid configurations
        // Segment 0 input
        output                                     Unseg2SegEna0_out,
        output [`segment_width-1:0]                Unseg2SegDat0_out,
        output                                     Unseg2SegSop0_out,
        output                                     Unseg2SegEop0_out,
        output                                     Unseg2SegErr0_out,
        output [($clog2(`segment_width/8))-1:0]    Unseg2SegMty0_out,
        // Segment 1 input
        output                                     Unseg2SegEna1_out,
        output  [`segment_width-1:0]               Unseg2SegDat1_out,
        output                                     Unseg2SegSop1_out,
        output                                     Unseg2SegEop1_out,
        output                                     Unseg2SegErr1_out,
        output  [($clog2(`segment_width/8))-1:0]   Unseg2SegMty1_out,
        `ifdef en_port1
        // Segment 2 input
        output                                     Unseg2SegEna2_out,
        output  [`segment_width-1:0]               Unseg2SegDat2_out,
        output                                     Unseg2SegSop2_out,
        output                                     Unseg2SegEop2_out,
        output                                     Unseg2SegErr2_out,
        output  [($clog2(`segment_width/8))-1:0]   Unseg2SegMty2_out,
        // Segment 3 input
        output                                     Unseg2SegEna3_out,
        output  [`segment_width-1:0]               Unseg2SegDat3_out,
        output                                     Unseg2SegSop3_out,
        output                                     Unseg2SegEop3_out,
        output                                     Unseg2SegErr3_out,
        output  [($clog2(`segment_width/8))-1:0]   Unseg2SegMty3_out,
        `endif
        `ifdef en_port2
        // Segment 4 input
        output                                     Unseg2SegEna4_out,
        output  [`segment_width-1:0]               Unseg2SegDat4_out,
        output                                     Unseg2SegSop4_out,
        output                                     Unseg2SegEop4_out,
        output                                     Unseg2SegErr4_out,
        output  [($clog2(`segment_width/8))-1:0]   Unseg2SegMty4_out,
        // Segment 5 input
        output                                     Unseg2SegEna5_out,
        output  [`segment_width-1:0]               Unseg2SegDat5_out,
        output                                     Unseg2SegSop5_out,
        output                                     Unseg2SegEop5_out,
        output                                     Unseg2SegErr5_out,
        output  [($clog2(`segment_width/8))-1:0]   Unseg2SegMty5_out,
        `endif
        `ifdef en_port3
        // Segment 6 input
        output                                     Unseg2SegEna6_out,
        output  [`segment_width-1:0]               Unseg2SegDat6_out,
        output                                     Unseg2SegSop6_out,
        output                                     Unseg2SegEop6_out,
        output                                     Unseg2SegErr6_out,
        output  [($clog2(`segment_width/8))-1:0]   Unseg2SegMty6_out,
        // Segment 7 input
        output                                     Unseg2SegEna7_out,
        output  [`segment_width-1:0]               Unseg2SegDat7_out,
        output                                     Unseg2SegSop7_out,
        output                                     Unseg2SegEop7_out,
        output                                     Unseg2SegErr7_out,
        output  [($clog2(`segment_width/8))-1:0]   Unseg2SegMty7_out,
        `endif

        // Packet output interface - Unsegmented AXI Stream
        // axis0 is active for all valid configurations
        // unsegmented AXIS0 interface
        (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis0_pkt_in TDATA" *)
        input [`unseg_axis_w-1:0]       s_axis0_tdata,
        (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis0_pkt_in TKEEP" *)
        input [(`unseg_axis_w/8)-1:0]   s_axis0_tkeep,
        (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis0_pkt_in TLAST" *)
        input                           s_axis0_tlast,
		(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis0_pkt_in TUSER" *)
        input                           s_axis0_tuser,
        (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis0_pkt_in TVALID" *)
        input                           s_axis0_tvalid,
        (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis0_pkt_in TREADY" *)
        output                          s_axis0_tready,

        `ifdef en_axis1
        // unsegmented AXIS1 interface
        (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis1_pkt_in TDATA" *)
        input [`unseg_axis_w-1:0]       s_axis1_tdata,
        (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis1_pkt_in TKEEP" *)
        input [(`unseg_axis_w/8)-1:0]   s_axis1_tkeep,
        (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis1_pkt_in TLAST" *)
        input                           s_axis1_tlast,
		(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis1_pkt_in TUSER" *)
        input                           s_axis1_tuser,
        (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis1_pkt_in TVALID" *)
        input                           s_axis1_tvalid,
        (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis1_pkt_in TREADY" *)
        output                          s_axis1_tready,
        `endif

        // Statistics
        `ifdef debug_en
        output wire error_missing_sop,
        output wire error_broken_pkt_out,
        output wire error_broken_pkt_in,
        `endif
        `ifdef statistics_en
        `ifdef en_axis1
        output wire [63: 0] p1_pkt_in_cnt,
        output wire [63: 0] p1_err_pkt_in_cnt,
        output wire [63: 0] p1_pkt_in_byte_cnt,
        output wire [63: 0] p0_pkt_in_cnt,
        output wire [63: 0] p0_err_pkt_in_cnt,
        output wire [63: 0] p0_pkt_in_byte_cnt,
        `endif
        output wire [63: 0] total_pkt_in_cnt,
        output wire [63: 0] total_err_pkt_in_cnt,
        output wire [63: 0] total_pkt_in_byte_cnt,
        output wire [63: 0] total_pkt_out_cnt,
        output wire [63: 0] total_err_pkt_out_cnt,
        output wire [63: 0] total_pkt_out_byte_cnt,
        `endif
        input wire tx_axis_tready_in,
        output wire tx_axis_tvalid_out
        );

//-----------------------------------------------------------------------------------------------------------------------

localparam P_MARK_DEBUG = "false";

localparam seg_mty_w = $clog2(`segment_width/8);
`ifdef data_rate_200
localparam pkt_array_depth = `pktarray_depth/2;
`else
localparam pkt_array_depth = `pktarray_depth;
`endif
localparam local_buff_depth = 16;
localparam io_buff_depth = 32;

// Packet block size
// Block size should be sufficient to hold atleast one complete packet of the maximum expected size.
// Also block size should be a power of 2

`ifdef data_rate_200
localparam pkt_blk_depth = 512;
localparam input_buffer_depth = pkt_blk_depth;
localparam output_buffer_depth = input_buffer_depth*8*`num_axis_ports;
`else
localparam pkt_blk_depth = 512;
localparam input_buffer_depth = pkt_blk_depth;
localparam output_buffer_depth = input_buffer_depth*4*`num_axis_ports;
`endif

//-----------------------------------------------------------------------------------------------------------------------

wire aclk_axis_unseg;
wire aresetn_axis_unseg;

`ifdef independant_clk
    assign aclk_axis_unseg = aclk_axis_unseg_in;
    assign aresetn_axis_unseg = aresetn_axis_unseg_in;
`else
    assign aclk_axis_unseg = aclk_axis_seg_in;
    assign aresetn_axis_unseg = aresetn_axis_seg_in;
`endif

//-----------------------------------------------------------------------------------------------------------------------

//----------------- Input Stream buffer

wire [`unseg_axis_w-1:0] s_axis_tdata_in [`num_axis_ports-1:0];
wire [(`unseg_axis_w/8)-1:0] s_axis_tkeep_in [`num_axis_ports-1:0];
wire [`num_axis_ports-1:0] s_axis_tvalid_in;
wire [`num_axis_ports-1:0] s_axis_tlast_in;
wire [`num_axis_ports-1:0] s_axis_tuser_in;
wire [`num_axis_ports-1:0] s_axis_tready_in;

wire axis_pkt_blk_rdy_flg;
wire axis_pkt_blk_rdy_p;
reg axis_pkt_blk_rdy_flg_clr;

assign s_axis_tdata_in[0] 	= s_axis0_tdata;
assign s_axis_tkeep_in[0] 	= s_axis0_tkeep;
assign s_axis_tvalid_in[0] 	= s_axis0_tvalid & (~axis_pkt_blk_rdy_flg);
assign s_axis_tlast_in[0] 	= s_axis0_tlast;
assign s_axis_tuser_in[0] 	= s_axis0_tuser;
assign s_axis0_tready		= s_axis_tready_in[0] & (~axis_pkt_blk_rdy_flg);

`ifdef en_axis1
assign s_axis_tdata_in[1] 	= s_axis1_tdata;
assign s_axis_tkeep_in[1] 	= s_axis1_tkeep;
assign s_axis_tvalid_in[1] 	= s_axis1_tvalid & (~axis_pkt_blk_rdy_flg);
assign s_axis_tlast_in[1] 	= s_axis1_tlast;
assign s_axis_tuser_in[1] 	= s_axis1_tuser;
assign s_axis1_tready 		= s_axis_tready_in[1] & (~axis_pkt_blk_rdy_flg);
`endif

wire [`unseg_axis_w-1:0] axis_tdata_c [`num_axis_ports-1:0];
wire [(`unseg_axis_w/8)-1:0] axis_tkeep_c [`num_axis_ports-1:0];
wire [`num_axis_ports-1:0] axis_tvalid_c;
wire [`num_axis_ports-1:0] axis_tlast_c;
wire [`num_axis_ports-1:0] axis_tuser_c;
wire [`num_axis_ports-1:0] axis_tready_c;

wire [`num_axis_ports-1:0] axis_in_buff_pfull;
wire [`num_axis_ports-1:0] axis_in_buff_pempty;
wire [`num_axis_ports-1:0] almost_full_axis;
wire [`num_axis_ports-1:0] almost_empty_axis;

wire [`num_axis_ports-1:0] axis_inbuff_pfull;
wire [`num_axis_ports-1:0] axis_inbuff_aempty;

wire [$clog2(input_buffer_depth):0] axis_inbuff_wrcnt [`num_axis_ports-1:0];

`ifdef debug_en

reg [`num_axis_ports-1:0] err_boken_pkt, err_boken_pkt_tlst;

genvar a1;
integer a2;

generate

for (a1=0; a1<`num_axis_ports; a1=a1+1) begin
    always @ (posedge aclk_axis_unseg) begin
        if (!aresetn_axis_unseg)
			err_boken_pkt[a1]	<= 1'b0;
		else
			err_boken_pkt[a1]	<= s_axis_tvalid_in[a1] & s_axis_tready_in[a1] & ~axis_pkt_blk_rdy_flg & ~s_axis_tlast_in[a1] & ~(&s_axis_tkeep_in[a1]);
	end
end

for (a1=0; a1<`num_axis_ports; a1=a1+1) begin
    always @ (posedge aclk_axis_unseg) begin
        if (!aresetn_axis_unseg)
			err_boken_pkt_tlst[a1] = 1'b0;
		else begin
			err_boken_pkt_tlst[a1] = 1'b0;
			if (s_axis_tlast_in[a1]) begin
				if (!err_boken_pkt_tlst[a1]) begin
					for (a2=0; a2<(`unseg_axis_w/8)-2; a2=a2+1) begin
						if (s_axis_tkeep_in[a1][a2+1] && !s_axis_tkeep_in[a1][a2])
							err_boken_pkt_tlst[a1] = 1'b1;
						else
							err_boken_pkt_tlst[a1] = 1'b0;
					end
				end
			end else
				err_boken_pkt_tlst[a1] = 1'b0;
		end
	end
end


endgenerate

assign error_broken_pkt_in = (|err_boken_pkt) | (|(err_boken_pkt_tlst & s_axis_tvalid_in & s_axis_tready_in & ~axis_pkt_blk_rdy_flg));

`endif

genvar a;
generate
	for (a=0; a<`num_axis_ports; a=a+1) begin
		assign axis_inbuff_pfull[a] = axis_in_buff_pfull[a];
		assign axis_inbuff_aempty[a] = almost_empty_axis[a];
		xpm_fifo_axis #(
			.CASCADE_HEIGHT(0),
			.CDC_SYNC_STAGES(3),
			.CLOCKING_MODE("common_clock"),
			.ECC_MODE("no_ecc"),
			.FIFO_DEPTH(input_buffer_depth),
			.FIFO_MEMORY_TYPE("auto"),
			.PACKET_FIFO("true"),
			.PROG_EMPTY_THRESH(10),
			.PROG_FULL_THRESH(input_buffer_depth-5),
			.RD_DATA_COUNT_WIDTH($clog2(input_buffer_depth)+1),
			.RELATED_CLOCKS(0),
			.SIM_ASSERT_CHK(0),
			.TDATA_WIDTH(`unseg_axis_w),
			.TDEST_WIDTH(1),
			.TID_WIDTH(1),
			.TUSER_WIDTH(1),
			.USE_ADV_FEATURES("0803"),
			.WR_DATA_COUNT_WIDTH($clog2(input_buffer_depth)+1)
			)
		xpm_fifo_axis_unseg_in (
			.m_aclk(aclk_axis_unseg),
			.m_axis_tready(axis_tready_c[a]),
			.m_axis_tdata(axis_tdata_c[a]),
			.m_axis_tkeep(axis_tkeep_c[a]),
			.m_axis_tlast(axis_tlast_c[a]),
			.m_axis_tuser(axis_tuser_c[a]),
			.m_axis_tvalid(axis_tvalid_c[a]),
			.s_aclk(aclk_axis_unseg),
			.s_aresetn(aresetn_axis_unseg),
			.prog_full_axis(axis_in_buff_pfull[a]),
			.prog_empty_axis(axis_in_buff_pempty[a]),
			.almost_full_axis(almost_full_axis[a]),
			.almost_empty_axis(almost_empty_axis[a]),
			.s_axis_tready(s_axis_tready_in[a]),
			.s_axis_tdata(s_axis_tdata_in[a]),
			.s_axis_tkeep(s_axis_tkeep_in[a]),
			.s_axis_tlast(s_axis_tlast_in[a]),
			.s_axis_tuser(s_axis_tuser_in[a]),
			.s_axis_tvalid(s_axis_tvalid_in[a]),
			.wr_data_count_axis(axis_inbuff_wrcnt[a])
			);
	end
endgenerate

wire [`segment_width-1:0] axis_tdata_buff [`num_axis_ports-1:0][(`unseg_axis_w/`segment_width)-1:0];
wire [(`segment_width/8)-1:0] axis_tkeep_buff [`num_axis_ports-1:0][(`unseg_axis_w/`segment_width)-1:0];
wire [`num_axis_ports-1:0] axis_tvalid_buff;
wire [`num_axis_ports-1:0] axis_tlast_buff;
wire [`num_axis_ports-1:0] axis_tuser_buff;
wire [`num_axis_ports-1:0] axis_tready_buff;

genvar aa, ab;
generate
	for (aa=0; aa<`num_axis_ports; aa=aa+1) begin
		assign axis_tready_c[aa]	= axis_tready_buff[aa];
		assign axis_tvalid_buff[aa] = axis_tvalid_c[aa];
		assign axis_tlast_buff[aa] 	= axis_tlast_c[aa];
		assign axis_tuser_buff[aa] 	= axis_tuser_c[aa];
		for (ab=0; ab<(`unseg_axis_w/`segment_width); ab=ab+1) begin
			assign axis_tdata_buff[aa][ab] = axis_tdata_c[aa][((ab+1)*`segment_width)-1:(ab*`segment_width)];
			assign axis_tkeep_buff[aa][ab] = axis_tkeep_c[aa][((ab+1)*(`segment_width/8))-1:(ab*(`segment_width/8))];
		end
	end
endgenerate

//----------------- Read packets as a block

reg [$clog2(input_buffer_depth):0] axis_pkt_in_cnt [`num_axis_ports-1:0];
reg [$clog2(input_buffer_depth)+1:0] num_pkt_to_rd_reg [`num_axis_ports-1:0];
reg axis_in_buff_pfull_q, axis_in_buff_pfull_qq;

wire out_buff_afull;
wire out_buff_pfull;

genvar b;
for (b=0; b<`num_axis_ports; b=b+1) begin
    always @ (posedge aclk_axis_unseg) begin
        if (!aresetn_axis_unseg)
            axis_pkt_in_cnt[b]	<= 'd0;
        else if (axis_pkt_blk_rdy_p)
             axis_pkt_in_cnt[b] <= 'd0;
        else if (s_axis_tvalid_in[b] && s_axis_tready_in[b] && s_axis_tlast_in[b])
            axis_pkt_in_cnt[b]	<= axis_pkt_in_cnt[b] + 'd1;
    end
end

reg [$clog2(pkt_blk_depth*4):0] axis_pkt_flush_cnt;

`ifdef en_axis1

always @ (posedge aclk_axis_unseg) begin
    if (!aresetn_axis_unseg)
        axis_pkt_flush_cnt  <= 'd0;
    else if (axis_pkt_blk_rdy_p)
        axis_pkt_flush_cnt  <= 'd0;
    else if ((|axis_pkt_in_cnt[1] || |axis_pkt_in_cnt[0]) && !out_buff_pfull)
        axis_pkt_flush_cnt  <= axis_pkt_flush_cnt + 1;
    else
        axis_pkt_flush_cnt  <= 'd0;
end

`else

always @ (posedge aclk_axis_unseg) begin
    if (!aresetn_axis_unseg)
        axis_pkt_flush_cnt  <= 'd0;
    else if (axis_pkt_blk_rdy_p)
        axis_pkt_flush_cnt  <= 'd0;
    else if (|axis_pkt_in_cnt[0] && !out_buff_pfull)
        axis_pkt_flush_cnt  <= axis_pkt_flush_cnt + 1;
    else
        axis_pkt_flush_cnt  <= 'd0;
end

`endif

reg [`num_axis_ports-1:0] axis_pkt_blk_rd;
reg unseg_pkt_blk_rd;

assign axis_pkt_blk_rdy_flg = axis_in_buff_pfull_q;

wire [`num_axis_ports-1:0] unseg_buff_empty;

always @ (posedge aclk_axis_unseg) begin
    axis_pkt_blk_rdy_flg_clr	<= axis_pkt_blk_rdy_p;
    axis_in_buff_pfull_qq   	<= axis_in_buff_pfull_q;
    if (!aresetn_axis_unseg)
        axis_in_buff_pfull_q    <= 1'b0;
    else if (axis_pkt_blk_rdy_flg_clr | (|axis_pkt_blk_rd))
        axis_in_buff_pfull_q    <= 1'b0;
    else
        axis_in_buff_pfull_q    <= ((~(&axis_inbuff_aempty) & |axis_inbuff_pfull) | axis_pkt_flush_cnt[$clog2(pkt_blk_depth*4)]) & ~out_buff_pfull & (&unseg_buff_empty);
end

assign axis_pkt_blk_rdy_p = axis_in_buff_pfull_q & ~axis_in_buff_pfull_qq;

reg axis_pkt_blk_rdy_rp_q;

always @ (posedge aclk_axis_unseg) begin
	axis_pkt_blk_rdy_rp_q	<= axis_pkt_blk_rdy_p;
end

reg [$clog2(input_buffer_depth):0] axis_pkt_rd_cnt [`num_axis_ports-1:0];
wire [`num_axis_ports-1:0] axis_pkt_blk_rd_end;

genvar b0;
generate
for (b0=0; b0<`num_axis_ports; b0=b0+1) begin
always @ (posedge aclk_axis_unseg) begin
    if (!aresetn_axis_unseg) begin
        num_pkt_to_rd_reg[b0]   <= 'd0;
        axis_pkt_blk_rd[b0]     <= 1'b0;
    end else if (axis_pkt_blk_rdy_p) begin
        num_pkt_to_rd_reg[b0]   <= axis_pkt_in_cnt[b0];
        axis_pkt_blk_rd[b0]     <= |axis_pkt_in_cnt[b0];
    end else begin
        num_pkt_to_rd_reg[b0]   <= num_pkt_to_rd_reg[b0];
        if (axis_pkt_blk_rd_end[b0])
            axis_pkt_blk_rd[b0]	<= 1'b0;
        else
            axis_pkt_blk_rd[b0]	<= axis_pkt_blk_rd[b0];
    end
end
end
endgenerate

genvar b1;
generate
for (b1=0; b1<`num_axis_ports; b1=b1+1) begin
    always @ (posedge aclk_axis_unseg) begin
        if (!aresetn_axis_unseg)
            axis_pkt_rd_cnt[b1] <= 'd0;
        else if (axis_pkt_blk_rd_end[b1])
            axis_pkt_rd_cnt[b1] <= 'd0;
        else if (axis_tvalid_buff[b1] && axis_tready_buff[b1] && axis_tlast_buff[b1])
            axis_pkt_rd_cnt[b1] <= axis_pkt_rd_cnt[b1] + 'd1;
    end
end
endgenerate

genvar b3;
generate
for (b3=0; b3<`num_axis_ports; b3=b3+1) begin
    assign axis_pkt_blk_rd_end[b3] = (axis_pkt_blk_rd[b3] && axis_pkt_rd_cnt[b3] >= num_pkt_to_rd_reg[b3]) ? 1'b1 : 1'b0;
end

endgenerate

//-----------------------------------------------------------------------------------------------------------------------

//-----------------  Stream to segment conversion

reg [(`unseg_axis_w/`segment_width)-1:0] unseg_sop [`num_axis_ports-1:0];
reg [(`unseg_axis_w/`segment_width)-1:0] unseg_eop [`num_axis_ports-1:0];
reg [(`unseg_axis_w/`segment_width)-1:0] unseg_err [`num_axis_ports-1:0];
reg [(`unseg_axis_w/`segment_width)-1:0] unseg_val [`num_axis_ports-1:0];
wire [(`unseg_axis_w/`segment_width)-1:0] unseg_blk_end [`num_axis_ports-1:0];
wire [seg_mty_w-1:0] unseg_mty_c [`num_axis_ports-1:0] [(`unseg_axis_w/`segment_width)-1:0];
reg [seg_mty_w-1:0] unseg_mty [`num_axis_ports-1:0] [(`unseg_axis_w/`segment_width)-1:0];
reg [`segment_width-1:0] unseg_dat [`num_axis_ports-1:0] [(`unseg_axis_w/`segment_width)-1:0];

reg [`num_axis_ports-1:0] pkt_start;

genvar c, cc;
generate
for (c=0; c<`num_axis_ports; c=c+1) begin
    always @ (posedge aclk_axis_unseg) begin
        if (!aresetn_axis_unseg)
            pkt_start[c]	<= 1'b1;
        else begin
            if(axis_tvalid_buff[c] & !axis_tlast_buff[c] & axis_tready_buff[c])
                pkt_start[c]   <= 1'b0;
            else if (axis_tvalid_buff[c] & axis_tlast_buff[c] & axis_tready_buff[c])
                pkt_start[c]   <= 1'b1;
        end
        unseg_sop[c][0] <= (axis_tready_buff[c] & pkt_start[c] & axis_tvalid_buff[c]);
    end
    for (cc=0; cc<((`unseg_axis_w/`segment_width)-1); cc=cc+1) begin
        always @ (posedge aclk_axis_unseg)
            unseg_sop[c][cc+1] <= 1'b0;
    end
end
endgenerate

wire tdata_available [`num_axis_ports-1:0] [(`unseg_axis_w/`segment_width)-1:0];

genvar d, dd;
generate
for (d=0; d<`num_axis_ports; d=d+1) begin
    for (dd=0; dd<(`unseg_axis_w/`segment_width); dd=dd+1) begin
        assign tdata_available[d][dd] = |axis_tkeep_buff[d][dd] & axis_tvalid_buff[d];
    end
end
endgenerate

genvar e, ee;
generate
for (e=0; e<`num_axis_ports; e=e+1) begin
    always @ (posedge aclk_axis_unseg) begin
        unseg_eop[e][(`unseg_axis_w/`segment_width)-1] <= tdata_available[e][(`unseg_axis_w/`segment_width)-1] & axis_tlast_buff[e];
        unseg_err[e][(`unseg_axis_w/`segment_width)-1] <= tdata_available[e][(`unseg_axis_w/`segment_width)-1] & axis_tlast_buff[e] & axis_tuser_buff[e];
    end
    for (ee=0; ee<((`unseg_axis_w/`segment_width)-1); ee=ee+1) begin
        always @ (posedge aclk_axis_unseg) begin
            unseg_eop[e][ee] <= tdata_available[e][ee] & ~tdata_available[e][ee+1] & axis_tlast_buff[e];
            unseg_err[e][ee] <= tdata_available[e][ee] & ~tdata_available[e][ee+1] & axis_tlast_buff[e] & axis_tuser_buff[e];
        end
    end
end
endgenerate

genvar f, ff;
generate
for (f=0; f<`num_axis_ports; f=f+1) begin
    for (ff=0; ff<((`unseg_axis_w/`segment_width)); ff=ff+1) begin
        tkeep_to_mty u_tkeep_to_mty
        (
        .tkeep_in(axis_tkeep_buff[f][ff]),
        .mty_out(unseg_mty_c[f][ff])
        );
        always @ (posedge aclk_axis_unseg) begin
            unseg_dat[f][ff] <= axis_tdata_buff[f][ff];
            unseg_val[f][ff] <= tdata_available[f][ff] & axis_tvalid_buff[f] & axis_tready_buff[f];
            unseg_mty[f][ff] <= unseg_mty_c[f][ff];
       end
    end
end
endgenerate

genvar f1, f2;
generate
for (f1=0; f1<`num_axis_ports; f1=f1+1) begin
    for (f2=0; f2<((`unseg_axis_w/`segment_width)); f2=f2+1) begin
        assign unseg_blk_end[f1][f2] = unseg_eop[f1][f2] & axis_pkt_blk_rd_end[f1];
    end
end
endgenerate

reg [(`unseg_axis_w/`segment_width)-1:0] unseg_sop_q [`num_axis_ports-1:0];
reg [(`unseg_axis_w/`segment_width)-1:0] unseg_eop_q [`num_axis_ports-1:0];
reg [(`unseg_axis_w/`segment_width)-1:0] unseg_err_q [`num_axis_ports-1:0];
reg [(`unseg_axis_w/`segment_width)-1:0] unseg_val_q [`num_axis_ports-1:0];
reg [(`unseg_axis_w/`segment_width)-1:0] unseg_blk_end_q [`num_axis_ports-1:0];
reg [`segment_width-1:0] unseg_dat_q [`num_axis_ports-1:0] [(`unseg_axis_w/`segment_width)-1:0];
reg [seg_mty_w-1:0] unseg_mty_q [`num_axis_ports-1:0] [(`unseg_axis_w/`segment_width)-1:0];

genvar f3, f4;
generate
for (f3=0; f3<`num_axis_ports; f3=f3+1) begin
    for (f4=0; f4<((`unseg_axis_w/`segment_width)); f4=f4+1) begin
		always @ (posedge aclk_axis_unseg) begin
			unseg_sop_q[f3][f4] <= unseg_sop[f3][f4];
			unseg_eop_q[f3][f4] <= unseg_eop[f3][f4];
			unseg_err_q[f3][f4] <= unseg_err[f3][f4];
			unseg_dat_q[f3][f4] <= unseg_dat[f3][f4];
			unseg_val_q[f3][f4] <= unseg_val[f3][f4];
            unseg_mty_q[f3][f4] <= unseg_mty[f3][f4];
            unseg_blk_end_q[f3][f4] <= unseg_eop[f3][f4] & axis_pkt_blk_rd_end[f3];
		end
	end
end
endgenerate

//-----------------------------------------------------------------------------------------------------------------------

//----------------- Segment Buffer

wire [(`unseg_axis_w/`segment_width)-1:0] unseg_buf_aempty [`num_axis_ports-1:0];
wire [(`unseg_axis_w/`segment_width)-1:0] unseg_buf_afull [`num_axis_ports-1:0];
wire [(`unseg_axis_w/`segment_width)-1:0] unseg_buf_pfull [`num_axis_ports-1:0];
wire [(`unseg_axis_w/`segment_width)-1:0] unseg_buf_empty [`num_axis_ports-1:0];
wire [(`unseg_axis_w/`segment_width)-1:0] unseg_buf_data_valid [`num_axis_ports-1:0];
wire [(`unseg_axis_w/`segment_width)-1:0] unseg_buf_rd_rst_busy [`num_axis_ports-1:0];
wire [(`unseg_axis_w/`segment_width)-1:0] unseg_buf_wr_rst_busy [`num_axis_ports-1:0];

wire [(`unseg_axis_w/`segment_width)-1:0] unseg_sop_buf [`num_axis_ports-1:0];
wire [(`unseg_axis_w/`segment_width)-1:0] unseg_eop_buf [`num_axis_ports-1:0];
wire [(`unseg_axis_w/`segment_width)-1:0] unseg_err_buf [`num_axis_ports-1:0];
wire [(`unseg_axis_w/`segment_width)-1:0] unseg_val_buf_c [`num_axis_ports-1:0];
wire [(`unseg_axis_w/`segment_width)-1:0] unseg_val_buf [`num_axis_ports-1:0];
wire [(`unseg_axis_w/`segment_width)-1:0] unseg_blk_end_buf [`num_axis_ports-1:0];
wire [seg_mty_w-1:0] unseg_mty_buf [`num_axis_ports-1:0] [(`unseg_axis_w/`segment_width)-1:0];
wire [`segment_width-1:0] unseg_dat_buf [`num_axis_ports-1:0] [(`unseg_axis_w/`segment_width)-1:0];

wire [`num_axis_ports-1:0] unseg_buf_wr_en;
reg [`num_axis_ports-1:0] unseg_buf_rd_en;

wire pkt_array_buf_pfull;

wire [`num_axis_ports-1:0] unseg_buf_rd_en_c;

reg axis_blk_rd_q, axis_blk_rd_qq;
wire axis_blk_rd_rp;
wire unseg_pkt_blk_end;

always @ (posedge aclk_axis_unseg) begin
	axis_blk_rd_q	<= |axis_pkt_blk_rd;
	axis_blk_rd_qq	<= axis_blk_rd_q;
end

assign axis_blk_rd_rp = axis_blk_rd_q & ~axis_blk_rd_qq;

always @ (posedge aclk_axis_unseg) begin
	if (!aresetn_axis_unseg)
        unseg_pkt_blk_rd   <= 1'b0;
    else if (unseg_pkt_blk_end)
        unseg_pkt_blk_rd   <= 1'b0;
    else if (axis_blk_rd_rp)
        unseg_pkt_blk_rd   <= 1'b1;
    else
        unseg_pkt_blk_rd   <= unseg_pkt_blk_rd;
end

genvar g, gg;
generate
for (g=0; g<`num_axis_ports; g=g+1) begin
    assign unseg_buf_wr_en[g] = unseg_val_q[g][0];
    assign axis_tready_buff[g] = axis_pkt_blk_rd[g] & ~axis_pkt_blk_rd_end[g] & ~(|unseg_buf_pfull[g]);
	assign unseg_buff_empty[g] = &unseg_buf_empty[g];
    for (gg=0; gg<((`unseg_axis_w/`segment_width)); gg=gg+1) begin
        assign unseg_val_buf[g][gg] = unseg_val_buf_c[g][gg] & unseg_buf_data_valid[g][gg];
        xpm_fifo_sync #(
            .CASCADE_HEIGHT(0),
            .DOUT_RESET_VALUE("0"),
            .ECC_MODE("no_ecc"),
            .FIFO_MEMORY_TYPE("auto"),
            .FIFO_READ_LATENCY(1),
            .FIFO_WRITE_DEPTH(local_buff_depth),
            .FULL_RESET_VALUE(0),
            .PROG_EMPTY_THRESH(10),
            .PROG_FULL_THRESH(local_buff_depth-5),
            .RD_DATA_COUNT_WIDTH(1),
            .READ_DATA_WIDTH(`segment_width+seg_mty_w+5),
            .READ_MODE("fwft"),
            .SIM_ASSERT_CHK(0),
            .USE_ADV_FEATURES("100A"),
            .WAKEUP_TIME(0),
            .WRITE_DATA_WIDTH(`segment_width+seg_mty_w+5),
            .WR_DATA_COUNT_WIDTH(1)
            )
        xpm_fifo_sync_unseg_seg_buff (
            .almost_empty(unseg_buf_aempty[g][gg]),
            .almost_full(unseg_buf_afull[g][gg]),
            .data_valid(unseg_buf_data_valid[g][gg]),
            .dbiterr(),
            .dout({unseg_blk_end_buf[g][gg],unseg_err_buf[g][gg],unseg_eop_buf[g][gg],unseg_sop_buf[g][gg],unseg_mty_buf[g][gg],unseg_val_buf_c[g][gg],unseg_dat_buf[g][gg]}),
            .empty(unseg_buf_empty[g][gg]),
            .full(),
            .overflow(),
            .prog_empty(),
            .prog_full(unseg_buf_pfull[g][gg]),
            .rd_data_count(),
            .rd_rst_busy(unseg_buf_rd_rst_busy[g][gg]),
            .sbiterr(),
            .underflow(),
            .wr_ack(),
            .wr_data_count(),
            .wr_rst_busy(unseg_buf_wr_rst_busy[g][gg]),
            .din({unseg_blk_end_q[g][gg],unseg_err_q[g][gg],unseg_eop_q[g][gg],unseg_sop_q[g][gg],unseg_mty_q[g][gg],unseg_val_q[g][gg],unseg_dat_q[g][gg]}),
            .injectdbiterr(1'b0),
            .injectsbiterr(1'b0),
            .rd_en(unseg_buf_rd_en_c[g]),
            .rst(!aresetn_axis_unseg),
            .sleep(1'b0),
            .wr_clk(aclk_axis_unseg),
            .wr_en(unseg_buf_wr_en[g])
            );
    end
end
endgenerate

//-----------------------------------------------------------------------------------------------------------------------

//----- Packet read enable generation, (read arbitration, based on packet availability in input ports)

reg only_port1_active, only_port0_active;

`ifdef en_axis1			// Below logic assumes max no of ports is 2 (applicable for 400G)

always @ (posedge aclk_axis_unseg) begin
	if (!aresetn_axis_unseg)
		only_port0_active	<= 1'b0;
	else if (axis_pkt_blk_rdy_p)
		if (axis_inbuff_aempty[1])
			only_port0_active	<= 1'b1;
		else
			only_port0_active	<= 1'b0;
	else
		only_port0_active	<= only_port0_active;
end

always @ (posedge aclk_axis_unseg) begin
	if (!aresetn_axis_unseg)
		only_port1_active	<= 1'b0;
	else if (axis_pkt_blk_rdy_p)
		if (axis_inbuff_aempty[0])
			only_port1_active	<= 1'b1;
		else
			only_port1_active	<= 1'b0;
	else
		only_port1_active	<= only_port1_active;
end

reg pkt_port_sel;

assign unseg_buf_rd_en_c[0] = (unseg_buf_rd_en[0] | ((|unseg_eop_buf[1] & (|unseg_val_buf[1])) & !(|unseg_buf_empty[0])) & ~pkt_array_buf_pfull);
assign unseg_buf_rd_en_c[1] = (unseg_buf_rd_en[1] | ((|unseg_eop_buf[0] & (|unseg_val_buf[0])) & !(|unseg_buf_empty[1])) & ~pkt_array_buf_pfull);

always @ (posedge aclk_axis_unseg) begin
	if (!aresetn_axis_unseg) begin
		pkt_port_sel		<= 1'b0;
		unseg_buf_rd_en[0]	<= 1'b0;
		unseg_buf_rd_en[1]	<= 1'b0;
	end else if (axis_pkt_blk_rdy_rp_q) begin
		if (only_port1_active) begin
			pkt_port_sel		<= 1'b1;
			unseg_buf_rd_en[0]	<= 1'b0;
			unseg_buf_rd_en[1]	<= 1'b0;
		end else if (only_port0_active) begin
			pkt_port_sel		<= 1'b0;
			unseg_buf_rd_en[1]	<= 1'b0;
			unseg_buf_rd_en[1]	<= 1'b0;
		end else
			pkt_port_sel		<= pkt_port_sel;
	end else if (!pkt_array_buf_pfull) begin
		if (pkt_port_sel) begin
		    unseg_buf_rd_en[0]	<= 1'b0;
			if (|unseg_eop_buf[1] && |unseg_val_buf[1]) begin
                if (|unseg_buf_empty[1]) begin
				    unseg_buf_rd_en[0]	<= 1'b1;
					unseg_buf_rd_en[1]	<= 1'b0;
				    pkt_port_sel     	<= 1'b0;
				end else if (!(|unseg_buf_empty[0])) begin
					unseg_buf_rd_en[0]	<= 1'b1;
					unseg_buf_rd_en[1]	<= 1'b0;
					pkt_port_sel 		<= 1'b0;
                end else
					unseg_buf_rd_en[1]	<= 1'b1;
            end else if (|unseg_eop_buf[1] && !(|unseg_buf_empty[0])) begin
	               unseg_buf_rd_en[0]  	<= 1'b1;
	               unseg_buf_rd_en[1]  	<= 1'b0;
	               pkt_port_sel 	   	<= 1'b0;
	        end	else if(!(|unseg_buf_empty[1])) begin
	           unseg_buf_rd_en[1]		<= 1'b1;
	        end else begin
	           unseg_buf_rd_en[1]		<= 1'b0;
	        end
		end else begin
		  unseg_buf_rd_en[1]	<= 1'b0;
	       if (|unseg_eop_buf[0] && |unseg_val_buf[0]) begin
				if (|unseg_buf_empty[0]) begin
				    unseg_buf_rd_en[1]	<= 1'b1;
					unseg_buf_rd_en[0]	<= 1'b0;
				    pkt_port_sel     	<= 1'b1;
				end else if (!(|unseg_buf_empty[1])) begin
					unseg_buf_rd_en[1]	<= 1'b1;
					unseg_buf_rd_en[0]	<= 1'b0;
					pkt_port_sel     	<= 1'b1;
				end else
					unseg_buf_rd_en[0]	<= 1'b1;
	       end else if (|unseg_eop_buf[0] && !(|unseg_buf_empty[1])) begin
	           unseg_buf_rd_en[1]	<= 1'b1;
	           unseg_buf_rd_en[0]	<= 1'b0;
	           pkt_port_sel     	<= 1'b1;
	       end else if(!(|unseg_buf_empty[0])) begin
	           unseg_buf_rd_en[0]	<= 1'b1;
	       end else begin
	           unseg_buf_rd_en[0]	<= 1'b0;
	       end
		end
	end
end

`else				// only one port available

assign unseg_buf_rd_en_c[0] = unseg_buf_rd_en[0] & ~pkt_array_buf_pfull;

always @ (posedge aclk_axis_unseg) begin
	if (!aresetn_axis_unseg)
		unseg_buf_rd_en[0]	<= 1'b0;
	else if (!pkt_array_buf_pfull) begin
		if (|unseg_buf_empty[0])
			unseg_buf_rd_en[0]	<= 1'b0;
		else
			unseg_buf_rd_en[0]	<= 1'b1;
	end
end

`endif

`ifdef en_axis1

reg [`segment_width-1:0] seg_data_array [pkt_array_depth-1:0];
reg [seg_mty_w-1:0] seg_mty_array [pkt_array_depth-1:0];
reg [pkt_array_depth-1:0] seg_val_array;
reg [pkt_array_depth-1:0] seg_sop_array;
reg [pkt_array_depth-1:0] seg_eop_array;
reg [pkt_array_depth-1:0] seg_err_array;
reg [pkt_array_depth-1:0] seg_blk_end_array;

`else

reg [`segment_width-1:0] seg_data_array [(`unseg_axis_w/`segment_width)-1:0];
reg [seg_mty_w-1:0] seg_mty_array [(`unseg_axis_w/`segment_width)-1:0];
reg [(`unseg_axis_w/`segment_width)-1:0] seg_val_array;
reg [(`unseg_axis_w/`segment_width)-1:0] seg_sop_array;
reg [(`unseg_axis_w/`segment_width)-1:0] seg_eop_array;
reg [(`unseg_axis_w/`segment_width)-1:0] seg_err_array;
reg [(`unseg_axis_w/`segment_width)-1:0] seg_blk_end_array;

`endif

// Generate a flag indicate the end of a block(aligned with the eop of the last packet in the block)

wire [`num_axis_ports-1:0] unseg_blk_end_buf_val;

`ifdef en_axis1

reg [`num_axis_ports-1:0] unseg_blk_end_flg;

genvar h;
generate
for (h=0; h<`num_axis_ports; h=h+1) begin
    if (h == 0)
        always @ (posedge aclk_axis_unseg) begin
			if (!aresetn_axis_unseg | unseg_pkt_blk_end)
				unseg_blk_end_flg[h] <= 1'b0;
			else if (only_port1_active)
				unseg_blk_end_flg[h] <= 1'b0;
			else if (unseg_blk_end_flg[h])
	           if (|unseg_blk_end_buf[h+1] && |unseg_val_buf[h+1] && unseg_buf_rd_en_c[h+1])
	               unseg_blk_end_flg[h] <= 1'b0;
	           else
	               unseg_blk_end_flg[h] <= unseg_blk_end_flg[h];
	       else if (|unseg_blk_end_buf[h] && |unseg_val_buf[h] && unseg_buf_rd_en_c[h])
	           if (|unseg_blk_end_buf[h+1] && |unseg_val_buf[h+1] && unseg_buf_rd_en_c[h+1])
	               unseg_blk_end_flg[h] <= 1'b0;
	           else if (unseg_blk_end_flg[h+1])
	               unseg_blk_end_flg[h] <= 1'b0;
	           else
	               unseg_blk_end_flg[h] <= 1'b1;
	       else
	           unseg_blk_end_flg[h] <= unseg_blk_end_flg[h];
	   end
    else
        always @ (posedge aclk_axis_unseg) begin
			if (!aresetn_axis_unseg | unseg_pkt_blk_end)
				unseg_blk_end_flg[h] <= 1'b0;
			else if (only_port0_active)
				unseg_blk_end_flg[h] <= 1'b0;
	       else if (unseg_blk_end_flg[h])
	           if (|unseg_blk_end_buf[h-1] && |unseg_val_buf[h-1] && unseg_buf_rd_en_c[h-1])
	               unseg_blk_end_flg[h] <= 1'b0;
	           else
	               unseg_blk_end_flg[h] <= unseg_blk_end_flg[h];
	       else if (|unseg_blk_end_buf[h] && |unseg_val_buf[h] && unseg_buf_rd_en_c[h])
	           if (|unseg_blk_end_buf[h-1] && |unseg_val_buf[h-1] && unseg_buf_rd_en_c[h-1])
	               unseg_blk_end_flg[h] <= 1'b0;
	           else if (unseg_blk_end_flg[h-1])
	               unseg_blk_end_flg[h] <= 1'b0;
	           else
	               unseg_blk_end_flg[h] <= 1'b1;
	       else
	           unseg_blk_end_flg[h] <= unseg_blk_end_flg[h];
        end
end
endgenerate

`endif

`ifdef en_axis1

genvar h0;
generate
for (h0=0; h0<`num_axis_ports; h0=h0+1) begin
    if (h0 == 0)
        assign unseg_blk_end_buf_val[h0] = (unseg_blk_end_flg[h0+1] && (|unseg_blk_end_buf[h0] && unseg_buf_rd_en_c[h0] && |unseg_val_buf[h0])) ? 1'b1 : (|unseg_blk_end_buf[h0] && unseg_buf_rd_en_c[h0] && |unseg_val_buf[h0] && !(|unseg_val_buf[h0+1])) ? 1'b1 : (|unseg_blk_end_buf[h0] & unseg_buf_rd_en_c[h0] & |unseg_val_buf[h0]) & (|unseg_blk_end_buf[h0+1] & unseg_buf_rd_en_c[h0+1] & |unseg_val_buf[h0+1]);
    else
        assign unseg_blk_end_buf_val[h0] = (unseg_blk_end_flg[h0-1] && (|unseg_blk_end_buf[h0] && unseg_buf_rd_en_c[h0] && |unseg_val_buf[h0])) ? 1'b1 : (|unseg_blk_end_buf[h0] && unseg_buf_rd_en_c[h0] && |unseg_val_buf[h0] && !(|unseg_val_buf[h0-1])) ? 1'b1 : (|unseg_blk_end_buf[h0] & unseg_buf_rd_en_c[h0] & |unseg_val_buf[h0]) & (|unseg_blk_end_buf[h0-1] & unseg_buf_rd_en_c[h0-1] & |unseg_val_buf[h0-1]);
end
endgenerate

`else
	assign unseg_blk_end_buf_val[0] =  (|unseg_blk_end_buf[0] & |unseg_val_buf[0]);
`endif

assign unseg_pkt_blk_end = |unseg_blk_end_buf_val;

genvar hh;

`ifdef en_axis1

generate
for (hh=0; hh < (pkt_array_depth/2); hh = hh+1) begin
    always @ (posedge aclk_axis_unseg) begin
        if (pkt_port_sel) begin
            seg_data_array[hh]   						<= unseg_dat_buf[1][hh];
            seg_mty_array[hh]    						<= unseg_mty_buf[1][hh];
            seg_val_array[hh]    						<= unseg_val_buf[1][hh] & unseg_buf_rd_en_c[1];
            seg_sop_array[hh]    						<= unseg_sop_buf[1][hh];
            seg_eop_array[hh]    						<= unseg_eop_buf[1][hh];
            seg_err_array[hh]    						<= unseg_err_buf[1][hh];
            seg_blk_end_array[hh]    					<= unseg_blk_end_buf[1][hh] & unseg_blk_end_buf_val[1];
            seg_data_array[hh+(pkt_array_depth/2)]   	<= unseg_dat_buf[0][hh];
            seg_mty_array[hh+(pkt_array_depth/2)]    	<= unseg_mty_buf[0][hh];
            seg_val_array[hh+(pkt_array_depth/2)]    	<= unseg_val_buf[0][hh] & unseg_buf_rd_en_c[0];
            seg_sop_array[hh+(pkt_array_depth/2)]    	<= unseg_sop_buf[0][hh];
            seg_eop_array[hh+(pkt_array_depth/2)]    	<= unseg_eop_buf[0][hh];
            seg_err_array[hh+(pkt_array_depth/2)]    	<= unseg_err_buf[0][hh];
            seg_blk_end_array[hh+(pkt_array_depth/2)]   <= unseg_blk_end_buf[0][hh] & unseg_blk_end_buf_val[0];
        end else begin
            seg_data_array[hh]   						<= unseg_dat_buf[0][hh];
            seg_mty_array[hh]    						<= unseg_mty_buf[0][hh];
            seg_val_array[hh]    						<= unseg_val_buf[0][hh] & unseg_buf_rd_en_c[0];
            seg_sop_array[hh]    						<= unseg_sop_buf[0][hh];
            seg_eop_array[hh]    						<= unseg_eop_buf[0][hh];
            seg_err_array[hh]    						<= unseg_err_buf[0][hh];
            seg_blk_end_array[hh]    					<= unseg_blk_end_buf[0][hh] & unseg_blk_end_buf_val[0];
            seg_data_array[hh+(pkt_array_depth/2)]   	<= unseg_dat_buf[1][hh];
            seg_mty_array[hh+(pkt_array_depth/2)]    	<= unseg_mty_buf[1][hh];
            seg_val_array[hh+(pkt_array_depth/2)]    	<= unseg_val_buf[1][hh] & unseg_buf_rd_en_c[1];
            seg_sop_array[hh+(pkt_array_depth/2)]    	<= unseg_sop_buf[1][hh];
            seg_eop_array[hh+(pkt_array_depth/2)]    	<= unseg_eop_buf[1][hh];
            seg_err_array[hh+(pkt_array_depth/2)]    	<= unseg_err_buf[1][hh];
            seg_blk_end_array[hh+(pkt_array_depth/2)]   <= unseg_blk_end_buf[1][hh] & unseg_blk_end_buf_val[1];
        end
	end
end
endgenerate

`else

generate
for (hh=0; hh < pkt_array_depth; hh = hh+1) begin
    always @ (posedge aclk_axis_unseg) begin
        seg_data_array[hh]   	<= unseg_dat_buf[0][hh];
        seg_mty_array[hh]    	<= unseg_mty_buf[0][hh];
        seg_val_array[hh]    	<= unseg_val_buf[0][hh] & unseg_buf_rd_en_c[0];
        seg_sop_array[hh]    	<= unseg_sop_buf[0][hh];
        seg_eop_array[hh]    	<= unseg_eop_buf[0][hh];
        seg_err_array[hh]    	<= unseg_err_buf[0][hh];
        seg_blk_end_array[hh]	<= unseg_blk_end_buf[0][hh];
    end
end
endgenerate

`endif

//-----------------------------------------------------------------------------------------------------------------------

//----------------- Segment array

// Pack the segments

reg [`segment_width-1:0] pkt_data_array [(pkt_array_depth*2)-1:0];
reg [seg_mty_w-1:0] pkt_mty_array [(pkt_array_depth*2)-1:0];
reg [(pkt_array_depth*2)-1:0] pkt_val_array0;
reg [(pkt_array_depth*2)-1:0] pkt_val_array00;
reg [(pkt_array_depth*2)-1:0] pkt_val_array1;
reg [(pkt_array_depth*2)-1:0] pkt_val_array2;
reg [(pkt_array_depth*2)-1:0] pkt_val_array;
reg [(pkt_array_depth*2)-1:0] pkt_sop_array;
reg [(pkt_array_depth*2)-1:0] pkt_eop_array;
reg [(pkt_array_depth*2)-1:0] pkt_err_array;
reg [(pkt_array_depth*2)-1:0] pkt_blk_end_array;
reg [(pkt_array_depth*2)-1:0] pkt_blk_end_array1;

reg [$clog2((pkt_array_depth*2))-1:0] pkt_seg_sel_reg [(pkt_array_depth*2)-1:0];
reg [$clog2((pkt_array_depth*2))-1:0] pkt_seg_sel_reg1 [(pkt_array_depth*2)-1:0];

wire pkt_arry_clr_p0;
wire pkt_arry_clr_p1;
wire pkt_arry_clr_p2;
wire pkt_arry_clr_p3;

reg [$clog2((pkt_array_depth*2))-1:0] pkt_array_ptr1;
reg [$clog2((pkt_array_depth*2))-1:0] pkt_array_ptr2;

wire p0_flushout_c;
wire p1_flushout_c;
wire p2_flushout_c;
wire p3_flushout_c;

assign p0_flushout_c = pkt_val_array1[0] & |(pkt_blk_end_array1[((pkt_array_depth/2)*1)-1:0]);
assign p1_flushout_c = pkt_val_array1[((pkt_array_depth/2)*1)] & |(pkt_blk_end_array1[((pkt_array_depth/2)*2)-1:(pkt_array_depth/2)*1]);
assign p2_flushout_c = pkt_val_array1[((pkt_array_depth/2)*2)] & |(pkt_blk_end_array1[((pkt_array_depth/2)*3)-1:(pkt_array_depth/2)*2]);
assign p3_flushout_c = pkt_val_array1[((pkt_array_depth/2)*3)] & |(pkt_blk_end_array1[((pkt_array_depth/2)*4)-1:(pkt_array_depth/2)*3]);

assign pkt_arry_clr_p0 = pkt_val_array1[((pkt_array_depth/2)*1)-1] | (pkt_val_array1[0] & |(pkt_blk_end_array1[((pkt_array_depth/2)*1)-1:0]));
assign pkt_arry_clr_p1 = pkt_val_array1[((pkt_array_depth/2)*2)-1] | (pkt_val_array1[((pkt_array_depth/2)*1)] & |(pkt_blk_end_array1[((pkt_array_depth/2)*2)-1:(pkt_array_depth/2)*1]));
assign pkt_arry_clr_p2 = pkt_val_array1[((pkt_array_depth/2)*3)-1] | (pkt_val_array1[((pkt_array_depth/2)*2)] & |(pkt_blk_end_array1[((pkt_array_depth/2)*3)-1:(pkt_array_depth/2)*2]));
assign pkt_arry_clr_p3 = pkt_val_array1[((pkt_array_depth/2)*4)-1] | (pkt_val_array1[((pkt_array_depth/2)*3)] & |(pkt_blk_end_array1[((pkt_array_depth/2)*4)-1:(pkt_array_depth/2)*3]));

wire pkt_array_rst;
wire pkt_seg_sel_reg_rst;

assign pkt_array_rst = !aresetn_axis_unseg | p0_flushout_c | p1_flushout_c | p2_flushout_c | p3_flushout_c;
assign pkt_seg_sel_reg_rst = !aresetn_axis_unseg | p0_flushout_c | p1_flushout_c | p2_flushout_c | p3_flushout_c;

integer i, ii;
generate
    always @ (posedge aclk_axis_unseg) begin
        if (pkt_array_rst) begin
            pkt_array_ptr1   = 0;
            for(i=0; i < pkt_array_depth*2; i = i+1) begin
                pkt_val_array0 [i] 		<= 1'b0;
				pkt_val_array1 [i] 		<= 1'b0;
                pkt_blk_end_array1 [i] 	<= 1'b0;
            end
		end else begin
            for(i=0; i <pkt_array_depth*2; i = i+1) begin
                pkt_val_array0 [i]	<= 1'b0;
            end

			if (pkt_arry_clr_p0) begin
				for(ii=0; ii < (pkt_array_depth/2)*1; ii = ii+1) begin
					pkt_val_array1[ii] <= 1'b0;
				end
			end
			if (pkt_arry_clr_p1) begin
				for(ii=(pkt_array_depth/2); ii < (pkt_array_depth/2)*2; ii = ii+1) begin
					pkt_val_array1 [ii] <= 1'b0;
				end
			end
			if (pkt_arry_clr_p2) begin
				for(ii=(pkt_array_depth/2)*2; ii < (pkt_array_depth/2)*3; ii = ii+1) begin
					pkt_val_array1[ii] <= 1'b0;
				end
			end
			if (pkt_arry_clr_p3) begin
				for(ii=(pkt_array_depth/2)*3; ii < (pkt_array_depth*2); ii = ii+1) begin
					pkt_val_array1 [ii] <= 1'b0;
				end
			end

			for(i=0; i < pkt_array_depth; i = i+1) begin
				if (seg_val_array[i]) begin
					pkt_val_array0 [pkt_array_ptr1] 	<= 1'b1;
					pkt_val_array1 [pkt_array_ptr1] 	<= 1'b1;
					pkt_blk_end_array1[pkt_array_ptr1] 	<= seg_blk_end_array[i];
					pkt_array_ptr1 = pkt_array_ptr1 + 1;
				end
			end
        end
    end

    always @ (posedge aclk_axis_unseg) begin
        if (pkt_seg_sel_reg_rst) begin
            pkt_array_ptr2   = 0;
		end else begin
			for(i=0; i < pkt_array_depth; i = i+1) begin
				if (seg_val_array[i]) begin
					pkt_seg_sel_reg[pkt_array_ptr2] <= i;
					pkt_array_ptr2 = pkt_array_ptr2 + 1;
				end
			end
        end
    end
endgenerate

`ifdef en_axis1

reg [`segment_width-1:0] seg_data_array1 [pkt_array_depth-1:0];
reg [seg_mty_w-1:0] seg_mty_array1 [pkt_array_depth-1:0];
reg [pkt_array_depth-1:0] seg_val_array1;
reg [pkt_array_depth-1:0] seg_sop_array1;
reg [pkt_array_depth-1:0] seg_eop_array1;
reg [pkt_array_depth-1:0] seg_err_array1;
reg [pkt_array_depth-1:0] seg_blk_end_array1;

reg [`segment_width-1:0] seg_data_array2 [pkt_array_depth-1:0];
reg [seg_mty_w-1:0] seg_mty_array2 [pkt_array_depth-1:0];
reg [pkt_array_depth-1:0] seg_val_array2;
reg [pkt_array_depth-1:0] seg_sop_array2;
reg [pkt_array_depth-1:0] seg_eop_array2;
reg [pkt_array_depth-1:0] seg_err_array2;
reg [pkt_array_depth-1:0] seg_blk_end_array2;

`else

reg [`segment_width-1:0] seg_data_array1 [(`unseg_axis_w/`segment_width)-1:0];
reg [seg_mty_w-1:0] seg_mty_array1 [(`unseg_axis_w/`segment_width)-1:0];
reg [(`unseg_axis_w/`segment_width)-1:0] seg_val_array1;
reg [(`unseg_axis_w/`segment_width)-1:0] seg_sop_array1;
reg [(`unseg_axis_w/`segment_width)-1:0] seg_eop_array1;
reg [(`unseg_axis_w/`segment_width)-1:0] seg_err_array1;
reg [(`unseg_axis_w/`segment_width)-1:0] seg_blk_end_array1;

reg [`segment_width-1:0] seg_data_array2 [(`unseg_axis_w/`segment_width)-1:0];
reg [seg_mty_w-1:0] seg_mty_array2 [(`unseg_axis_w/`segment_width)-1:0];
reg [(`unseg_axis_w/`segment_width)-1:0] seg_val_array2;
reg [(`unseg_axis_w/`segment_width)-1:0] seg_sop_array2;
reg [(`unseg_axis_w/`segment_width)-1:0] seg_eop_array2;
reg [(`unseg_axis_w/`segment_width)-1:0] seg_err_array2;
reg [(`unseg_axis_w/`segment_width)-1:0] seg_blk_end_array2;

`endif

genvar h1;
generate
for (h1=0; h1 < pkt_array_depth; h1 = h1+1) begin
    always @ (posedge aclk_axis_unseg) begin
        seg_data_array1[h1] 	<= seg_data_array[h1];
        seg_mty_array1[h1]  	<= seg_mty_array[h1];
        seg_val_array1[h1]  	<= seg_val_array[h1];
        seg_sop_array1[h1]  	<= seg_sop_array[h1];
        seg_eop_array1[h1]  	<= seg_eop_array[h1];
        seg_err_array1[h1]  	<= seg_err_array[h1];
        seg_blk_end_array1[h1]  <= seg_blk_end_array[h1];
    end
end
for (h1=0; h1 < pkt_array_depth; h1 = h1+1) begin
    always @ (posedge aclk_axis_unseg) begin
        seg_data_array2[h1] 	<= seg_data_array1[h1];
        seg_mty_array2[h1]  	<= seg_mty_array1[h1];
        seg_val_array2[h1]  	<= seg_val_array1[h1];
        seg_sop_array2[h1]  	<= seg_sop_array1[h1];
        seg_eop_array2[h1]  	<= seg_eop_array1[h1];
        seg_err_array2[h1]  	<= seg_err_array1[h1];
        seg_blk_end_array2[h1]  <= seg_blk_end_array1[h1];
    end
end
for (h1=0; h1 < pkt_array_depth*2; h1 = h1+1) begin
    always @ (posedge aclk_axis_unseg) begin
		pkt_seg_sel_reg1[h1]	<= pkt_seg_sel_reg[h1];
	end
end
endgenerate

always @ (posedge aclk_axis_unseg) begin
    pkt_val_array2	<= pkt_val_array1;
    pkt_val_array 	<= pkt_val_array2;
    pkt_val_array00 <= pkt_val_array0;
end

genvar array_depth;

generate
    for (array_depth=0; array_depth < pkt_array_depth; array_depth = array_depth+1) begin
        always @ (posedge aclk_axis_unseg) begin
            if (!aresetn_axis_unseg) begin
                pkt_sop_array[array_depth]  					<= 1'b0;
                pkt_eop_array[array_depth]  					<= 1'b0;
                pkt_err_array[array_depth]  					<= 1'b0;
                pkt_blk_end_array[array_depth]  				<= 1'b0;
                pkt_mty_array[array_depth]  					<= 'd0;
                pkt_data_array[array_depth] 					<= 'd0;
                pkt_sop_array [array_depth+pkt_array_depth]  	<= 1'b0;
                pkt_eop_array [array_depth+pkt_array_depth]  	<= 1'b0;
                pkt_err_array [array_depth+pkt_array_depth]  	<= 1'b0;
                pkt_blk_end_array [array_depth+pkt_array_depth]	<= 1'b0;
                pkt_mty_array [array_depth+pkt_array_depth]  	<= 'd0;
                pkt_data_array[array_depth+pkt_array_depth]  	<= 'd0;
            end else begin
                if (pkt_val_array00[array_depth]) begin
                    pkt_sop_array[array_depth]  					<= seg_sop_array2 [pkt_seg_sel_reg1[array_depth]];
                    pkt_eop_array[array_depth]  					<= seg_eop_array2 [pkt_seg_sel_reg1[array_depth]];
                    pkt_err_array[array_depth]  					<= seg_err_array2 [pkt_seg_sel_reg1[array_depth]];
                    pkt_blk_end_array[array_depth]  				<= seg_blk_end_array2 [pkt_seg_sel_reg1[array_depth]];
                    pkt_mty_array[array_depth]  					<= seg_mty_array2 [pkt_seg_sel_reg1[array_depth]];
                    pkt_data_array[array_depth] 					<= seg_data_array2[pkt_seg_sel_reg1[array_depth]];
                end
                if (pkt_val_array00[array_depth+pkt_array_depth]) begin
                    pkt_sop_array [array_depth+pkt_array_depth] 	<= seg_sop_array2 [pkt_seg_sel_reg1[array_depth+pkt_array_depth]];
                    pkt_eop_array [array_depth+pkt_array_depth] 	<= seg_eop_array2 [pkt_seg_sel_reg1[array_depth+pkt_array_depth]];
                    pkt_err_array [array_depth+pkt_array_depth] 	<= seg_err_array2 [pkt_seg_sel_reg1[array_depth+pkt_array_depth]];
                    pkt_blk_end_array [array_depth+pkt_array_depth] <= seg_blk_end_array2 [pkt_seg_sel_reg1[array_depth+pkt_array_depth]];
                    pkt_mty_array [array_depth+pkt_array_depth] 	<= seg_mty_array2 [pkt_seg_sel_reg1[array_depth+pkt_array_depth]];
                    pkt_data_array[array_depth+pkt_array_depth] 	<= seg_data_array2[pkt_seg_sel_reg1[array_depth+pkt_array_depth]];
                end
            end
        end
    end
endgenerate

//-----------------------------------------------------------------------------------------------------------------------

//----------------- Buffering packed segments

reg [`segment_width-1:0] pkt_data_buf_in_p0 [(pkt_array_depth/2)-1:0];
reg [seg_mty_w-1:0] pkt_mty_buf_in_p0 [(pkt_array_depth/2)-1:0];
reg [(pkt_array_depth/2)-1:0] pkt_val_buf_in_p0;
reg [(pkt_array_depth/2)-1:0] pkt_sop_buf_in_p0;
reg [(pkt_array_depth/2)-1:0] pkt_eop_buf_in_p0;
reg [(pkt_array_depth/2)-1:0] pkt_err_buf_in_p0;
reg [(pkt_array_depth/2)-1:0] pkt_blk_end_buf_in_p0;
reg [`segment_width-1:0] pkt_data_buf_in_p1[(pkt_array_depth/2)-1:0];
reg [seg_mty_w-1:0] pkt_mty_buf_in_p1[(pkt_array_depth/2)-1:0];
reg [(pkt_array_depth/2)-1:0] pkt_val_buf_in_p1;
reg [(pkt_array_depth/2)-1:0] pkt_sop_buf_in_p1;
reg [(pkt_array_depth/2)-1:0] pkt_eop_buf_in_p1;
reg [(pkt_array_depth/2)-1:0] pkt_err_buf_in_p1;
reg [(pkt_array_depth/2)-1:0] pkt_blk_end_buf_in_p1;
reg [`segment_width-1:0] pkt_data_buf_in_p2 [(pkt_array_depth/2)-1:0];
reg [seg_mty_w-1:0] pkt_mty_buf_in_p2 [(pkt_array_depth/2)-1:0];
reg [(pkt_array_depth/2)-1:0] pkt_val_buf_in_p2;
reg [(pkt_array_depth/2)-1:0] pkt_sop_buf_in_p2;
reg [(pkt_array_depth/2)-1:0] pkt_eop_buf_in_p2;
reg [(pkt_array_depth/2)-1:0] pkt_err_buf_in_p2;
reg [(pkt_array_depth/2)-1:0] pkt_blk_end_buf_in_p2;
reg [`segment_width-1:0] pkt_data_buf_in_p3[(pkt_array_depth/2)-1:0];
reg [seg_mty_w-1:0] pkt_mty_buf_in_p3[(pkt_array_depth/2)-1:0];
reg [(pkt_array_depth/2)-1:0] pkt_val_buf_in_p3;
reg [(pkt_array_depth/2)-1:0] pkt_sop_buf_in_p3;
reg [(pkt_array_depth/2)-1:0] pkt_eop_buf_in_p3;
reg [(pkt_array_depth/2)-1:0] pkt_err_buf_in_p3;
reg [(pkt_array_depth/2)-1:0] pkt_blk_end_buf_in_p3;

genvar v;
generate
    for (v=0; v<(pkt_array_depth/2); v=v+1) begin
        always @ (posedge aclk_axis_unseg) begin
            pkt_val_buf_in_p0[v]     <= pkt_val_array[v];
            pkt_data_buf_in_p0[v]    <= pkt_data_array[v];
            pkt_mty_buf_in_p0[v]     <= pkt_mty_array[v];
            pkt_sop_buf_in_p0[v]     <= pkt_sop_array[v];
            pkt_eop_buf_in_p0[v]     <= pkt_eop_array[v];
            pkt_err_buf_in_p0[v]     <= pkt_err_array[v];
            pkt_blk_end_buf_in_p0[v] <= pkt_blk_end_array[v] & pkt_val_array[v];
            pkt_val_buf_in_p1[v]     <= pkt_val_array[v+((pkt_array_depth/2)*1)];
            pkt_data_buf_in_p1[v]    <= pkt_data_array[v+((pkt_array_depth/2)*1)];
            pkt_mty_buf_in_p1[v]     <= pkt_mty_array[v+((pkt_array_depth/2)*1)];
            pkt_sop_buf_in_p1[v]     <= pkt_sop_array[v+((pkt_array_depth/2)*1)];
            pkt_eop_buf_in_p1[v]     <= pkt_eop_array[v+((pkt_array_depth/2)*1)];
            pkt_err_buf_in_p1[v]     <= pkt_err_array[v+((pkt_array_depth/2)*1)];
            pkt_blk_end_buf_in_p1[v] <= pkt_blk_end_array[v+((pkt_array_depth/2)*1)] & pkt_val_array[v+((pkt_array_depth/2)*1)];
            pkt_val_buf_in_p2[v]     <= pkt_val_array[v+((pkt_array_depth/2)*2)];
            pkt_data_buf_in_p2[v]    <= pkt_data_array[v+((pkt_array_depth/2)*2)];
            pkt_mty_buf_in_p2[v]     <= pkt_mty_array[v+((pkt_array_depth/2)*2)];
            pkt_sop_buf_in_p2[v]     <= pkt_sop_array[v+((pkt_array_depth/2)*2)];
            pkt_eop_buf_in_p2[v]     <= pkt_eop_array[v+((pkt_array_depth/2)*2)];
            pkt_err_buf_in_p2[v]     <= pkt_err_array[v+((pkt_array_depth/2)*2)];
            pkt_blk_end_buf_in_p2[v] <= pkt_blk_end_array[v+((pkt_array_depth/2)*2)] & pkt_val_array[v+((pkt_array_depth/2)*2)];
            pkt_val_buf_in_p3[v]     <= pkt_val_array[v+((pkt_array_depth/2)*3)];
            pkt_data_buf_in_p3[v]    <= pkt_data_array[v+((pkt_array_depth/2)*3)];
            pkt_mty_buf_in_p3[v]     <= pkt_mty_array[v+((pkt_array_depth/2)*3)];
            pkt_sop_buf_in_p3[v]     <= pkt_sop_array[v+((pkt_array_depth/2)*3)];
            pkt_eop_buf_in_p3[v]     <= pkt_eop_array[v+((pkt_array_depth/2)*3)];
            pkt_err_buf_in_p3[v]     <= pkt_err_array[v+((pkt_array_depth/2)*3)];
            pkt_blk_end_buf_in_p3[v] <= pkt_blk_end_array[v+((pkt_array_depth/2)*3)] & pkt_val_array[v+((pkt_array_depth/2)*3)];
        end
    end
endgenerate

wire wr_en_0;
wire wr_en_1;
wire wr_en_2;
wire wr_en_3;

wire p0_flushout;
wire p1_flushout;
wire p2_flushout;
wire p3_flushout;

assign p0_flushout = (|pkt_blk_end_buf_in_p0 && |pkt_blk_end_buf_in_p3) ? 1'b1 : (|pkt_blk_end_buf_in_p0 && !(|pkt_blk_end_buf_in_p1)) ? 1'b1 : 1'b0;
assign p1_flushout = (|pkt_blk_end_buf_in_p1 && |pkt_blk_end_buf_in_p0) ? 1'b1 : (|pkt_blk_end_buf_in_p1 && !(|pkt_blk_end_buf_in_p2)) ? 1'b1 : 1'b0;
assign p2_flushout = (|pkt_blk_end_buf_in_p2 && |pkt_blk_end_buf_in_p1) ? 1'b1 : (|pkt_blk_end_buf_in_p2 && !(|pkt_blk_end_buf_in_p3)) ? 1'b1 : 1'b0;
assign p3_flushout = (|pkt_blk_end_buf_in_p3 && |pkt_blk_end_buf_in_p2) ? 1'b1 : (|pkt_blk_end_buf_in_p3 && !(|pkt_blk_end_buf_in_p0)) ? 1'b1 : 1'b0;

assign wr_en_0 = pkt_val_buf_in_p0[((pkt_array_depth/2)*1)-1] | p0_flushout;
assign wr_en_1 = pkt_val_buf_in_p1[((pkt_array_depth/2)*1)-1] | p1_flushout;
assign wr_en_2 = pkt_val_buf_in_p2[((pkt_array_depth/2)*1)-1] | p2_flushout;
assign wr_en_3 = pkt_val_buf_in_p3[((pkt_array_depth/2)*1)-1] | p3_flushout;

reg [`segment_width-1:0] pkt_data_buf_in_p0_q [(pkt_array_depth/2)-1:0];
reg [seg_mty_w-1:0] pkt_mty_buf_in_p0_q [(pkt_array_depth/2)-1:0];
reg [(pkt_array_depth/2)-1:0] pkt_val_buf_in_p0_q;
reg [(pkt_array_depth/2)-1:0] pkt_sop_buf_in_p0_q;
reg [(pkt_array_depth/2)-1:0] pkt_eop_buf_in_p0_q;
reg [(pkt_array_depth/2)-1:0] pkt_err_buf_in_p0_q;
reg [(pkt_array_depth/2)-1:0] pkt_blk_end_buf_in_p0_q;
reg [`segment_width-1:0] pkt_data_buf_in_p1_q[(pkt_array_depth/2)-1:0];
reg [seg_mty_w-1:0] pkt_mty_buf_in_p1_q[(pkt_array_depth/2)-1:0];
reg [(pkt_array_depth/2)-1:0] pkt_val_buf_in_p1_q;
reg [(pkt_array_depth/2)-1:0] pkt_sop_buf_in_p1_q;
reg [(pkt_array_depth/2)-1:0] pkt_eop_buf_in_p1_q;
reg [(pkt_array_depth/2)-1:0] pkt_err_buf_in_p1_q;
reg [(pkt_array_depth/2)-1:0] pkt_blk_end_buf_in_p1_q;
reg [`segment_width-1:0] pkt_data_buf_in_p2_q [(pkt_array_depth/2)-1:0];
reg [seg_mty_w-1:0] pkt_mty_buf_in_p2_q [(pkt_array_depth/2)-1:0];
reg [(pkt_array_depth/2)-1:0] pkt_val_buf_in_p2_q;
reg [(pkt_array_depth/2)-1:0] pkt_sop_buf_in_p2_q;
reg [(pkt_array_depth/2)-1:0] pkt_eop_buf_in_p2_q;
reg [(pkt_array_depth/2)-1:0] pkt_err_buf_in_p2_q;
reg [(pkt_array_depth/2)-1:0] pkt_blk_end_buf_in_p2_q;
reg [`segment_width-1:0] pkt_data_buf_in_p3_q [(pkt_array_depth/2)-1:0];
reg [seg_mty_w-1:0] pkt_mty_buf_in_p3_q [(pkt_array_depth/2)-1:0];
reg [(pkt_array_depth/2)-1:0] pkt_val_buf_in_p3_q;
reg [(pkt_array_depth/2)-1:0] pkt_sop_buf_in_p3_q;
reg [(pkt_array_depth/2)-1:0] pkt_eop_buf_in_p3_q;
reg [(pkt_array_depth/2)-1:0] pkt_err_buf_in_p3_q;
reg [(pkt_array_depth/2)-1:0] pkt_blk_end_buf_in_p3_q;

reg wr_en_0_q;
reg wr_en_1_q;
reg wr_en_2_q;
reg wr_en_3_q;

genvar vv;
generate
for (vv=0; vv<`num_segments; vv=vv+1) begin
    always @ (posedge aclk_axis_unseg) begin
        pkt_val_buf_in_p0_q[vv]     <= pkt_val_buf_in_p0[vv];
        pkt_data_buf_in_p0_q[vv]    <= pkt_data_buf_in_p0[vv];
        pkt_mty_buf_in_p0_q[vv]     <= pkt_mty_buf_in_p0[vv];
        pkt_sop_buf_in_p0_q[vv]     <= pkt_sop_buf_in_p0[vv];
        pkt_eop_buf_in_p0_q[vv]     <= pkt_eop_buf_in_p0[vv];
        pkt_err_buf_in_p0_q[vv]     <= pkt_err_buf_in_p0[vv];
        pkt_blk_end_buf_in_p0_q[vv] <= pkt_blk_end_buf_in_p0[vv] & p0_flushout;
        pkt_val_buf_in_p1_q[vv]     <= pkt_val_buf_in_p1[vv];
        pkt_data_buf_in_p1_q[vv]    <= pkt_data_buf_in_p1[vv];
        pkt_mty_buf_in_p1_q[vv]     <= pkt_mty_buf_in_p1[vv];
        pkt_sop_buf_in_p1_q[vv]     <= pkt_sop_buf_in_p1[vv];
        pkt_eop_buf_in_p1_q[vv]     <= pkt_eop_buf_in_p1[vv];
        pkt_err_buf_in_p1_q[vv]     <= pkt_err_buf_in_p1[vv];
        pkt_blk_end_buf_in_p1_q[vv] <= pkt_blk_end_buf_in_p1[vv] & p1_flushout;
        pkt_val_buf_in_p2_q[vv]     <= pkt_val_buf_in_p2[vv];
        pkt_data_buf_in_p2_q[vv]    <= pkt_data_buf_in_p2[vv];
        pkt_mty_buf_in_p2_q[vv]     <= pkt_mty_buf_in_p2[vv];
        pkt_sop_buf_in_p2_q[vv]     <= pkt_sop_buf_in_p2[vv];
        pkt_eop_buf_in_p2_q[vv]     <= pkt_eop_buf_in_p2[vv];
        pkt_err_buf_in_p2_q[vv]     <= pkt_err_buf_in_p2[vv];
        pkt_blk_end_buf_in_p2_q[vv] <= pkt_blk_end_buf_in_p2[vv] & p2_flushout;
        pkt_val_buf_in_p3_q[vv]     <= pkt_val_buf_in_p3[vv];
        pkt_data_buf_in_p3_q[vv]    <= pkt_data_buf_in_p3[vv];
        pkt_mty_buf_in_p3_q[vv]     <= pkt_mty_buf_in_p3[vv];
        pkt_sop_buf_in_p3_q[vv]     <= pkt_sop_buf_in_p3[vv];
        pkt_eop_buf_in_p3_q[vv]     <= pkt_eop_buf_in_p3[vv];
        pkt_err_buf_in_p3_q[vv]     <= pkt_err_buf_in_p3[vv];
        pkt_blk_end_buf_in_p3_q[vv] <= pkt_blk_end_buf_in_p3[vv] & p3_flushout;
    end
end
endgenerate

always @ (posedge aclk_axis_unseg) begin
    wr_en_0_q   <= wr_en_0;
    wr_en_1_q   <= wr_en_1;
    wr_en_2_q   <= wr_en_2;
    wr_en_3_q   <= wr_en_3;
end

reg rd_en_0;
reg rd_en_1;
reg rd_en_2;
reg rd_en_3;

wire [(pkt_array_depth/2)-1:0] unseg_buf1_aempty_0;
wire [(pkt_array_depth/2)-1:0] unseg_buf1_afull_0;
wire [(pkt_array_depth/2)-1:0] unseg_buf1_pfull_0;
wire [(pkt_array_depth/2)-1:0] unseg_buf1_empty_0;
wire [(pkt_array_depth/2)-1:0] unseg_data_valid_0;
wire [(pkt_array_depth/2)-1:0] unseg_rd_rst_busy_0;
wire [(pkt_array_depth/2)-1:0] unseg_wr_rst_busy_0;
wire [(pkt_array_depth/2)-1:0] unseg_buf1_aempty_1;
wire [(pkt_array_depth/2)-1:0] unseg_buf1_afull_1;
wire [(pkt_array_depth/2)-1:0] unseg_buf1_pfull_1;
wire [(pkt_array_depth/2)-1:0] unseg_buf1_empty_1;
wire [(pkt_array_depth/2)-1:0] unseg_data_valid_1;
wire [(pkt_array_depth/2)-1:0] unseg_rd_rst_busy_1;
wire [(pkt_array_depth/2)-1:0] unseg_wr_rst_busy_1;
wire [(pkt_array_depth/2)-1:0] unseg_buf1_aempty_2;
wire [(pkt_array_depth/2)-1:0] unseg_buf1_afull_2;
wire [(pkt_array_depth/2)-1:0] unseg_buf1_pfull_2;
wire [(pkt_array_depth/2)-1:0] unseg_buf1_empty_2;
wire [(pkt_array_depth/2)-1:0] unseg_data_valid_2;
wire [(pkt_array_depth/2)-1:0] unseg_rd_rst_busy_2;
wire [(pkt_array_depth/2)-1:0] unseg_wr_rst_busy_2;
wire [(pkt_array_depth/2)-1:0] unseg_buf1_aempty_3;
wire [(pkt_array_depth/2)-1:0] unseg_buf1_afull_3;
wire [(pkt_array_depth/2)-1:0] unseg_buf1_pfull_3;
wire [(pkt_array_depth/2)-1:0] unseg_buf1_empty_3;
wire [(pkt_array_depth/2)-1:0] unseg_data_valid_3;
wire [(pkt_array_depth/2)-1:0] unseg_rd_rst_busy_3;
wire [(pkt_array_depth/2)-1:0] unseg_wr_rst_busy_3;

wire [`segment_width-1:0] pkt_data_buf_out_p0 [(pkt_array_depth/2)-1:0];
wire [seg_mty_w-1:0] pkt_mty_buf_out_p0 [(pkt_array_depth/2)-1:0];
wire [(pkt_array_depth/2)-1:0] pkt_val_buf_out_p0;
wire [(pkt_array_depth/2)-1:0] pkt_sop_buf_out_p0;
wire [(pkt_array_depth/2)-1:0] pkt_eop_buf_out_p0;
wire [(pkt_array_depth/2)-1:0] pkt_err_buf_out_p0;
wire [(pkt_array_depth/2)-1:0] pkt_blk_end_buf_out_p0;
wire [`segment_width-1:0] pkt_data_buf_out_p1 [(pkt_array_depth/2)-1:0];
wire [seg_mty_w-1:0] pkt_mty_buf_out_p1 [(pkt_array_depth/2)-1:0];
wire [(pkt_array_depth/2)-1:0] pkt_val_buf_out_p1;
wire [(pkt_array_depth/2)-1:0] pkt_sop_buf_out_p1;
wire [(pkt_array_depth/2)-1:0] pkt_eop_buf_out_p1;
wire [(pkt_array_depth/2)-1:0] pkt_err_buf_out_p1;
wire [(pkt_array_depth/2)-1:0] pkt_blk_end_buf_out_p1;
wire [`segment_width-1:0] pkt_data_buf_out_p2 [(pkt_array_depth/2)-1:0];
wire [seg_mty_w-1:0] pkt_mty_buf_out_p2 [(pkt_array_depth/2)-1:0];
wire [(pkt_array_depth/2)-1:0] pkt_val_buf_out_p2;
wire [(pkt_array_depth/2)-1:0] pkt_sop_buf_out_p2;
wire [(pkt_array_depth/2)-1:0] pkt_eop_buf_out_p2;
wire [(pkt_array_depth/2)-1:0] pkt_err_buf_out_p2;
wire [(pkt_array_depth/2)-1:0] pkt_blk_end_buf_out_p2;
wire [`segment_width-1:0] pkt_data_buf_out_p3 [(pkt_array_depth/2)-1:0];
wire [seg_mty_w-1:0] pkt_mty_buf_out_p3 [(pkt_array_depth/2)-1:0];
wire [(pkt_array_depth/2)-1:0] pkt_val_buf_out_p3;
wire [(pkt_array_depth/2)-1:0] pkt_sop_buf_out_p3;
wire [(pkt_array_depth/2)-1:0] pkt_eop_buf_out_p3;
wire [(pkt_array_depth/2)-1:0] pkt_err_buf_out_p3;
wire [(pkt_array_depth/2)-1:0] pkt_blk_end_buf_out_p3;

genvar x;
generate
    for (x=0; x<`num_segments; x=x+1) begin
        xpm_fifo_sync #(
           .CASCADE_HEIGHT(0),
           .DOUT_RESET_VALUE("0"),
           .ECC_MODE("no_ecc"),
           .FIFO_MEMORY_TYPE("auto"),
           .FIFO_READ_LATENCY(0),
           .FIFO_WRITE_DEPTH(local_buff_depth),
           .FULL_RESET_VALUE(0),
           .PROG_EMPTY_THRESH(10),
           .PROG_FULL_THRESH(local_buff_depth-7),
           .RD_DATA_COUNT_WIDTH(1),
           .READ_DATA_WIDTH(`segment_width+seg_mty_w+5),
           .READ_MODE("fwft"),
           .SIM_ASSERT_CHK(0),
           .USE_ADV_FEATURES("1002"),
           .WAKEUP_TIME(0),
           .WRITE_DATA_WIDTH(`segment_width+seg_mty_w+5),
           .WR_DATA_COUNT_WIDTH(1)
        )
        xpm_fifo_sync_seg_buff_p0 (
           .almost_empty(unseg_buf1_aempty_0[x]),
           .almost_full(unseg_buf1_afull_0[x]),
           .data_valid(unseg_data_valid_0[x]),
           .dbiterr(),
           .dout({pkt_mty_buf_out_p0[x],pkt_blk_end_buf_out_p0[x],pkt_err_buf_out_p0[x],pkt_eop_buf_out_p0[x],pkt_sop_buf_out_p0[x],pkt_val_buf_out_p0[x],pkt_data_buf_out_p0[x]}),
           .empty(unseg_buf1_empty_0[x]),
           .full(),
           .overflow(),
           .prog_empty(),
           .prog_full(unseg_buf1_pfull_0[x]),
           .rd_data_count(),
           .rd_rst_busy(unseg_rd_rst_busy_0[x]),
           .sbiterr(),
           .underflow(),
           .wr_ack(),
           .wr_data_count(),
           .wr_rst_busy(unseg_wr_rst_busy_0[x]),
           .din({pkt_mty_buf_in_p0_q[x],pkt_blk_end_buf_in_p0_q[x],pkt_err_buf_in_p0_q[x],pkt_eop_buf_in_p0_q[x],pkt_sop_buf_in_p0_q[x],pkt_val_buf_in_p0_q[x],pkt_data_buf_in_p0_q[x]}),
           .injectdbiterr(1'b0),
           .injectsbiterr(1'b0),
           .rd_en(rd_en_0 & !out_buff_afull),
           .rst(!aresetn_axis_unseg),
           .sleep(1'b0),
           .wr_clk(aclk_axis_unseg),
           .wr_en(wr_en_0_q & !unseg_wr_rst_busy_0[x])
        );

        xpm_fifo_sync #(
           .CASCADE_HEIGHT(0),
           .DOUT_RESET_VALUE("0"),
           .ECC_MODE("no_ecc"),
           .FIFO_MEMORY_TYPE("auto"),
           .FIFO_READ_LATENCY(0),
           .FIFO_WRITE_DEPTH(local_buff_depth),
           .FULL_RESET_VALUE(0),
           .PROG_EMPTY_THRESH(10),
           .PROG_FULL_THRESH(local_buff_depth-7),
           .RD_DATA_COUNT_WIDTH(1),
           .READ_DATA_WIDTH(`segment_width+seg_mty_w+5),
           .READ_MODE("fwft"),
           .SIM_ASSERT_CHK(0),
           .USE_ADV_FEATURES("1002"),
           .WAKEUP_TIME(0),
           .WRITE_DATA_WIDTH(`segment_width+seg_mty_w+5),
           .WR_DATA_COUNT_WIDTH(1)
        )
        xpm_fifo_sync_seg_buff_p1 (
           .almost_empty(unseg_buf1_aempty_1[x]),
           .almost_full(unseg_buf1_afull_1[x]),
           .data_valid(unseg_data_valid_1[x]),
           .dbiterr(),
           .dout({pkt_mty_buf_out_p1[x],pkt_blk_end_buf_out_p1[x],pkt_err_buf_out_p1[x],pkt_eop_buf_out_p1[x],pkt_sop_buf_out_p1[x],pkt_val_buf_out_p1[x],pkt_data_buf_out_p1[x]}),
           .empty(unseg_buf1_empty_1[x]),
           .full(),
           .overflow(),
           .prog_empty(),
           .prog_full(unseg_buf1_pfull_1[x]),
           .rd_data_count(),
           .rd_rst_busy(unseg_rd_rst_busy_1[x]),
           .sbiterr(),
           .underflow(),
           .wr_ack(),
           .wr_data_count(),
           .wr_rst_busy(unseg_wr_rst_busy_1[x]),
           .din({pkt_mty_buf_in_p1_q[x],pkt_blk_end_buf_in_p1_q[x],pkt_err_buf_in_p1_q[x],pkt_eop_buf_in_p1_q[x],pkt_sop_buf_in_p1_q[x],pkt_val_buf_in_p1_q[x],pkt_data_buf_in_p1_q[x]}),
           .injectdbiterr(1'b0),
           .injectsbiterr(1'b0),
           .rd_en(rd_en_1 & !out_buff_afull),
           .rst(!aresetn_axis_unseg),
           .sleep(1'b0),
           .wr_clk(aclk_axis_unseg),
           .wr_en(wr_en_1_q & !unseg_wr_rst_busy_1[x])
        );

        xpm_fifo_sync #(
           .CASCADE_HEIGHT(0),
           .DOUT_RESET_VALUE("0"),
           .ECC_MODE("no_ecc"),
           .FIFO_MEMORY_TYPE("auto"),
           .FIFO_READ_LATENCY(0),
           .FIFO_WRITE_DEPTH(local_buff_depth),
           .FULL_RESET_VALUE(0),
           .PROG_EMPTY_THRESH(10),
           .PROG_FULL_THRESH(local_buff_depth-7),
           .RD_DATA_COUNT_WIDTH(1),
           .READ_DATA_WIDTH(`segment_width+seg_mty_w+5),
           .READ_MODE("fwft"),
           .SIM_ASSERT_CHK(0),
           .USE_ADV_FEATURES("1002"),
           .WAKEUP_TIME(0),
           .WRITE_DATA_WIDTH(`segment_width+seg_mty_w+5),
           .WR_DATA_COUNT_WIDTH(1)
        )
        xpm_fifo_sync_seg_buff_p2 (
           .almost_empty(unseg_buf1_aempty_2[x]),
           .almost_full(unseg_buf1_afull_2[x]),
           .data_valid(unseg_data_valid_2[x]),
           .dbiterr(),
           .dout({pkt_mty_buf_out_p2[x],pkt_blk_end_buf_out_p2[x],pkt_err_buf_out_p2[x],pkt_eop_buf_out_p2[x],pkt_sop_buf_out_p2[x],pkt_val_buf_out_p2[x],pkt_data_buf_out_p2[x]}),
           .empty(unseg_buf1_empty_2[x]),
           .full(),
           .overflow(),
           .prog_empty(),
           .prog_full(unseg_buf1_pfull_2[x]),
           .rd_data_count(),
           .rd_rst_busy(unseg_rd_rst_busy_2[x]),
           .sbiterr(),
           .underflow(),
           .wr_ack(),
           .wr_data_count(),
           .wr_rst_busy(unseg_wr_rst_busy_2[x]),
           .din({pkt_mty_buf_in_p2_q[x],pkt_blk_end_buf_in_p2_q[x],pkt_err_buf_in_p2_q[x],pkt_eop_buf_in_p2_q[x],pkt_sop_buf_in_p2_q[x],pkt_val_buf_in_p2_q[x],pkt_data_buf_in_p2_q[x]}),
           .injectdbiterr(1'b0),
           .injectsbiterr(1'b0),
           .rd_en(rd_en_2 & !out_buff_afull),
           .rst(!aresetn_axis_unseg),
           .sleep(1'b0),
           .wr_clk(aclk_axis_unseg),
           .wr_en(wr_en_2_q & !unseg_wr_rst_busy_2[x])
        );

        xpm_fifo_sync #(
           .CASCADE_HEIGHT(0),
           .DOUT_RESET_VALUE("0"),
           .ECC_MODE("no_ecc"),
           .FIFO_MEMORY_TYPE("auto"),
           .FIFO_READ_LATENCY(0),
           .FIFO_WRITE_DEPTH(local_buff_depth),
           .FULL_RESET_VALUE(0),
           .PROG_EMPTY_THRESH(10),
           .PROG_FULL_THRESH(local_buff_depth-7),
           .RD_DATA_COUNT_WIDTH(1),
           .READ_DATA_WIDTH(`segment_width+seg_mty_w+5),
           .READ_MODE("fwft"),
           .SIM_ASSERT_CHK(0),
           .USE_ADV_FEATURES("1002"),
           .WAKEUP_TIME(0),
           .WRITE_DATA_WIDTH(`segment_width+seg_mty_w+5),
           .WR_DATA_COUNT_WIDTH(1)
        )
        xpm_fifo_sync_seg_buff_p3 (
           .almost_empty(unseg_buf1_aempty_3[x]),
           .almost_full(unseg_buf1_afull_3[x]),
           .data_valid(unseg_data_valid_3[x]),
           .dbiterr(),
           .dout({pkt_mty_buf_out_p3[x],pkt_blk_end_buf_out_p3[x],pkt_err_buf_out_p3[x],pkt_eop_buf_out_p3[x],pkt_sop_buf_out_p3[x],pkt_val_buf_out_p3[x],pkt_data_buf_out_p3[x]}),
           .empty(unseg_buf1_empty_3[x]),
           .full(),
           .overflow(),
           .prog_empty(),
           .prog_full(unseg_buf1_pfull_3[x]),
           .rd_data_count(),
           .rd_rst_busy(unseg_rd_rst_busy_3[x]),
           .sbiterr(),
           .underflow(),
           .wr_ack(),
           .wr_data_count(),
           .wr_rst_busy(unseg_wr_rst_busy_3[x]),
           .din({pkt_mty_buf_in_p3_q[x],pkt_blk_end_buf_in_p3_q[x],pkt_err_buf_in_p3_q[x],pkt_eop_buf_in_p3_q[x],pkt_sop_buf_in_p3_q[x],pkt_val_buf_in_p3_q[x],pkt_data_buf_in_p3_q[x]}),
           .injectdbiterr(1'b0),
           .injectsbiterr(1'b0),
           .rd_en(rd_en_3 & !out_buff_afull),
           .rst(!aresetn_axis_unseg),
           .sleep(1'b0),
           .wr_clk(aclk_axis_unseg),
           .wr_en(wr_en_3_q & !unseg_wr_rst_busy_3[x])
        );
    end
endgenerate

assign pkt_array_buf_pfull = (|unseg_buf1_pfull_0) | (|unseg_buf1_pfull_1) | (|unseg_buf1_pfull_2) | (|unseg_buf1_pfull_3);

//-----------------------------------------------------------------------------------------------------------------------

//----------------- Packet readout / array port arbitration

wire rd_rst;

assign rd_rst = (|pkt_blk_end_buf_out_p0 & rd_en_0) | (|pkt_blk_end_buf_out_p1 & rd_en_1) | (|pkt_blk_end_buf_out_p2 & rd_en_2) | (|pkt_blk_end_buf_out_p3 & rd_en_3);

reg [1:0] port_sel;
(* MARK_DEBUG= P_MARK_DEBUG *) reg [1:0] port_sel_1;
reg [1:0] port_sel_2;

(* MARK_DEBUG= P_MARK_DEBUG *) reg rd_mux_en;

always @ (posedge aclk_axis_unseg) begin
        port_sel_1 	<= port_sel;
        port_sel_2 	<= port_sel_1;
    if (!aresetn_axis_unseg | rd_rst) begin
        rd_en_0 	<= 1'b0;
        rd_en_1 	<= 1'b0;
        rd_en_2 	<= 1'b0;
        rd_en_3 	<= 1'b0;
        port_sel 	<= 2'b00;
		rd_mux_en	<= 1'b0;
    end else if (!out_buff_afull) begin
		rd_mux_en	<= 1'b0;
		if (port_sel == 2'b11) begin
			if (!(|unseg_buf1_empty_3) && !(|unseg_rd_rst_busy_3)) begin
				rd_en_0  	<= 1'b0;
				rd_en_1  	<= 1'b0;
				rd_en_2  	<= 1'b0;
                rd_en_3  	<= 1'b1;
                port_sel 	<= 2'b00;
				rd_mux_en	<= 1'b1;
			end else begin
				rd_en_0  	<= 1'b0;
				rd_en_1  	<= 1'b0;
				rd_en_2  	<= 1'b0;
				rd_en_3  	<= 1'b0;
				port_sel 	<= port_sel;
				rd_mux_en	<= 1'b0;
			end
		end else if (port_sel == 2'b10) begin
			if (!(|unseg_buf1_empty_2) && !(|unseg_rd_rst_busy_2)) begin
				rd_en_0  	<= 1'b0;
				rd_en_1  	<= 1'b0;
				rd_en_2  	<= 1'b1;
				rd_en_3  	<= 1'b0;
				port_sel 	<= 2'b11;
				rd_mux_en	<= 1'b1;
			end else begin
				rd_en_0  	<= 1'b0;
				rd_en_1  	<= 1'b0;
				rd_en_2  	<= 1'b0;
				rd_en_3  	<= 1'b0;
                port_sel 	<= port_sel;
				rd_mux_en	<= 1'b0;
			end
		end else if (port_sel == 2'b01) begin
			if (!(|unseg_buf1_empty_1) && !(|unseg_rd_rst_busy_1)) begin
				rd_en_0  	<= 1'b0;
				rd_en_1  	<= 1'b1;
				rd_en_2  	<= 1'b0;
				rd_en_3  	<= 1'b0;
				port_sel 	<= 2'b10;
				rd_mux_en	<= 1'b1;
			end else begin
				rd_en_0  	<= 1'b0;
				rd_en_1  	<= 1'b0;
				rd_en_2  	<= 1'b0;
				rd_en_3  	<= 1'b0;
				port_sel 	<= port_sel;
				rd_mux_en	<= 1'b0;
                end
		end else begin
			if (!(|unseg_buf1_empty_0) && !(|unseg_rd_rst_busy_0)) begin
				rd_en_0  	<= 1'b1;
				rd_en_1  	<= 1'b0;
				rd_en_2  	<= 1'b0;
				rd_en_3  	<= 1'b0;
				port_sel 	<= 2'b01;
				rd_mux_en	<= 1'b1;
			end else begin
				rd_en_0  	<= 1'b0;
				rd_en_1  	<= 1'b0;
				rd_en_2  	<= 1'b0;
				rd_en_3  	<= 1'b0;
				port_sel 	<= port_sel;
				rd_mux_en	<= 1'b0;
			end
		end
    end else
		rd_mux_en	<= 1'b0;
end

reg [`segment_width-1:0] pkt_data_out_0 [`num_segments-1:0];
(* MARK_DEBUG= P_MARK_DEBUG *) reg [seg_mty_w-1:0] pkt_mty_out_0 [`num_segments-1:0];
(* MARK_DEBUG= P_MARK_DEBUG *) reg [`num_segments-1:0] pkt_val_out_0;
(* MARK_DEBUG= P_MARK_DEBUG *) reg [`num_segments-1:0] pkt_sop_out_0;
(* MARK_DEBUG= P_MARK_DEBUG *) reg [`num_segments-1:0] pkt_eop_out_0;
(* MARK_DEBUG= P_MARK_DEBUG *) reg [`num_segments-1:0] pkt_err_out_0;
(* MARK_DEBUG= P_MARK_DEBUG *) reg [`num_segments-1:0] pkt_blk_end_out_0;

genvar z, zz;

generate
    for (zz=0; zz<`num_segments; zz=zz+1) begin
        always @ (posedge aclk_axis_unseg) begin
            if (!aresetn_axis_unseg) begin
                pkt_val_out_0[zz] 		<= 1'b0;
                pkt_mty_out_0[zz] 		<= {seg_mty_w{1'b1}};
                pkt_eop_out_0[zz] 		<= 1'b0;
                pkt_eop_out_0[zz] 		<= 1'b0;
                pkt_err_out_0[zz] 		<= 1'b0;
                pkt_blk_end_out_0[zz] 	<= 1'b0;
			end else if (rd_mux_en) begin
                if (port_sel_1 == 2'b11) begin
                    pkt_val_out_0[zz]       <= pkt_val_buf_out_p3[zz] & unseg_data_valid_3[zz];
                    pkt_mty_out_0[zz]       <= pkt_mty_buf_out_p3[zz];
                    pkt_sop_out_0[zz]       <= pkt_sop_buf_out_p3[zz];
                    pkt_eop_out_0[zz]       <= pkt_eop_buf_out_p3[zz];
                    pkt_err_out_0[zz]       <= pkt_err_buf_out_p3[zz];
                    pkt_data_out_0[zz]      <= pkt_data_buf_out_p3[zz];
                    pkt_blk_end_out_0[zz]   <= pkt_blk_end_buf_out_p3[zz];
                end else if (port_sel_1 == 2'b10) begin
                    pkt_val_out_0[zz]    	<= pkt_val_buf_out_p2[zz] & unseg_data_valid_2[zz];
                    pkt_mty_out_0[zz]    	<= pkt_mty_buf_out_p2[zz];
                    pkt_sop_out_0[zz]    	<= pkt_sop_buf_out_p2[zz];
                    pkt_eop_out_0[zz]    	<= pkt_eop_buf_out_p2[zz];
                    pkt_err_out_0[zz]    	<= pkt_err_buf_out_p2[zz];
                    pkt_data_out_0[zz]   	<= pkt_data_buf_out_p2[zz];
                    pkt_blk_end_out_0[zz]   <= pkt_blk_end_buf_out_p2[zz];
                end else if (port_sel_1 == 2'b01) begin
                    pkt_val_out_0[zz]    	<= pkt_val_buf_out_p1[zz] & unseg_data_valid_1[zz];
                    pkt_mty_out_0[zz]    	<= pkt_mty_buf_out_p1[zz];
                    pkt_sop_out_0[zz]    	<= pkt_sop_buf_out_p1[zz];
                    pkt_eop_out_0[zz]    	<= pkt_eop_buf_out_p1[zz];
                    pkt_err_out_0[zz]    	<= pkt_err_buf_out_p1[zz];
                    pkt_data_out_0[zz]   	<= pkt_data_buf_out_p1[zz];
                    pkt_blk_end_out_0[zz]   <= pkt_blk_end_buf_out_p1[zz];
                end else begin
                    pkt_val_out_0[zz]    	<= pkt_val_buf_out_p0[zz] & unseg_data_valid_0[zz];
                    pkt_mty_out_0[zz]    	<= pkt_mty_buf_out_p0[zz];
                    pkt_sop_out_0[zz]    	<= pkt_sop_buf_out_p0[zz];
                    pkt_eop_out_0[zz]    	<= pkt_eop_buf_out_p0[zz];
                    pkt_err_out_0[zz]    	<= pkt_err_buf_out_p0[zz];
                    pkt_data_out_0[zz]   	<= pkt_data_buf_out_p0[zz];
                    pkt_blk_end_out_0[zz]   <= pkt_blk_end_buf_out_p0[zz];
                end
	        end else begin
				pkt_val_out_0[zz]    	<= 1'b0;
			end
        end
    end
endgenerate

//-----------------------------------------------------------------------------------------------------------------------

wire seg_buf_wr_en;
wire seg_buf_rd_en;

reg [$clog2(output_buffer_depth):0] out_buff_wr_cnt;
wire [$clog2(output_buffer_depth):0] out_blk_size_to_rd;
reg out_pkt_blk_rdy;
wire out_pkt_blk_rd_done;

wire seg_buf_wr_done;

reg [$clog2(output_buffer_depth):0] out_buff_wr_cnt_reg;
reg seg_buf_wr_done_reg;

assign seg_buf_wr_en = |pkt_val_out_0;

assign seg_buf_wr_done = |pkt_val_out_0 & |pkt_blk_end_out_0;

always @ (posedge aclk_axis_unseg) begin
    if (!aresetn_axis_unseg)
        out_buff_wr_cnt <= 'd0;
    else if (seg_buf_wr_en)
        if (seg_buf_wr_done)
            out_buff_wr_cnt <= 'd0;
        else
            out_buff_wr_cnt <= out_buff_wr_cnt + 1;
    else
        out_buff_wr_cnt <= out_buff_wr_cnt;
end

always @ (posedge aclk_axis_unseg) begin
    seg_buf_wr_done_reg <= seg_buf_wr_done;
    if (!aresetn_axis_unseg)
        out_buff_wr_cnt_reg <= 'd0;
    else if (seg_buf_wr_done)
        out_buff_wr_cnt_reg <= out_buff_wr_cnt + 1;
    else
        out_buff_wr_cnt_reg <= out_buff_wr_cnt_reg;
end

reg out_pkt_blk_rdy_q;
wire out_pkt_blk_rd_init;

always @ (posedge aclk_axis_unseg) begin
    out_pkt_blk_rdy_q   <= out_pkt_blk_rdy;
end

assign out_pkt_blk_rd_init = out_pkt_blk_rdy & ~out_pkt_blk_rdy_q;

wire blk_rd_cnt_valid;
wire blk_rd_cnt_buf_empty;
wire blk_rd_cnt_buf_wr_rst_busy;
wire blk_rd_cnt_buf_rd_rst_busy;

xpm_fifo_sync #(
   .CASCADE_HEIGHT(0),
   .DOUT_RESET_VALUE("0"),
   .ECC_MODE("no_ecc"),
   .FIFO_MEMORY_TYPE("auto"),
   .FIFO_READ_LATENCY(0),
   .FIFO_WRITE_DEPTH(16),
   .FULL_RESET_VALUE(0),
   .PROG_EMPTY_THRESH(0),
   .PROG_FULL_THRESH(0),
   .RD_DATA_COUNT_WIDTH(1),
   .READ_DATA_WIDTH($clog2(output_buffer_depth)+1),
   .READ_MODE("fwft"),
   .SIM_ASSERT_CHK(0),
   .USE_ADV_FEATURES("0000"),
   .WAKEUP_TIME(0),
   .WRITE_DATA_WIDTH($clog2(output_buffer_depth)+1),
   .WR_DATA_COUNT_WIDTH(1)
   )
xpm_fifo_sync_seg_blk_rd_cnt(
   .almost_empty(),
   .almost_full(),
   .data_valid(blk_rd_cnt_valid),
   .dbiterr(),
   .dout(out_blk_size_to_rd),
   .empty(blk_rd_cnt_buf_empty),
   .full(),
   .overflow(),
   .prog_empty(),
   .prog_full(),
   .rd_data_count(),
   .rd_rst_busy(blk_rd_cnt_buf_rd_rst_busy),
   .sbiterr(),
   .underflow(),
   .wr_ack(),
   .wr_data_count(),
   .wr_rst_busy(blk_rd_cnt_buf_wr_rst_busy),
   .din(out_buff_wr_cnt_reg),
   .injectdbiterr(1'b0),
   .injectsbiterr(1'b0),
   .rd_en(out_pkt_blk_rd_done),
   .rst(!aresetn_axis_unseg),
   .sleep(1'b0),
   .wr_clk(aclk_axis_unseg),
   .wr_en(seg_buf_wr_done_reg & !blk_rd_cnt_buf_wr_rst_busy)
   );

wire out_pkt_blk_rd_clr;

always @ (posedge aclk_axis_unseg) begin
    if (!aresetn_axis_unseg)
        out_pkt_blk_rdy <= 1'b0;
    else if (out_pkt_blk_rd_clr)
        out_pkt_blk_rdy <=  1'b0;
    else if (!blk_rd_cnt_buf_empty)
        out_pkt_blk_rdy <=  1'b1;
    else
        out_pkt_blk_rdy <= out_pkt_blk_rdy;
end

reg out_pkt_blk_rd;
wire out_buff_rdy;
reg [$clog2(output_buffer_depth):0] out_blk_size_to_rd_reg;

//----------------- Output buffer read enable generation

always @ (posedge aclk_axis_unseg) begin
    if (!aresetn_axis_unseg)
        out_blk_size_to_rd_reg <= 'd0;
    else if (out_pkt_blk_rd_init)
        out_blk_size_to_rd_reg <= out_blk_size_to_rd;
    else
        out_blk_size_to_rd_reg <= out_blk_size_to_rd_reg;
end

always @ (posedge aclk_axis_unseg) begin
    if (!aresetn_axis_unseg)
        out_pkt_blk_rd <= 1'b0;
    else if (out_pkt_blk_rd_done)
        out_pkt_blk_rd <= 1'b0;
    else if (out_pkt_blk_rd_init)
        out_pkt_blk_rd <= 1'b1;
    else
        out_pkt_blk_rd <= out_pkt_blk_rd;
end

reg [$clog2(output_buffer_depth):0] out_buff_rd_cnt;

assign out_pkt_blk_rd_done = (seg_buf_rd_en && out_buff_rd_cnt == out_blk_size_to_rd_reg-1) ? 1'b1 : 1'b0;
assign out_pkt_blk_rd_clr = out_pkt_blk_rd_done;

always @ (posedge aclk_axis_unseg) begin
    if (!aresetn_axis_unseg)
        out_buff_rd_cnt <= 'd0;
    else if (out_pkt_blk_rd_done)
        out_buff_rd_cnt <= 'd0;
    else if (seg_buf_rd_en)
        out_buff_rd_cnt <= out_buff_rd_cnt + 1;
    else
        out_buff_rd_cnt <= out_buff_rd_cnt;
end

//-----------------------------------------------------------------------------------------------------------------------

//----------------- Output Buffer

wire [`num_segments-1:0] unseg2seg_val;
wire [`segment_width-1:0] unseg2seg_dat [`num_segments-1:0];
wire [`num_segments-1:0] unseg2seg_sop;
wire [`num_segments-1:0] unseg2seg_eop;
wire [`num_segments-1:0] unseg2seg_err;
wire [($clog2(`segment_width/8))-1:0] unseg2seg_mty [`num_segments-1:0];

wire [`num_segments-1:0] seg_buf_aempty;
wire [`num_segments-1:0] seg_buf_afull;
wire [`num_segments-1:0] seg_buf_empty;
(* MARK_DEBUG= P_MARK_DEBUG *) wire [`num_segments-1:0] seg_buf_pfull;
wire [`num_segments-1:0] seg_buf_pempty;
wire [`num_segments-1:0] seg_data_valid;
wire [`num_segments-1:0] seg_rd_rst_busy;
wire [`num_segments-1:0] seg_wr_rst_busy;

assign out_buff_pfull = ~(|seg_buf_pempty);
assign out_buff_afull = |seg_buf_pfull;

assign seg_buf_rd_en = out_pkt_blk_rd & out_buff_rdy;

genvar xx;
generate
    for (xx=0; xx<`num_segments; xx=xx+1) begin
        xpm_fifo_sync #(
			.CASCADE_HEIGHT(0),
			.DOUT_RESET_VALUE("0"),
			.ECC_MODE("no_ecc"),
			.FIFO_MEMORY_TYPE("auto"),
			.FIFO_READ_LATENCY(1),
			.FIFO_WRITE_DEPTH(output_buffer_depth),
			.FULL_RESET_VALUE(0),
			`ifdef data_rate_200
			.PROG_EMPTY_THRESH(output_buffer_depth - ((input_buffer_depth+(local_buff_depth*4))*2)),
			`else
			.PROG_EMPTY_THRESH(output_buffer_depth - ((input_buffer_depth+(local_buff_depth*4))*`num_axis_ports)),
			`endif
			.PROG_FULL_THRESH(output_buffer_depth - 5),
			.RD_DATA_COUNT_WIDTH(1),
			.READ_DATA_WIDTH(`segment_width+seg_mty_w+4),
			.READ_MODE("std"),
			.SIM_ASSERT_CHK(0),
			.USE_ADV_FEATURES("1202"),
			.WAKEUP_TIME(0),
			.WRITE_DATA_WIDTH(`segment_width+seg_mty_w+4),
			.WR_DATA_COUNT_WIDTH(1)
        )
        xpm_fifo_sync_seg_out_buf1 (
           .almost_empty(seg_buf_aempty[xx]),
           .almost_full(seg_buf_afull[xx]),
           .data_valid(seg_data_valid[xx]),
           .dbiterr(),
           .dout({unseg2seg_mty[xx],unseg2seg_err[xx],unseg2seg_eop[xx],unseg2seg_sop[xx],unseg2seg_val[xx],unseg2seg_dat[xx]}),
           .empty(seg_buf_empty[xx]),
           .full(),
           .overflow(),
           .prog_empty(seg_buf_pempty[xx]),
           .prog_full(seg_buf_pfull[xx]),
           .rd_data_count(),
           .rd_rst_busy(seg_rd_rst_busy[xx]),
           .sbiterr(),
           .underflow(),
           .wr_ack(),
           .wr_data_count(),
           .wr_rst_busy(seg_wr_rst_busy[xx]),
           .din({pkt_mty_out_0[xx],pkt_err_out_0[xx],pkt_eop_out_0[xx],pkt_sop_out_0[xx],pkt_val_out_0[xx],pkt_data_out_0[xx]}),
           .injectdbiterr(1'b0),
           .injectsbiterr(1'b0),
           .rd_en(seg_buf_rd_en),
           .rst(!aresetn_axis_unseg),
           .sleep(1'b0),
           .wr_clk(aclk_axis_unseg),
           .wr_en(seg_buf_wr_en)
        );
    end
endgenerate

wire [`num_segments-1:0] unseg2seg_val_c;
wire [(`segment_width*`num_segments)-1:0] unseg2seg_dat_c;
wire [`num_segments-1:0] unseg2seg_sop_c;
wire [`num_segments-1:0] unseg2seg_eop_c;
wire [`num_segments-1:0] unseg2seg_err_c;
wire [(seg_mty_w*`num_segments)-1:0] unseg2seg_mty_c;

genvar y0;
generate
    for (y0=0; y0<`num_segments; y0=y0+1) begin
		assign unseg2seg_val_c[y0] = unseg2seg_val[y0];
		assign unseg2seg_sop_c[y0] = unseg2seg_sop[y0];
		assign unseg2seg_eop_c[y0] = unseg2seg_eop[y0];
		assign unseg2seg_err_c[y0] = unseg2seg_err[y0];
		assign unseg2seg_dat_c[((y0+1)*`segment_width)-1:y0*`segment_width] = unseg2seg_dat[y0];
		assign unseg2seg_mty_c[((y0+1)*seg_mty_w)-1:y0*seg_mty_w] = unseg2seg_mty[y0];
	end
endgenerate

wire [`num_segments-1:0] unseg2seg_out_Val_c;
wire [(`segment_width*`num_segments)-1:0] unseg2seg_out_Dat_c;
wire [`num_segments-1:0] unseg2seg_out_Sop_c;
wire [`num_segments-1:0] unseg2seg_out_Eop_c;
wire [`num_segments-1:0] unseg2seg_out_Err_c;
wire [(($clog2(`segment_width/8))*`num_segments)-1:0] unseg2seg_out_Mty_c;

wire seg_buf_out_aempty;
wire seg_buf_out_afull;
wire seg_buf_out_empty;
wire seg_buf_out_pfull;
wire seg_buf_out_pempty;
wire seg_data_out_valid;
wire seg_rd_out_rst_busy;
wire seg_wr_out_rst_busy;

wire seg_buf_out_wr_en;
wire seg_buf_out_rd_en;

assign seg_buf_out_wr_en = |seg_data_valid;
assign seg_buf_out_rd_en = tx_axis_tready_in & ~(seg_buf_out_empty);

`ifdef independant_clk

xpm_fifo_async #(
    .CASCADE_HEIGHT(0),
    .CDC_SYNC_STAGES(3),
    .DOUT_RESET_VALUE("0"),
    .ECC_MODE("no_ecc"),
    .FIFO_MEMORY_TYPE("auto"),
    .FIFO_READ_LATENCY(0),
    .FIFO_WRITE_DEPTH(io_buff_depth),
    .FULL_RESET_VALUE(0),
    .PROG_EMPTY_THRESH(3),
    .PROG_FULL_THRESH(io_buff_depth-5),
    .RD_DATA_COUNT_WIDTH(1),
    .READ_DATA_WIDTH((`segment_width+seg_mty_w+4)*`num_segments),
    .READ_MODE("fwft"),
    .RELATED_CLOCKS(0),
    .SIM_ASSERT_CHK(0),
    .USE_ADV_FEATURES("1008"),
    .WAKEUP_TIME(0),
    .WRITE_DATA_WIDTH((`segment_width+seg_mty_w+4)*`num_segments),
    .WR_DATA_COUNT_WIDTH(1)
	)
xpm_fifo_async_seg_out_buf (
    .almost_empty(seg_buf_out_aempty),
    .almost_full(seg_buf_out_afull),
    .data_valid(seg_data_out_valid),
    .dbiterr(),
    .dout({unseg2seg_out_Mty_c,unseg2seg_out_Err_c,unseg2seg_out_Eop_c,unseg2seg_out_Sop_c,unseg2seg_out_Val_c,unseg2seg_out_Dat_c}),
    .empty(seg_buf_out_empty),
    .full(),
    .overflow(),
    .prog_empty(seg_buf_out_pempty),
    .prog_full(seg_buf_out_pfull),
    .rd_data_count(),
    .rd_rst_busy(seg_rd_out_rst_busy),
    .sbiterr(),
    .underflow(),
    .wr_ack(),
    .wr_data_count(),
    .wr_rst_busy(seg_wr_out_rst_busy),
    .din({unseg2seg_mty_c,unseg2seg_err_c,unseg2seg_eop_c,unseg2seg_sop_c,unseg2seg_val_c,unseg2seg_dat_c}),
    .injectdbiterr(1'b0),
    .injectsbiterr(1'b0),
    .rd_clk(aclk_axis_seg_in),
    .rd_en(seg_buf_out_rd_en),
    .rst(!aresetn_axis_unseg),
    .sleep(1'b0),
    .wr_clk(aclk_axis_unseg),
    .wr_en(seg_buf_out_wr_en)
	);

`else

xpm_fifo_sync #(
    .CASCADE_HEIGHT(0),
    .DOUT_RESET_VALUE("0"),
    .ECC_MODE("no_ecc"),
    .FIFO_MEMORY_TYPE("auto"),
    .FIFO_READ_LATENCY(0),
    .FIFO_WRITE_DEPTH(io_buff_depth),
    .FULL_RESET_VALUE(0),
    .PROG_EMPTY_THRESH(3),
    .PROG_FULL_THRESH(io_buff_depth-5),
    .RD_DATA_COUNT_WIDTH(1),
    .READ_DATA_WIDTH((`segment_width+seg_mty_w+4)*`num_segments),
    .READ_MODE("fwft"),
    .SIM_ASSERT_CHK(0),
    .USE_ADV_FEATURES("1008"),
    .WAKEUP_TIME(0),
    .WRITE_DATA_WIDTH((`segment_width+seg_mty_w+4)*`num_segments),
    .WR_DATA_COUNT_WIDTH(1)
	)
xpm_fifo_sync_seg_out_buf (
    .almost_empty(seg_buf_out_aempty),
    .almost_full(seg_buf_out_afull),
    .data_valid(seg_data_out_valid),
    .dbiterr(),
    .dout({unseg2seg_out_Mty_c,unseg2seg_out_Err_c,unseg2seg_out_Eop_c,unseg2seg_out_Sop_c,unseg2seg_out_Val_c,unseg2seg_out_Dat_c}),
    .empty(seg_buf_out_empty),
    .full(),
    .overflow(),
    .prog_empty(seg_buf_out_pempty),
    .prog_full(seg_buf_out_pfull),
    .rd_data_count(),
    .rd_rst_busy(seg_rd_out_rst_busy),
    .sbiterr(),
    .underflow(),
    .wr_ack(),
    .wr_data_count(),
    .wr_rst_busy(seg_wr_out_rst_busy),
    .din({unseg2seg_mty_c,unseg2seg_err_c,unseg2seg_eop_c,unseg2seg_sop_c,unseg2seg_val_c,unseg2seg_dat_c}),
    .injectdbiterr(1'b0),
    .injectsbiterr(1'b0),
    .rd_en(seg_buf_out_rd_en),
    .rst(!aresetn_axis_unseg),
    .sleep(1'b0),
    .wr_clk(aclk_axis_unseg),
    .wr_en(seg_buf_out_wr_en)
	);

`endif

assign out_buff_rdy = ~seg_buf_out_afull;

wire [`num_segments-1:0] unseg2seg_out_Val;
wire [`segment_width-1:0] unseg2seg_out_Dat [`num_segments-1:0];
wire [`num_segments-1:0] unseg2seg_out_Sop;
wire [`num_segments-1:0] unseg2seg_out_Eop;
wire [`num_segments-1:0] unseg2seg_out_Err;
wire [($clog2(`segment_width/8))-1:0] unseg2seg_out_Mty [`num_segments-1:0];

genvar y1;
generate
    for (y1=0; y1<`num_segments; y1=y1+1) begin
		assign unseg2seg_out_Val[y1] = unseg2seg_out_Val_c[y1];
		assign unseg2seg_out_Sop[y1] = unseg2seg_out_Sop_c[y1];
		assign unseg2seg_out_Eop[y1] = unseg2seg_out_Eop_c[y1];
		assign unseg2seg_out_Err[y1] = unseg2seg_out_Err_c[y1];
		assign unseg2seg_out_Dat[y1] = unseg2seg_out_Dat_c[((y1+1)*`segment_width)-1:y1*`segment_width];
		assign unseg2seg_out_Mty[y1] = unseg2seg_out_Mty_c[((y1+1)*seg_mty_w)-1:y1*seg_mty_w];
	end
endgenerate

// Segment 0 output
assign Unseg2SegEna0_out = unseg2seg_out_Val[0] & seg_data_out_valid;
assign Unseg2SegDat0_out = unseg2seg_out_Dat[0];
assign Unseg2SegSop0_out = unseg2seg_out_Sop[0] & seg_data_out_valid;
assign Unseg2SegEop0_out = unseg2seg_out_Eop[0] & seg_data_out_valid;
assign Unseg2SegErr0_out = unseg2seg_out_Err[0];
assign Unseg2SegMty0_out = unseg2seg_out_Mty[0];
// Segment 1 output
assign Unseg2SegEna1_out = unseg2seg_out_Val[1] & seg_data_out_valid;
assign Unseg2SegDat1_out = unseg2seg_out_Dat[1];
assign Unseg2SegSop1_out = unseg2seg_out_Sop[1] & seg_data_out_valid;
assign Unseg2SegEop1_out = unseg2seg_out_Eop[1] & seg_data_out_valid;
assign Unseg2SegErr1_out = unseg2seg_out_Err[1];
assign Unseg2SegMty1_out = unseg2seg_out_Mty[1];

assign tx_axis_tvalid_out = seg_data_out_valid;

`ifdef en_port1
// Segment 2 output
assign Unseg2SegEna2_out = unseg2seg_out_Val[2] & seg_data_out_valid;
assign Unseg2SegDat2_out = unseg2seg_out_Dat[2];
assign Unseg2SegSop2_out = unseg2seg_out_Sop[2] & seg_data_out_valid;
assign Unseg2SegEop2_out = unseg2seg_out_Eop[2] & seg_data_out_valid;
assign Unseg2SegErr2_out = unseg2seg_out_Err[2];
assign Unseg2SegMty2_out = unseg2seg_out_Mty[2];
// Segment 3 output
assign Unseg2SegEna3_out = unseg2seg_out_Val[3] & seg_data_out_valid;
assign Unseg2SegDat3_out = unseg2seg_out_Dat[3];
assign Unseg2SegSop3_out = unseg2seg_out_Sop[3] & seg_data_out_valid;
assign Unseg2SegEop3_out = unseg2seg_out_Eop[3] & seg_data_out_valid;
assign Unseg2SegErr3_out = unseg2seg_out_Err[3];
assign Unseg2SegMty3_out = unseg2seg_out_Mty[3];
`endif
`ifdef en_port2
// Segment 4 output
assign Unseg2SegEna4_out = unseg2seg_out_Val[4] & seg_data_out_valid;
assign Unseg2SegDat4_out = unseg2seg_out_Dat[4];
assign Unseg2SegSop4_out = unseg2seg_out_Sop[4] & seg_data_out_valid;
assign Unseg2SegEop4_out = unseg2seg_out_Eop[4] & seg_data_out_valid;
assign Unseg2SegErr4_out = unseg2seg_out_Err[4];
assign Unseg2SegMty4_out = unseg2seg_out_Mty[4];
// Segment 5 outpu
assign Unseg2SegEna5_out = unseg2seg_out_Val[5] & seg_data_out_valid;
assign Unseg2SegDat5_out = unseg2seg_out_Dat[5];
assign Unseg2SegSop5_out = unseg2seg_out_Sop[5] & seg_data_out_valid;
assign Unseg2SegEop5_out = unseg2seg_out_Eop[5] & seg_data_out_valid;
assign Unseg2SegErr5_out = unseg2seg_out_Err[5];
assign Unseg2SegMty5_out = unseg2seg_out_Mty[5];
`endif
`ifdef en_port3
// Segment 6 output
assign Unseg2SegEna6_out = unseg2seg_out_Val[6] & seg_data_out_valid;
assign Unseg2SegDat6_out = unseg2seg_out_Dat[6];
assign Unseg2SegSop6_out = unseg2seg_out_Sop[6] & seg_data_out_valid;
assign Unseg2SegEop6_out = unseg2seg_out_Eop[6] & seg_data_out_valid;
assign Unseg2SegErr6_out = unseg2seg_out_Err[6];
assign Unseg2SegMty6_out = unseg2seg_out_Mty[6];
// Segment 7 output
assign Unseg2SegEna7_out = unseg2seg_out_Val[7] & seg_data_out_valid;
assign Unseg2SegDat7_out = unseg2seg_out_Dat[7];
assign Unseg2SegSop7_out = unseg2seg_out_Sop[7] & seg_data_out_valid;
assign Unseg2SegEop7_out = unseg2seg_out_Eop[7] & seg_data_out_valid;
assign Unseg2SegErr7_out = unseg2seg_out_Err[7];
assign Unseg2SegMty7_out = unseg2seg_out_Mty[7];
`endif

//-----------------------------------------------------------------------------------------------------------------------

`ifdef debug_en

// Error detection

// #1 First SoP should always start at Segment0, 1st SoP is either the very first SoP of a traffic or
// SoP followed by an EoP which is not ended in last segment in last cycle

reg unseg_val0_q;
wire unseg_val0_rp;

always @ (posedge aclk_axis_seg_in) begin
    unseg_val0_q	<= Unseg2SegEna0_out;
end

assign unseg_val0_rp = Unseg2SegEna0_out & ~unseg_val0_q;

assign error_missing_sop = unseg_val0_rp & ~ Unseg2SegSop0_out;

// #2 Packet should not be broken, valid should not go low in between SoP and EoP of a packet (DCMAC expectation)

reg [3:0] sop_cnt, eop_cnt;
reg pkt_open;
wire error_broken_pkt0;

integer yy;

always @(*) begin
    sop_cnt = 'd0;
    eop_cnt = 'd0;
    for (yy=0; yy<`num_segments; yy=yy+1) begin
        if (unseg2seg_out_Val[yy] && seg_buf_out_rd_en) begin
            if (unseg2seg_out_Sop[yy])
                sop_cnt = sop_cnt + 1;
            if (unseg2seg_out_Eop[yy])
                eop_cnt = eop_cnt + 1;
        end
    end
end

always @ (posedge aclk_axis_seg_in) begin
    if (seg_buf_out_rd_en)
        if (sop_cnt > eop_cnt)
            pkt_open <= 1'b1;
        else
            pkt_open <= 1'b0;
    else
         pkt_open <=  pkt_open;
end

assign error_broken_pkt0 = pkt_open & ~unseg_val0_q;		// Indicates a missing eop

integer z0;

reg error_broken_pkt1;

reg last_seg_eop;

always @ (posedge aclk_axis_seg_in) begin
    if (!aresetn_axis_seg_in) begin
        error_broken_pkt1	<= 1'b0;
		last_seg_eop		= 1'b1;
    end else begin
        for (z0=0; z0<`num_segments; z0=z0+1) begin
            if (unseg2seg_out_Val[z0] & seg_buf_out_rd_en) begin
				if (unseg2seg_out_Sop[z0] && !last_seg_eop) begin			// indicates a gap between eop & next sop within valid segments
					error_broken_pkt1   = 1'b1;								// packet get corrupted
				end else if (unseg2seg_out_Sop[z0] && last_seg_eop) begin	// next valid packet boundary detected
					error_broken_pkt1   = 1'b0;
				end else begin
					error_broken_pkt1   = error_broken_pkt1;
				end
				last_seg_eop		= unseg2seg_out_Eop[z0];
			end
		end
	end
end

//	#3 Corrupted data/mty values

reg err_data_mismatch;
reg [15:0] seg_last_data;
reg err_mty_nonzero;

integer z1;

always @ (posedge aclk_axis_seg_in) begin
    if (!aresetn_axis_seg_in) begin
		err_data_mismatch	= 1'b0;
		seg_last_data		= 'd0;
		err_mty_nonzero	= 1'b0;
	end else begin
		for (z1=0; z1<`num_segments; z1=z1+1) begin
			if (unseg2seg_out_Val[z1] & seg_buf_out_rd_en) begin
				if(unseg2seg_out_Dat[z1][15:0] - seg_last_data != 15'h0001) begin
					err_data_mismatch = 1'b1;
				end else begin
					err_data_mismatch = 1'b0;
				end
				seg_last_data = unseg2seg_out_Dat[z1][15:0];
				if(!unseg2seg_out_Eop[z1] && |unseg2seg_out_Mty[z1]) begin
					err_mty_nonzero = 1'b1;
				end else begin
					err_mty_nonzero = 1'b0;
				end
			end
		end
	end
end

// in the below assignment "err_data_mismatch" could be included only when checking with incrementing/counter data as packet input and at less rate(flow_control disabled)

assign error_broken_pkt_out = error_broken_pkt0 | error_broken_pkt1 | err_mty_nonzero;	// | err_data_mismatch;

`endif

//-----------------------------------------------------------------------------------------------------------------------

//----------------- Port Statistics

`ifdef statistics_en
    localparam statistics_en = 1;
`else
    localparam statistics_en = 0;
`endif

generate

if (statistics_en) begin

//----------------- Ouput packet count

reg [63:0] segment_pkt_cnt [`num_segments-1:0];
reg [63:0] segment_err_cnt [`num_segments-1:0];
reg [63:0] segment_pkt_sop_cnt [`num_segments-1:0];
reg [63:0] segment_byte_cnt [`num_segments-1:0];
wire [($clog2(`segment_width/8)):0] segment_validbytes [`num_segments-1:0];
reg [63:0] total_pktout_cnt;
reg [63:0] total_err_pktout_cnt;
reg [63:0] total_pktout_byte_cnt;

genvar ab;

for (ab=0; ab<`num_segments; ab=ab+1) begin
    mty_to_validbytes u_mty_to_valbytes
        (
        .mty_in(unseg2seg_out_Mty[ab]),
        .valid_bytes_out(segment_validbytes[ab])
        );
end

genvar cd;

for (cd=0; cd<`num_segments; cd=cd+1) begin
    always @ (posedge aclk_axis_seg_in) begin
        if (!aresetn_axis_seg_in)
            segment_byte_cnt[cd] <= 'd0;
        else if (unseg2seg_out_Val[cd] & seg_data_out_valid & seg_buf_out_rd_en)
            segment_byte_cnt[cd] <=  segment_byte_cnt[cd] + segment_validbytes[cd];
    end
end

integer ef;

always @ (*) begin
    total_pktout_byte_cnt   = 'd0;
    for (ef=0; ef<`num_segments; ef=ef+1) begin
        total_pktout_byte_cnt   = total_pktout_byte_cnt + segment_byte_cnt[ef];
    end
end

genvar gh;

for (gh=0; gh<`num_segments; gh=gh+1) begin
    always @ (posedge aclk_axis_seg_in) begin
        if (!aresetn_axis_seg_in)
            segment_pkt_cnt[gh] <= 'd0;
        else if (unseg2seg_out_Val[gh] && seg_data_out_valid && unseg2seg_out_Eop[gh] && seg_buf_out_rd_en)
            segment_pkt_cnt[gh] <= segment_pkt_cnt[gh] + 1;
    end
    always @ (posedge aclk_axis_seg_in) begin
        if (!aresetn_axis_seg_in)
            segment_err_cnt[gh] <= 'd0;
        else if (unseg2seg_out_Val[gh] && seg_data_out_valid && unseg2seg_out_Eop[gh] && unseg2seg_out_Err[gh] && seg_buf_out_rd_en)
            segment_err_cnt[gh] <= segment_err_cnt[gh] + 1;
    end
end

integer ij;

always @ (*) begin
    total_pktout_cnt   = 'd0;
    total_err_pktout_cnt   = 'd0;
    for (ij=0; ij<`num_segments; ij=ij+1) begin
        total_pktout_cnt   = total_pktout_cnt + segment_pkt_cnt[ij];
        total_err_pktout_cnt   = total_err_pktout_cnt + segment_err_cnt[ij];
    end
end

//----------------- Input packet count

reg [63:0] port_pkt_in_cnt [`num_axis_ports-1:0];
reg [63:0] port_err_pkt_in_cnt [`num_axis_ports-1:0];
reg [63:0] port_pkt_in_byte_cnt [`num_axis_ports-1:0];
reg [63:0] total_pktin_cnt;
reg [63:0] total_err_pktin_cnt;
reg [63:0] total_pktin_byte_cnt;

wire [($clog2(`unseg_axis_w/8)):0] port_valid_bytes [`num_axis_ports-1:0];

genvar g;
for (g=0; g<`num_axis_ports; g=g+1) begin
    tkeep_to_validbytes u_tkeep_to_valbytes
        (
        .tkeep_in(s_axis_tkeep_in[g]),
        .valid_bytes_out(port_valid_bytes[g])
        );
end

genvar i;
for (i=0; i<`num_axis_ports; i=i+1) begin
    always @ (posedge aclk_axis_unseg) begin
        if (!aresetn_axis_unseg)
            port_pkt_in_cnt[i] <= 'd0;
        else if (s_axis_tvalid_in[i] && (s_axis_tready_in[i] && !axis_pkt_blk_rdy_flg) && s_axis_tlast_in[i])
            port_pkt_in_cnt[i] <= port_pkt_in_cnt[i] + 'd1;
    end
	always @ (posedge aclk_axis_unseg) begin
        if (!aresetn_axis_unseg)
            port_err_pkt_in_cnt[i] <= 'd0;
        else if (s_axis_tvalid_in[i] && (s_axis_tready_in[i] && !axis_pkt_blk_rdy_flg) && s_axis_tlast_in[i] && s_axis_tuser_in[i])
            port_err_pkt_in_cnt[i] <= port_err_pkt_in_cnt[i] + 'd1;
    end
end

genvar j;
for (j=0; j<`num_axis_ports; j=j+1) begin
    always @ (posedge aclk_axis_unseg) begin
        if (!aresetn_axis_unseg)
            port_pkt_in_byte_cnt[j] <= 'd0;
        else if (s_axis_tvalid_in[j] && (s_axis_tready_in[j] && !axis_pkt_blk_rdy_flg))
            port_pkt_in_byte_cnt[j] <= port_pkt_in_byte_cnt[j] + port_valid_bytes[j];
    end
end

integer k;
always @ (*) begin
    total_pktin_cnt   		= 'd0;
    total_err_pktin_cnt   		= 'd0;
    total_pktin_byte_cnt   	= 'd0;
    for (k=0; k<`num_axis_ports; k=k+1) begin
        total_pktin_cnt   		= total_pktin_cnt + port_pkt_in_cnt[k];
        total_err_pktin_cnt     = total_err_pktin_cnt + port_err_pkt_in_cnt[k];
        total_pktin_byte_cnt   	= total_pktin_byte_cnt + port_pkt_in_byte_cnt[k];
    end
end

assign total_pkt_in_cnt 		= total_pktin_cnt;
assign total_err_pkt_in_cnt 	= total_err_pktin_cnt;
assign total_pkt_in_byte_cnt 	= total_pktin_byte_cnt;
assign total_pkt_out_cnt 		= total_pktout_cnt;
assign total_err_pkt_out_cnt 	= total_err_pktout_cnt;
assign total_pkt_out_byte_cnt	= total_pktout_byte_cnt;
`ifdef en_axis1
assign p1_pkt_in_cnt 			= port_pkt_in_cnt[1];
assign p1_err_pkt_in_cnt 		= port_err_pkt_in_cnt[1];
assign p1_pkt_in_byte_cnt 		= port_pkt_in_byte_cnt[1];
assign p0_pkt_in_cnt 			= port_pkt_in_cnt[0];
assign p0_err_pkt_in_cnt 		= port_err_pkt_in_cnt[0];
assign p0_pkt_in_byte_cnt 		= port_pkt_in_byte_cnt[0];
`endif

end
endgenerate

endmodule

//-----------------------------------------------------------------------------------------------------------------------

module tkeep_to_mty
    (
     input [(`segment_width/8)-1:0] tkeep_in,
     output wire [($clog2(`segment_width/8))-1:0] mty_out
    );

integer i;
reg [($clog2(`segment_width/8)):0] valid;

always @ (tkeep_in) begin
    valid = 0;
    for (i=0; i<(`segment_width/8); i=i+1)
        valid = valid + tkeep_in[i];
end

assign mty_out = (`segment_width/8) - valid;

endmodule

//-----------------------------------------------------------------------------------------------------------------------
//-----------------------------------------------------------------------------------------------------------------------

