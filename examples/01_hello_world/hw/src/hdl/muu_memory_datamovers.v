//---------------------------------------------------------------------------
//--  Copyright 2015 - 2017 Systems Group, ETH Zurich
//--  Copyright 2018 - 2019 IMDEA Software Institute, Madrid
//-- 
//--  This hardware module is free software: you can redistribute it and/or
//--  modify it under the terms of the GNU General Public License as published
//--  by the Free Software Foundation, either version 3 of the License, or
//--  (at your option) any later version.
//-- 
//--  This program is distributed in the hope that it will be useful,
//--  but WITHOUT ANY WARRANTY; without even the implied warranty of
//--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//--  GNU General Public License for more details.
//-- 
//--  You should have received a copy of the GNU General Public License
//--  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//---------------------------------------------------------------------------


`timescale 1ns / 1ps
`default_nettype none
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/11/2013 02:22:48 PM
// Design Name: 
// Module Name: mem_inf
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////f////////////////////////////////////////////////////////////////


module muu_memory_datamovers
	#(
	  parameter HASHTABLE_MEM_SIZE = 16, //512bit lines x 2^SIZE
      parameter VALUESTORE_MEM_SIZE = 16 //512bit lines x 2^SIZE
	)
	(
	input wire sys_rst_n,
	input wire sys_clk,

	input wire user_clk,
	input wire  user_rst_n,
	

	// ht_dramRdData:     Pull Input, 1536b
	output  wire [511:0] ht_dramRdData_data,
	output  wire          ht_dramRdData_valid,
	input wire          ht_dramRdData_ready,

	// ht_cmd_dramRdData: Push Output, 10b
	input wire [63:0] ht_cmd_dramRdData_data,
	input wire       ht_cmd_dramRdData_valid,
	output  wire       ht_cmd_dramRdData_stall,

	// ht_dramWrData:     Push Output, 1536b
	input wire [511:0] ht_dramWrData_data,
	input wire          ht_dramWrData_valid,
	output  wire          ht_dramWrData_stall,

	// ht_cmd_dramWrData: Push Output, 10b
	input wire [63:0] ht_cmd_dramWrData_data,
	input wire       ht_cmd_dramWrData_valid,
	output  wire       ht_cmd_dramWrData_stall,
	
	// Update DRAM Connection

    // upd_dramRdData:     Pull Input, 1536b
    output  wire [511:0] upd_dramRdData_data,
    output  wire          upd_dramRdData_valid,
    input wire          upd_dramRdData_ready,

    // upd_cmd_dramRdData: Push Output, 10b
    input wire [63:0] upd_cmd_dramRdData_data,
    input wire       upd_cmd_dramRdData_valid,
    output  wire       upd_cmd_dramRdData_stall,

    // upd_dramWrData:     Push Output, 1536b
    input wire [511:0] upd_dramWrData_data,
    input wire          upd_dramWrData_valid,
    output  wire          upd_dramWrData_stall,

    // upd_cmd_dramWrData: Push Output, 10b
    input wire [63:0] upd_cmd_dramWrData_data,
    input wire       upd_cmd_dramWrData_valid,
    output  wire       upd_cmd_dramWrData_stall,

	input wire [63:0] ptr_rdcmd_data,
	input wire         ptr_rdcmd_valid,
	output  wire         ptr_rdcmd_ready,

	output wire [512-1:0]  ptr_rd_data,
	output wire         ptr_rd_valid,
	input  wire         ptr_rd_ready,	

	input wire [512-1:0] ptr_wr_data,
	input wire         ptr_wr_valid,
	output  wire         ptr_wr_ready,

	input wire [63:0] ptr_wrcmd_data,
	input wire         ptr_wrcmd_valid,
	output  wire         ptr_wrcmd_ready,


	input wire [63:0] bmap_rdcmd_data,
	input wire         bmap_rdcmd_valid,
	output  wire         bmap_rdcmd_ready,

	output wire [512-1:0]  bmap_rd_data,
	output wire         bmap_rd_valid,
	input  wire         bmap_rd_ready,	

	input wire [512-1:0] bmap_wr_data,
	input wire         bmap_wr_valid,
	output  wire         bmap_wr_ready,

	input wire [63:0] bmap_wrcmd_data,
	input wire         bmap_wrcmd_valid,
	output  wire         bmap_wrcmd_ready,


// Slave Interface Write Address Ports
output wire  [3:0]                                 c0_s_axi_awid,
output wire  [33:0]                                c0_s_axi_awaddr,
output wire  [7:0]                                 c0_s_axi_awlen,
output wire  [2:0]                                 c0_s_axi_awsize,
output wire  [1:0]                                 c0_s_axi_awburst,

output wire                                        c0_s_axi_awvalid,
input wire                                        c0_s_axi_awready,
// Slave Interface Write Data Ports
output wire  [511:0]              c0_s_axi_wdata,
output wire  [63:0]               c0_s_axi_wstrb,
output wire                       c0_s_axi_wlast,
output wire                       c0_s_axi_wvalid,
input wire                       c0_s_axi_wready,
// Slave Interface Write Response Ports
output wire                       c0_s_axi_bready,
input wire [3:0]                      c0_s_axi_bid,
input wire [1:0]                 c0_s_axi_bresp,
input wire                       c0_s_axi_bvalid,
// Slave Interface Read Address Ports
output wire  [3:0]                c0_s_axi_arid,
output wire  [33:0]          c0_s_axi_araddr,
output wire  [7:0]                                 c0_s_axi_arlen,
output wire  [2:0]                                 c0_s_axi_arsize,
output wire  [1:0]                                 c0_s_axi_arburst,
output wire                                        c0_s_axi_arvalid,
input wire                                       c0_s_axi_arready,
// Slave Interface Read Data Ports
output wire                                        c0_s_axi_rready,
input wire [3:0]                c0_s_axi_rid,
input wire [511:0]              c0_s_axi_rdata,
input wire [1:0]                                 c0_s_axi_rresp,
input wire                                       c0_s_axi_rlast,
input wire                                       c0_s_axi_rvalid,


// Slave Interface Write Address Ports
output wire  [3:0]                                 c1_s_axi_awid,
output wire  [33:0]                                c1_s_axi_awaddr,
output wire  [7:0]                                 c1_s_axi_awlen,
output wire  [2:0]                                 c1_s_axi_awsize,
output wire  [1:0]                                 c1_s_axi_awburst,

output wire                                        c1_s_axi_awvalid,
input wire                                        c1_s_axi_awready,
// Slave Interface Write Data Ports
output wire  [511:0]              c1_s_axi_wdata,
output wire  [63:0]               c1_s_axi_wstrb,
output wire                       c1_s_axi_wlast,
output wire                       c1_s_axi_wvalid,
input wire                       c1_s_axi_wready,
// Slave Interface Write Response Ports
output wire                       c1_s_axi_bready,
input wire [3:0]                      c1_s_axi_bid,
input wire [1:0]                 c1_s_axi_bresp,
input wire                       c1_s_axi_bvalid,
// Slave Interface Read Address Ports
output wire  [3:0]                c1_s_axi_arid,
output wire  [33:0]          c1_s_axi_araddr,
output wire  [7:0]                                 c1_s_axi_arlen,
output wire  [2:0]                                 c1_s_axi_arsize,
output wire  [1:0]                                 c1_s_axi_arburst,
output wire                                        c1_s_axi_arvalid,
input wire                                       c1_s_axi_arready,
// Slave Interface Read Data Ports
output wire                                        c1_s_axi_rready,
input wire [3:0]                c1_s_axi_rid,
input wire [511:0]              c1_s_axi_rdata,
input wire [1:0]                                 c1_s_axi_rresp,
input wire                                       c1_s_axi_rlast,
input wire                                       c1_s_axi_rvalid,


// Slave Interface Write Address Ports
output wire  [3:0]                                 c2_s_axi_awid,
output wire  [33:0]                                c2_s_axi_awaddr,
output wire  [7:0]                                 c2_s_axi_awlen,
output wire  [2:0]                                 c2_s_axi_awsize,
output wire  [1:0]                                 c2_s_axi_awburst,

output wire                                        c2_s_axi_awvalid,
input wire                                        c2_s_axi_awready,
// Slave Interface Write Data Ports
output wire  [511:0]              c2_s_axi_wdata,
output wire  [63:0]               c2_s_axi_wstrb,
output wire                       c2_s_axi_wlast,
output wire                       c2_s_axi_wvalid,
input wire                       c2_s_axi_wready,
// Slave Interface Write Response Ports
output wire                       c2_s_axi_bready,
input wire [3:0]                      c2_s_axi_bid,
input wire [1:0]                 c2_s_axi_bresp,
input wire                       c2_s_axi_bvalid,
// Slave Interface Read Address Ports
output wire  [3:0]                c2_s_axi_arid,
output wire  [33:0]          c2_s_axi_araddr,
output wire  [7:0]                                 c2_s_axi_arlen,
output wire  [2:0]                                 c2_s_axi_arsize,
output wire  [1:0]                                 c2_s_axi_arburst,
output wire                                        c2_s_axi_arvalid,
input wire                                       c2_s_axi_arready,
// Slave Interface Read Data Ports
output wire                                        c2_s_axi_rready,
input wire [3:0]                c2_s_axi_rid,
input wire [511:0]              c2_s_axi_rdata,
input wire [1:0]                                 c2_s_axi_rresp,
input wire                                       c2_s_axi_rlast,
input wire                                       c2_s_axi_rvalid,


// Slave Interface Write Address Ports
output wire  [3:0]                                 c3_s_axi_awid,
output wire  [33:0]                                c3_s_axi_awaddr,
output wire  [7:0]                                 c3_s_axi_awlen,
output wire  [2:0]                                 c3_s_axi_awsize,
output wire  [1:0]                                 c3_s_axi_awburst,

output wire                                        c3_s_axi_awvalid,
input wire                                        c3_s_axi_awready,
// Slave Interface Write Data Ports
output wire  [511:0]              c3_s_axi_wdata,
output wire  [63:0]               c3_s_axi_wstrb,
output wire                       c3_s_axi_wlast,
output wire                       c3_s_axi_wvalid,
input wire                       c3_s_axi_wready,
// Slave Interface Write Response Ports
output wire                       c3_s_axi_bready,
input wire [3:0]                      c3_s_axi_bid,
input wire [1:0]                 c3_s_axi_bresp,
input wire                       c3_s_axi_bvalid,
// Slave Interface Read Address Ports
output wire  [3:0]                c3_s_axi_arid,
output wire  [33:0]          c3_s_axi_araddr,
output wire  [7:0]                                 c3_s_axi_arlen,
output wire  [2:0]                                 c3_s_axi_arsize,
output wire  [1:0]                                 c3_s_axi_arburst,
output wire                                        c3_s_axi_arvalid,
input wire                                       c3_s_axi_arready,
// Slave Interface Read Data Ports
output wire                                        c3_s_axi_rready,
input wire [3:0]                c3_s_axi_rid,
input wire [511:0]              c3_s_axi_rdata,
input wire [1:0]                                 c3_s_axi_rresp,
input wire                                       c3_s_axi_rlast,
input wire                                       c3_s_axi_rvalid




);



wire           ht_s_axis_read_cmd_tvalid;
wire          ht_s_axis_read_cmd_tready;
wire[79:0]     ht_s_axis_read_cmd_tdata;

//read status
wire          ht_m_axis_read_sts_tvalid;
wire           ht_m_axis_read_sts_tready;
wire[7:0]     ht_m_axis_read_sts_tdata;
//read stream
wire[511:0]    ht_m_axis_read_tdata;
wire[63:0]     ht_m_axis_read_tkeep;
wire          ht_m_axis_read_tlast;
wire          ht_m_axis_read_tvalid;
wire           ht_m_axis_read_tempty;
wire           ht_m_axis_read_tready;

//write commands
wire           ht_s_axis_write_cmd_tvalid;
wire          ht_s_axis_write_cmd_tready;
wire[79:0]     ht_s_axis_write_cmd_tdata;
//write status
wire          ht_m_axis_write_sts_tvalid;
wire           ht_m_axis_write_sts_tready;
wire[31:0]     ht_m_axis_write_sts_tdata;
//write stream
wire[511:0]     ht_s_axis_write_tdata;
wire[63:0]      ht_s_axis_write_tkeep;
wire           ht_s_axis_write_tlast;
wire           ht_s_axis_write_tvalid;
wire          ht_s_axis_write_tready;



wire           upd_s_axis_read_cmd_tvalid;
wire          upd_s_axis_read_cmd_tready;
wire[79:0]     upd_s_axis_read_cmd_tdata;
//read status
wire          upd_m_axis_read_sts_tvalid;
wire           upd_m_axis_read_sts_tready;
wire[7:0]     upd_m_axis_read_sts_tdata;
//read stream
wire[511:0]    upd_m_axis_read_tdata;
wire[63:0]     upd_m_axis_read_tkeep;
wire          upd_m_axis_read_tlast;
wire          upd_m_axis_read_tvalid;
wire           upd_m_axis_read_tempty;
wire           upd_m_axis_read_tready;

//write commands
wire           upd_s_axis_write_cmd_tvalid;
wire          upd_s_axis_write_cmd_tready;
wire[79:0]     upd_s_axis_write_cmd_tdata;
//write status
wire          upd_m_axis_write_sts_tvalid;
wire           upd_m_axis_write_sts_tready;
wire[31:0]     upd_m_axis_write_sts_tdata;
//write stream
wire[511:0]     upd_s_axis_write_tdata;
wire[63:0]      upd_s_axis_write_tkeep;
wire           upd_s_axis_write_tlast;
wire           upd_s_axis_write_tvalid;
wire          upd_s_axis_write_tready;  


wire        axis_s1_rxread_cc2dm_tvalid;
wire        axis_s1_rxread_cc2dm_tready;
wire[511:0]  axis_s1_rxread_cc2dm_tdata;
wire[63:0]   axis_s1_rxread_cc2dm_tkeep;
wire        axis_s1_rxread_cc2dm_tlast;


wire        axis_s2_rxread_cc2dm_tvalid;
wire        axis_s2_rxread_cc2dm_tready;
wire[511:0]  axis_s2_rxread_cc2dm_tdata;
wire[63:0]   axis_s2_rxread_cc2dm_tkeep;
wire        axis_s2_rxread_cc2dm_tlast;

////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////

assign ht_m_axis_write_sts_tready = 1;
assign ht_m_axis_read_sts_tready = 1;

assign ht_s_axis_read_cmd_tvalid = ht_cmd_dramRdData_valid;
assign ht_cmd_dramRdData_stall = ~ht_s_axis_read_cmd_tready;
// HT is in lower 8GB 

assign ht_s_axis_read_cmd_tdata = {8'b000000,{(34-HASHTABLE_MEM_SIZE){1'b0}},ht_cmd_dramRdData_data[HASHTABLE_MEM_SIZE-1:0],6'h00,2'b00,7'b0000001,9'b000000000,ht_cmd_dramRdData_data[39:32],6'b000000};

assign ht_dramRdData_data = axis_s1_rxread_cc2dm_tdata;
assign ht_dramRdData_valid = axis_s1_rxread_cc2dm_tvalid;
assign axis_s1_rxread_cc2dm_tready = ht_dramRdData_ready;

assign ht_s_axis_write_cmd_tvalid = ht_cmd_dramWrData_valid;
assign ht_cmd_dramWrData_stall = ~ht_s_axis_write_cmd_tready;
// HT is in lower 8GB 
assign ht_s_axis_write_cmd_tdata = {8'b000000,{(34-HASHTABLE_MEM_SIZE){1'b0}},ht_cmd_dramWrData_data[HASHTABLE_MEM_SIZE-1:0],6'h00,2'b00,7'b0000001,9'b000000000,ht_cmd_dramWrData_data[39:32],6'b000000};

assign ht_s_axis_write_tdata = ht_dramWrData_data;
assign ht_s_axis_write_tkeep = 64'hFFFFFFFFFFFFFFFF;
assign ht_s_axis_write_tvalid = ht_dramWrData_valid;
assign ht_s_axis_write_tlast = 0;
assign ht_dramWrData_stall = ~ht_s_axis_write_tready;


assign upd_m_axis_write_sts_tready = 1;
assign upd_m_axis_read_sts_tready = 1;

assign upd_s_axis_read_cmd_tvalid = upd_cmd_dramRdData_valid;
assign upd_cmd_dramRdData_stall = ~upd_s_axis_read_cmd_tready;
// UPD is in upper memory region
assign upd_s_axis_read_cmd_tdata = {8'b000000,{(33-HASHTABLE_MEM_SIZE){1'b0}},1'b0,upd_cmd_dramRdData_data[VALUESTORE_MEM_SIZE-1:0],6'h00,2'b00,7'b0000001,9'b000000000,upd_cmd_dramRdData_data[39:32],6'b000000};

assign upd_dramRdData_data = axis_s2_rxread_cc2dm_tdata;
assign upd_dramRdData_valid = axis_s2_rxread_cc2dm_tvalid;
assign axis_s2_rxread_cc2dm_tready = upd_dramRdData_ready;

assign upd_s_axis_write_cmd_tvalid = upd_cmd_dramWrData_valid;
assign upd_cmd_dramWrData_stall = ~upd_s_axis_write_cmd_tready;
// UPD is in upper memory region
assign upd_s_axis_write_cmd_tdata = {8'b000000,{(33-HASHTABLE_MEM_SIZE){1'b0}},1'b0,upd_cmd_dramWrData_data[VALUESTORE_MEM_SIZE-1:0],6'h00,2'b00,7'b0000001,9'b000000000,upd_cmd_dramWrData_data[39:32],6'b000000};

assign upd_s_axis_write_tdata = upd_dramWrData_data;
assign upd_s_axis_write_tkeep = 64'hFFFFFFFFFFFFFFFF;
assign upd_s_axis_write_tvalid = upd_dramWrData_valid;
assign upd_s_axis_write_tlast = 0;
assign upd_dramWrData_stall = ~upd_s_axis_write_tready;


// user interface signals
wire                                       sys_clk_sync_rst;
wire                                       c1_mmcm_locked;




wire ht_s_buf_read_cmd_tvalid;
wire ht_s_buf_read_cmd_tready;
wire[79:0] ht_s_buf_read_cmd_tdata;

nukv_fifogen #(
.DATA_SIZE(80),
.ADDR_BITS(8)
) rxread_1_cmdbuf (
    .clk(user_clk),
    .rst(~user_rst_n),
  .s_axis_tvalid(ht_s_axis_read_cmd_tvalid),            // input wire s_axis_tvalid
  .s_axis_tready(ht_s_axis_read_cmd_tready),            // output wire s_axis_tready
  .s_axis_tdata(ht_s_axis_read_cmd_tdata),              // input wire [63 : 0] s_axis_tdata
  .m_axis_tvalid(ht_s_buf_read_cmd_tvalid),            // output wire m_axis_tvalid
  .m_axis_tready(ht_s_buf_read_cmd_tready),            // input wire m_axis_tready
  .m_axis_tdata(ht_s_buf_read_cmd_tdata)
  );

axi_read_kvs_datamover rxread_1_datamover (
  .m_axi_mm2s_aclk(sys_clk),                        // input wire m_axi_mm2s_aclk
  .m_axi_mm2s_aresetn(sys_rst_n),                  // input wire m_axi_mm2s_aresetn
  .mm2s_err(),                                      // output wire mm2s_err
  .m_axis_mm2s_cmdsts_aclk(user_clk),        // input wire m_axis_mm2s_cmdsts_aclk
  .m_axis_mm2s_cmdsts_aresetn(user_rst_n),  // input wire m_axis_mm2s_cmdsts_aresetn
/*  .s_axis_mm2s_cmd_tvalid(toeRX_s_axis_read_cmd_tvalid),          // input wire s_axis_mm2s_cmd_tvalid
  .s_axis_mm2s_cmd_tready(toeRX_s_axis_read_cmd_tready),          // output wire s_axis_mm2s_cmd_tready
  .s_axis_mm2s_cmd_tdata(toeRX_s_axis_read_cmd_tdata),            // input wire [71 : 0] s_axis_mm2s_cmd_tdata
  .m_axis_mm2s_sts_tvalid(toeRX_m_axis_read_sts_tvalid),          // output wire m_axis_mm2s_sts_tvalid
  .m_axis_mm2s_sts_tready(toeRX_m_axis_read_sts_tready),          // input wire m_axis_mm2s_sts_tready
  .m_axis_mm2s_sts_tdata(toeRX_m_axis_read_sts_tdata),            // output wire [7 : 0] m_axis_mm2s_sts_tdata
*/

.s_axis_mm2s_cmd_tvalid(ht_s_buf_read_cmd_tvalid),          // input wire s_axis_mm2s_cmd_tvalid
.s_axis_mm2s_cmd_tready(ht_s_buf_read_cmd_tready),          // output wire s_axis_mm2s_cmd_tready
.s_axis_mm2s_cmd_tdata(ht_s_buf_read_cmd_tdata),            // input wire [71 : 0] s_axis_mm2s_cmd_tdata
.m_axis_mm2s_sts_tvalid(ht_m_axis_read_sts_tvalid),          // output wire m_axis_mm2s_sts_tvalid
.m_axis_mm2s_sts_tready(ht_m_axis_read_sts_tready),          // input wire m_axis_mm2s_sts_tready
.m_axis_mm2s_sts_tdata(ht_m_axis_read_sts_tdata),            // output wire [7 : 0] m_axis_mm2s_sts_tdata

   
  .m_axis_mm2s_sts_tkeep(),            // output wire [0 : 0] m_axis_mm2s_sts_tkeep
  .m_axis_mm2s_sts_tlast(),            // output wire m_axis_mm2s_sts_tlast
  .m_axi_mm2s_arid(c0_s_axi_arid),                        // output wire [3 : 0] m_axi_mm2s_arid
  .m_axi_mm2s_araddr(c0_s_axi_araddr),                    // output wire [31 : 0] m_axi_mm2s_araddr
  .m_axi_mm2s_arlen(c0_s_axi_arlen),                      // output wire [7 : 0] m_axi_mm2s_arlen
  .m_axi_mm2s_arsize(c0_s_axi_arsize),                    // output wire [2 : 0] m_axi_mm2s_arsize
  .m_axi_mm2s_arburst(c0_s_axi_arburst),                  // output wire [1 : 0] m_axi_mm2s_arburst
  .m_axi_mm2s_arprot(),                    // output wire [2 : 0] m_axi_mm2s_arprot
  .m_axi_mm2s_arcache(),                  // output wire [3 : 0] m_axi_mm2s_arcache
  .m_axi_mm2s_aruser(),                    // output wire [3 : 0] m_axi_mm2s_aruser
  .m_axi_mm2s_arvalid(c0_s_axi_arvalid),                  // output wire m_axi_mm2s_arvalid
  .m_axi_mm2s_arready(c0_s_axi_arready),                  // input wire m_axi_mm2s_arready
  .m_axi_mm2s_rdata(c0_s_axi_rdata),                      // input wire [511 : 0] m_axi_mm2s_rdata
  .m_axi_mm2s_rresp(c0_s_axi_rresp),                      // input wire [1 : 0] m_axi_mm2s_rresp
  .m_axi_mm2s_rlast(c0_s_axi_rlast),                      // input wire m_axi_mm2s_rlast
  .m_axi_mm2s_rvalid(c0_s_axi_rvalid),                    // input wire m_axi_mm2s_rvalid
  .m_axi_mm2s_rready(c0_s_axi_rready),                    // output wire m_axi_mm2s_rready
  .m_axis_mm2s_tdata(axis_s1_rxread_cc2dm_tdata),                    // output wire [63 : 0] m_axis_mm2s_tdata
  .m_axis_mm2s_tkeep(axis_s1_rxread_cc2dm_tkeep),                    // output wire [7 : 0] m_axis_mm2s_tkeep
  .m_axis_mm2s_tlast(axis_s1_rxread_cc2dm_tlast),                    // output wire m_axis_mm2s_tlast
  .m_axis_mm2s_tvalid(axis_s1_rxread_cc2dm_tvalid),                  // output wire m_axis_mm2s_tvalid
  .m_axis_mm2s_tready(axis_s1_rxread_cc2dm_tready)                  // input wire m_axis_mm2s_tready
);

wire upd_s_buf_read_cmd_tvalid;
wire upd_s_buf_read_cmd_tready;
wire[79:0] upd_s_buf_read_cmd_tdata;

nukv_fifogen #(
.DATA_SIZE(80),
.ADDR_BITS(8)
) rxread_2_cmdbuf (
    .clk(user_clk),
    .rst(~user_rst_n),
  .s_axis_tvalid(upd_s_axis_read_cmd_tvalid),            // input wire s_axis_tvalid
  .s_axis_tready(upd_s_axis_read_cmd_tready),            // output wire s_axis_tready
  .s_axis_tdata(upd_s_axis_read_cmd_tdata),              // input wire [63 : 0] s_axis_tdata
  .m_axis_tvalid(upd_s_buf_read_cmd_tvalid),            // output wire m_axis_tvalid
  .m_axis_tready(upd_s_buf_read_cmd_tready),            // input wire m_axis_tready
  .m_axis_tdata(upd_s_buf_read_cmd_tdata)
  );

axi_read_kvs_datamover rxread_2_datamover (
  .m_axi_mm2s_aclk(sys_clk),                        // input wire m_axi_mm2s_aclk
  .m_axi_mm2s_aresetn(sys_rst_n),                  // input wire m_axi_mm2s_aresetn
  .mm2s_err(),                                      // output wire mm2s_err
  .m_axis_mm2s_cmdsts_aclk(user_clk),        // input wire m_axis_mm2s_cmdsts_aclk
  .m_axis_mm2s_cmdsts_aresetn(user_rst_n),  // input wire m_axis_mm2s_cmdsts_aresetn
/*  .s_axis_mm2s_cmd_tvalid(toeRX_s_axis_read_cmd_tvalid),          // input wire s_axis_mm2s_cmd_tvalid
  .s_axis_mm2s_cmd_tready(toeRX_s_axis_read_cmd_tready),          // output wire s_axis_mm2s_cmd_tready
  .s_axis_mm2s_cmd_tdata(toeRX_s_axis_read_cmd_tdata),            // input wire [71 : 0] s_axis_mm2s_cmd_tdata
  .m_axis_mm2s_sts_tvalid(toeRX_m_axis_read_sts_tvalid),          // output wire m_axis_mm2s_sts_tvalid
  .m_axis_mm2s_sts_tready(toeRX_m_axis_read_sts_tready),          // input wire m_axis_mm2s_sts_tready
  .m_axis_mm2s_sts_tdata(toeRX_m_axis_read_sts_tdata),            // output wire [7 : 0] m_axis_mm2s_sts_tdata
*/

.s_axis_mm2s_cmd_tvalid(upd_s_buf_read_cmd_tvalid),          // input wire s_axis_mm2s_cmd_tvalid
.s_axis_mm2s_cmd_tready(upd_s_buf_read_cmd_tready),          // output wire s_axis_mm2s_cmd_tready
.s_axis_mm2s_cmd_tdata(upd_s_buf_read_cmd_tdata),            // input wire [71 : 0] s_axis_mm2s_cmd_tdata
.m_axis_mm2s_sts_tvalid(upd_m_axis_read_sts_tvalid),          // output wire m_axis_mm2s_sts_tvalid
.m_axis_mm2s_sts_tready(upd_m_axis_read_sts_tready),          // input wire m_axis_mm2s_sts_tready
.m_axis_mm2s_sts_tdata(upd_m_axis_read_sts_tdata),            // output wire [7 : 0] m_axis_mm2s_sts_tdata

   
  .m_axis_mm2s_sts_tkeep(),            // output wire [0 : 0] m_axis_mm2s_sts_tkeep
  .m_axis_mm2s_sts_tlast(),            // output wire m_axis_mm2s_sts_tlast
  .m_axi_mm2s_arid(c1_s_axi_arid),                        // output wire [3 : 0] m_axi_mm2s_arid
  .m_axi_mm2s_araddr(c1_s_axi_araddr),                    // output wire [31 : 0] m_axi_mm2s_araddr
  .m_axi_mm2s_arlen(c1_s_axi_arlen),                      // output wire [7 : 0] m_axi_mm2s_arlen
  .m_axi_mm2s_arsize(c1_s_axi_arsize),                    // output wire [2 : 0] m_axi_mm2s_arsize
  .m_axi_mm2s_arburst(c1_s_axi_arburst),                  // output wire [1 : 0] m_axi_mm2s_arburst
  .m_axi_mm2s_arprot(),                    // output wire [2 : 0] m_axi_mm2s_arprot
  .m_axi_mm2s_arcache(),                  // output wire [3 : 0] m_axi_mm2s_arcache
  .m_axi_mm2s_aruser(),                    // output wire [3 : 0] m_axi_mm2s_aruser
  .m_axi_mm2s_arvalid(c1_s_axi_arvalid),                  // output wire m_axi_mm2s_arvalid
  .m_axi_mm2s_arready(c1_s_axi_arready),                  // input wire m_axi_mm2s_arready
  .m_axi_mm2s_rdata(c1_s_axi_rdata),                      // input wire [511 : 0] m_axi_mm2s_rdata
  .m_axi_mm2s_rresp(c1_s_axi_rresp),                      // input wire [1 : 0] m_axi_mm2s_rresp
  .m_axi_mm2s_rlast(c1_s_axi_rlast),                      // input wire m_axi_mm2s_rlast
  .m_axi_mm2s_rvalid(c1_s_axi_rvalid),                    // input wire m_axi_mm2s_rvalid
  .m_axi_mm2s_rready(c1_s_axi_rready),                    // output wire m_axi_mm2s_rready
  .m_axis_mm2s_tdata(axis_s2_rxread_cc2dm_tdata),                    // output wire [63 : 0] m_axis_mm2s_tdata
  .m_axis_mm2s_tkeep(axis_s2_rxread_cc2dm_tkeep),                    // output wire [7 : 0] m_axis_mm2s_tkeep
  .m_axis_mm2s_tlast(axis_s2_rxread_cc2dm_tlast),                    // output wire m_axis_mm2s_tlast
  .m_axis_mm2s_tvalid(axis_s2_rxread_cc2dm_tvalid),                  // output wire m_axis_mm2s_tvalid
  .m_axis_mm2s_tready(axis_s2_rxread_cc2dm_tready)                  // input wire m_axis_mm2s_tready
);


wire ht_s_buf_write_cmd_tvalid;
wire ht_s_buf_write_cmd_tready;
wire[79:0] ht_s_buf_write_cmd_tdata;

nukv_fifogen #(
.DATA_SIZE(80),
.ADDR_BITS(8)
) rxwrite_1_cmdbuf (
    .clk(user_clk),
    .rst(~user_rst_n),                // input wire s_axis_aclk
  .s_axis_tvalid(ht_s_axis_write_cmd_tvalid),            // input wire s_axis_tvalid
  .s_axis_tready(ht_s_axis_write_cmd_tready),            // output wire s_axis_tready
  .s_axis_tdata(ht_s_axis_write_cmd_tdata),              // input wire [63 : 0] s_axis_tdata
  .m_axis_tvalid(ht_s_buf_write_cmd_tvalid),            // output wire m_axis_tvalid
  .m_axis_tready(ht_s_buf_write_cmd_tready),            // input wire m_axis_tready
  .m_axis_tdata(ht_s_buf_write_cmd_tdata)
  );

axi_write_kvs_datamover rxwrite_1_datamover (
  .m_axi_s2mm_aclk(sys_clk),                        // input wire m_axi_s2mm_aclk
  .m_axi_s2mm_aresetn(sys_rst_n),                  // input wire m_axi_s2mm_aresetn
  .s2mm_err(),                                      // output wire s2mm_err
  .m_axis_s2mm_cmdsts_awclk(user_clk),      // input wire m_axis_s2mm_cmdsts_awclk
  .m_axis_s2mm_cmdsts_aresetn(user_rst_n),  // input wire m_axis_s2mm_cmdsts_aresetn
/*  .s_axis_s2mm_cmd_tvalid(toeRX_s_axis_write_cmd_tvalid),          // input wire s_axis_s2mm_cmd_tvalid
  .s_axis_s2mm_cmd_tready(toeRX_s_axis_write_cmd_tready),          // output wire s_axis_s2mm_cmd_tready
  .s_axis_s2mm_cmd_tdata(toeRX_s_axis_write_cmd_tdata),            // input wire [71 : 0] s_axis_s2mm_cmd_tdata
  .m_axis_s2mm_sts_tvalid(toeRX_m_axis_write_sts_tvalid),          // output wire m_axis_s2mm_sts_tvalid
  .m_axis_s2mm_sts_tready(toeRX_m_axis_write_sts_tready),          // input wire m_axis_s2mm_sts_tready
  .m_axis_s2mm_sts_tdata(toeRX_m_axis_write_sts_tdata),            // output wire [7 : 0] m_axis_s2mm_sts_tdata
*/

 
 .s_axis_s2mm_cmd_tvalid(ht_s_buf_write_cmd_tvalid),          // input wire s_axis_s2mm_cmd_tvalid
 .s_axis_s2mm_cmd_tready(ht_s_buf_write_cmd_tready),          // output wire s_axis_s2mm_cmd_tready
 .s_axis_s2mm_cmd_tdata(ht_s_buf_write_cmd_tdata),            // input wire [71 : 0] s_axis_s2mm_cmd_tdata
 .m_axis_s2mm_sts_tvalid(ht_m_axis_write_sts_tvalid),          // output wire m_axis_s2mm_sts_tvalid
 .m_axis_s2mm_sts_tready(ht_m_axis_write_sts_tready),          // input wire m_axis_s2mm_sts_tready
 .m_axis_s2mm_sts_tdata(ht_m_axis_write_sts_tdata),            // output wire [7 : 0] m_axis_s2mm_sts_tdata
   
  .m_axis_s2mm_sts_tkeep(),            // output wire [0 : 0] m_axis_s2mm_sts_tkeep
  .m_axis_s2mm_sts_tlast(),            // output wire m_axis_s2mm_sts_tlast
  .m_axi_s2mm_awid(c0_s_axi_awid),                        // output wire [3 : 0] m_axi_s2mm_awid
  .m_axi_s2mm_awaddr(c0_s_axi_awaddr),                    // output wire [31 : 0] m_axi_s2mm_awaddr
  .m_axi_s2mm_awlen(c0_s_axi_awlen),                      // output wire [7 : 0] m_axi_s2mm_awlen
  .m_axi_s2mm_awsize(c0_s_axi_awsize),                    // output wire [2 : 0] m_axi_s2mm_awsize
  .m_axi_s2mm_awburst(c0_s_axi_awburst),                  // output wire [1 : 0] m_axi_s2mm_awburst
  .m_axi_s2mm_awprot(),                    // output wire [2 : 0] m_axi_s2mm_awprot
  .m_axi_s2mm_awcache(),                  // output wire [3 : 0] m_axi_s2mm_awcache
  .m_axi_s2mm_awuser(),                    // output wire [3 : 0] m_axi_s2mm_awuser
  .m_axi_s2mm_awvalid(c0_s_axi_awvalid),                  // output wire m_axi_s2mm_awvalid
  .m_axi_s2mm_awready(c0_s_axi_awready),                  // input wire m_axi_s2mm_awready
  .m_axi_s2mm_wdata(c0_s_axi_wdata),                      // output wire [511 : 0] m_axi_s2mm_wdata
  .m_axi_s2mm_wstrb(c0_s_axi_wstrb),                      // output wire [63 : 0] m_axi_s2mm_wstrb
  .m_axi_s2mm_wlast(c0_s_axi_wlast),                      // output wire m_axi_s2mm_wlast
  .m_axi_s2mm_wvalid(c0_s_axi_wvalid),                    // output wire m_axi_s2mm_wvalid
  .m_axi_s2mm_wready(c0_s_axi_wready),                    // input wire m_axi_s2mm_wready
  .m_axi_s2mm_bresp(c0_s_axi_bresp),                      // input wire [1 : 0] m_axi_s2mm_bresp
  .m_axi_s2mm_bvalid(c0_s_axi_bvalid),                    // input wire m_axi_s2mm_bvalid
  .m_axi_s2mm_bready(c0_s_axi_bready),                    // output wire m_axi_s2mm_bready
  .s_axis_s2mm_tdata(ht_s_axis_write_tdata),                    // input wire [63 : 0] s_axis_s2mm_tdata
  .s_axis_s2mm_tkeep(ht_s_axis_write_tkeep),                    // input wire [7 : 0] s_axis_s2mm_tkeep
  .s_axis_s2mm_tlast(ht_s_axis_write_tlast),                    // input wire s_axis_s2mm_tlast
  .s_axis_s2mm_tvalid(ht_s_axis_write_tvalid),                  // input wire s_axis_s2mm_tvalid
  .s_axis_s2mm_tready(ht_s_axis_write_tready)                  // output wire s_axis_s2mm_tready
);



wire upd_s_buf_write_cmd_tvalid;
wire upd_s_buf_write_cmd_tready;
wire[79:0] upd_s_buf_write_cmd_tdata;

nukv_fifogen #(
.DATA_SIZE(80),
.ADDR_BITS(8)
) rxwrite_2_cmdbuf (
    .clk(user_clk),
    .rst(~user_rst_n),
  .s_axis_tvalid(upd_s_axis_write_cmd_tvalid),            // input wire s_axis_tvalid
  .s_axis_tready(upd_s_axis_write_cmd_tready),            // output wire s_axis_tready
  .s_axis_tdata(upd_s_axis_write_cmd_tdata),              // input wire [63 : 0] s_axis_tdata
  .m_axis_tvalid(upd_s_buf_write_cmd_tvalid),            // output wire m_axis_tvalid
  .m_axis_tready(upd_s_buf_write_cmd_tready),            // input wire m_axis_tready
  .m_axis_tdata(upd_s_buf_write_cmd_tdata)
  );


axi_write_kvs_datamover rxwrite_2_datamover (
  .m_axi_s2mm_aclk(sys_clk),                        // input wire m_axi_s2mm_aclk
  .m_axi_s2mm_aresetn(sys_rst_n),                  // input wire m_axi_s2mm_aresetn
  .s2mm_err(),                                      // output wire s2mm_err
  .m_axis_s2mm_cmdsts_awclk(user_clk),      // input wire m_axis_s2mm_cmdsts_awclk
  .m_axis_s2mm_cmdsts_aresetn(user_rst_n),  // input wire m_axis_s2mm_cmdsts_aresetn
/*  .s_axis_s2mm_cmd_tvalid(toeRX_s_axis_write_cmd_tvalid),          // input wire s_axis_s2mm_cmd_tvalid
  .s_axis_s2mm_cmd_tready(toeRX_s_axis_write_cmd_tready),          // output wire s_axis_s2mm_cmd_tready
  .s_axis_s2mm_cmd_tdata(toeRX_s_axis_write_cmd_tdata),            // input wire [71 : 0] s_axis_s2mm_cmd_tdata
  .m_axis_s2mm_sts_tvalid(toeRX_m_axis_write_sts_tvalid),          // output wire m_axis_s2mm_sts_tvalid
  .m_axis_s2mm_sts_tready(toeRX_m_axis_write_sts_tready),          // input wire m_axis_s2mm_sts_tready
  .m_axis_s2mm_sts_tdata(toeRX_m_axis_write_sts_tdata),            // output wire [7 : 0] m_axis_s2mm_sts_tdata
*/

 
 .s_axis_s2mm_cmd_tvalid(upd_s_buf_write_cmd_tvalid),          // input wire s_axis_s2mm_cmd_tvalid
 .s_axis_s2mm_cmd_tready(upd_s_buf_write_cmd_tready),          // output wire s_axis_s2mm_cmd_tready
 .s_axis_s2mm_cmd_tdata(upd_s_buf_write_cmd_tdata),            // input wire [71 : 0] s_axis_s2mm_cmd_tdata
 .m_axis_s2mm_sts_tvalid(upd_m_axis_write_sts_tvalid),          // output wire m_axis_s2mm_sts_tvalid
 .m_axis_s2mm_sts_tready(upd_m_axis_write_sts_tready),          // input wire m_axis_s2mm_sts_tready
 .m_axis_s2mm_sts_tdata(upd_m_axis_write_sts_tdata),            // output wire [7 : 0] m_axis_s2mm_sts_tdata
   
  .m_axis_s2mm_sts_tkeep(),            // output wire [0 : 0] m_axis_s2mm_sts_tkeep
  .m_axis_s2mm_sts_tlast(),            // output wire m_axis_s2mm_sts_tlast
  .m_axi_s2mm_awid(c1_s_axi_awid),                        // output wire [3 : 0] m_axi_s2mm_awid
  .m_axi_s2mm_awaddr(c1_s_axi_awaddr),                    // output wire [31 : 0] m_axi_s2mm_awaddr
  .m_axi_s2mm_awlen(c1_s_axi_awlen),                      // output wire [7 : 0] m_axi_s2mm_awlen
  .m_axi_s2mm_awsize(c1_s_axi_awsize),                    // output wire [2 : 0] m_axi_s2mm_awsize
  .m_axi_s2mm_awburst(c1_s_axi_awburst),                  // output wire [1 : 0] m_axi_s2mm_awburst
  .m_axi_s2mm_awprot(),                    // output wire [2 : 0] m_axi_s2mm_awprot
  .m_axi_s2mm_awcache(),                  // output wire [3 : 0] m_axi_s2mm_awcache
  .m_axi_s2mm_awuser(),                    // output wire [3 : 0] m_axi_s2mm_awuser
  .m_axi_s2mm_awvalid(c1_s_axi_awvalid),                  // output wire m_axi_s2mm_awvalid
  .m_axi_s2mm_awready(c1_s_axi_awready),                  // input wire m_axi_s2mm_awready
  .m_axi_s2mm_wdata(c1_s_axi_wdata),                      // output wire [511 : 0] m_axi_s2mm_wdata
  .m_axi_s2mm_wstrb(c1_s_axi_wstrb),                      // output wire [63 : 0] m_axi_s2mm_wstrb
  .m_axi_s2mm_wlast(c1_s_axi_wlast),                      // output wire m_axi_s2mm_wlast
  .m_axi_s2mm_wvalid(c1_s_axi_wvalid),                    // output wire m_axi_s2mm_wvalid
  .m_axi_s2mm_wready(c1_s_axi_wready),                    // input wire m_axi_s2mm_wready
  .m_axi_s2mm_bresp(c1_s_axi_bresp),                      // input wire [1 : 0] m_axi_s2mm_bresp
  .m_axi_s2mm_bvalid(c1_s_axi_bvalid),                    // input wire m_axi_s2mm_bvalid
  .m_axi_s2mm_bready(c1_s_axi_bready),                    // output wire m_axi_s2mm_bready
  .s_axis_s2mm_tdata(upd_s_axis_write_tdata),                    // input wire [63 : 0] s_axis_s2mm_tdata
  .s_axis_s2mm_tkeep(upd_s_axis_write_tkeep),                    // input wire [7 : 0] s_axis_s2mm_tkeep
  .s_axis_s2mm_tlast(upd_s_axis_write_tlast),                    // input wire s_axis_s2mm_tlast
  .s_axis_s2mm_tvalid(upd_s_axis_write_tvalid),                  // input wire s_axis_s2mm_tvalid
  .s_axis_s2mm_tready(upd_s_axis_write_tready)                  // output wire s_axis_s2mm_tready
);




//-----------------------------------------------------------------------------------------------------------
wire           bmap_s_axis_read_cmd_tvalid;
wire          bmap_s_axis_read_cmd_tready;
wire[79:0]     bmap_s_axis_read_cmd_tdata;

//read status
wire          bmap_m_axis_read_sts_tvalid;
wire           bmap_m_axis_read_sts_tready;
wire[7:0]     bmap_m_axis_read_sts_tdata;
//read stream
wire[511:0]    bmap_m_axis_read_tdata;
wire[63:0]     bmap_m_axis_read_tkeep;
wire          bmap_m_axis_read_tlast;
wire          bmap_m_axis_read_tvalid;
wire 		  bmap_m_axis_read_tready;

//write commands
wire           bmap_s_axis_write_cmd_tvalid;
wire          bmap_s_axis_write_cmd_tready;
wire[79:0]     bmap_s_axis_write_cmd_tdata;
//write status
wire          bmap_m_axis_write_sts_tvalid;
wire           bmap_m_axis_write_sts_tready;
wire[31:0]     bmap_m_axis_write_sts_tdata;
//write stream
wire[511:0]     bmap_s_axis_write_tdata;
wire[63:0]      bmap_s_axis_write_tkeep;
wire           bmap_s_axis_write_tlast;
wire           bmap_s_axis_write_tvalid;
wire          bmap_s_axis_write_tready;

wire           ptr_s_axis_read_cmd_tvalid;
wire          ptr_s_axis_read_cmd_tready;
wire[79:0]     ptr_s_axis_read_cmd_tdata;
//read status
wire          ptr_m_axis_read_sts_tvalid;
wire           ptr_m_axis_read_sts_tready;
wire[7:0]     ptr_m_axis_read_sts_tdata;
//read stream
wire[511:0]    ptr_m_axis_read_tdata;
wire[63:0]     ptr_m_axis_read_tkeep;
wire          ptr_m_axis_read_tlast;
wire          ptr_m_axis_read_tvalid;
wire           ptr_m_axis_read_tready;

//write commands
wire           ptr_s_axis_write_cmd_tvalid;
wire          ptr_s_axis_write_cmd_tready;
wire[79:0]     ptr_s_axis_write_cmd_tdata;
//write status
wire          ptr_m_axis_write_sts_tvalid;
wire           ptr_m_axis_write_sts_tready;
wire[31:0]     ptr_m_axis_write_sts_tdata;
//write stream
wire[511:0]     ptr_s_axis_write_tdata;
wire[63:0]      ptr_s_axis_write_tkeep;
wire           ptr_s_axis_write_tlast;
wire           ptr_s_axis_write_tvalid;
wire          ptr_s_axis_write_tready;  

assign bmap_m_axis_write_sts_tready = 1;
assign bmap_m_axis_read_sts_tready = 1;

assign bmap_s_axis_read_cmd_tvalid = bmap_rdcmd_valid;
assign bmap_rdcmd_ready = bmap_s_axis_read_cmd_tready;
assign bmap_s_axis_read_cmd_tdata = {8'b000000,2'b00,bmap_rdcmd_data[31:0],6'h00,2'b00,7'b0000001,9'b000000000,1'b0,bmap_rdcmd_data[32 +: 7],6'b000000};

assign bmap_rd_data = bmap_m_axis_read_tdata;
assign bmap_rd_valid = bmap_m_axis_read_tvalid;
assign bmap_m_axis_read_tready = bmap_rd_ready;

assign bmap_s_axis_write_cmd_tvalid = bmap_wrcmd_valid;
assign bmap_wrcmd_ready = bmap_s_axis_write_cmd_tready;
assign bmap_s_axis_write_cmd_tdata = {8'b000000,2'b00,bmap_wrcmd_data[31:0],6'h00,2'b00,7'b0000001,9'b000000000,1'b0,bmap_wrcmd_data[32 +: 7],6'b000000};

assign bmap_s_axis_write_tdata = bmap_wr_data;
assign bmap_s_axis_write_tkeep = 64'hFFFFFFFFFFFFFFFF;
assign bmap_s_axis_write_tvalid = bmap_wr_valid;
assign bmap_s_axis_write_tlast = 0;
assign bmap_wr_ready = bmap_s_axis_write_tready;

assign ptr_m_axis_write_sts_tready = 1;
assign ptr_m_axis_read_sts_tready = 1;

assign ptr_s_axis_read_cmd_tvalid = ptr_rdcmd_valid;
assign ptr_rdcmd_ready = ptr_s_axis_read_cmd_tready;
assign ptr_s_axis_read_cmd_tdata = {8'b000000,2'b00,ptr_rdcmd_data[31:0],6'h00,2'b00,7'b0000001,9'b000000000,1'b0,ptr_rdcmd_data[32 +: 7],6'b000000};

assign ptr_rd_data = ptr_m_axis_read_tdata;
assign ptr_rd_valid = ptr_m_axis_read_tvalid;
assign ptr_m_axis_read_tready = ptr_rd_ready;

assign ptr_s_axis_write_cmd_tvalid = ptr_wrcmd_valid;
assign ptr_wrcmd_ready = ptr_s_axis_write_cmd_tready;
assign ptr_s_axis_write_cmd_tdata = {8'b000000,2'b00,ptr_wrcmd_data[31:0],6'h00,2'b00,7'b0000001,9'b000000000,1'b0,ptr_wrcmd_data[32 +: 7],6'b000000};

assign ptr_s_axis_write_tdata = ptr_wr_data;
assign ptr_s_axis_write_tkeep = 64'hFFFFFFFFFFFFFFFF;
assign ptr_s_axis_write_tvalid = ptr_wr_valid;
assign ptr_s_axis_write_tlast = 0;
assign ptr_wr_ready = ptr_s_axis_write_tready;

wire bmap_s_buf_read_cmd_tvalid;
wire bmap_s_buf_read_cmd_tready;
wire[79:0] bmap_s_buf_read_cmd_tdata;

nukv_fifogen #(
.DATA_SIZE(80),
.ADDR_BITS(8)
) rxread_bmap_cmdbuf (
    .clk(user_clk),
    .rst(~user_rst_n),
  .s_axis_tvalid(bmap_s_axis_read_cmd_tvalid),            // input wire s_axis_tvalid
  .s_axis_tready(bmap_s_axis_read_cmd_tready),            // output wire s_axis_tready
  .s_axis_tdata(bmap_s_axis_read_cmd_tdata),              // input wire [63 : 0] s_axis_tdata
  .m_axis_tvalid(bmap_s_buf_read_cmd_tvalid),            // output wire m_axis_tvalid
  .m_axis_tready(bmap_s_buf_read_cmd_tready),            // input wire m_axis_tready
  .m_axis_tdata(bmap_s_buf_read_cmd_tdata)
  );

axi_read_kvs_datamover rxread_bmap_datamover (
  .m_axi_mm2s_aclk(sys_clk),                        // input wire m_axi_mm2s_aclk
  .m_axi_mm2s_aresetn(sys_rst_n),                  // input wire m_axi_mm2s_aresetn
  .mm2s_err(),                                      // output wire mm2s_err
  .m_axis_mm2s_cmdsts_aclk(user_clk),        // input wire m_axis_mm2s_cmdsts_aclk
  .m_axis_mm2s_cmdsts_aresetn(user_rst_n),  // input wire m_axis_mm2s_cmdsts_aresetn

.s_axis_mm2s_cmd_tvalid(bmap_s_buf_read_cmd_tvalid),          // input wire s_axis_mm2s_cmd_tvalid
.s_axis_mm2s_cmd_tready(bmap_s_buf_read_cmd_tready),          // output wire s_axis_mm2s_cmd_tready
.s_axis_mm2s_cmd_tdata(bmap_s_buf_read_cmd_tdata),            // input wire [71 : 0] s_axis_mm2s_cmd_tdata
.m_axis_mm2s_sts_tvalid(bmap_m_axis_read_sts_tvalid),          // output wire m_axis_mm2s_sts_tvalid
.m_axis_mm2s_sts_tready(bmap_m_axis_read_sts_tready),          // input wire m_axis_mm2s_sts_tready
.m_axis_mm2s_sts_tdata(bmap_m_axis_read_sts_tdata),            // output wire [7 : 0] m_axis_mm2s_sts_tdata

   
  .m_axis_mm2s_sts_tkeep(),            // output wire [0 : 0] m_axis_mm2s_sts_tkeep
  .m_axis_mm2s_sts_tlast(),            // output wire m_axis_mm2s_sts_tlast
  .m_axi_mm2s_arid(c2_s_axi_arid),                        // output wire [3 : 0] m_axi_mm2s_arid
  .m_axi_mm2s_araddr(c2_s_axi_araddr),                    // output wire [31 : 0] m_axi_mm2s_araddr
  .m_axi_mm2s_arlen(c2_s_axi_arlen),                      // output wire [7 : 0] m_axi_mm2s_arlen
  .m_axi_mm2s_arsize(c2_s_axi_arsize),                    // output wire [2 : 0] m_axi_mm2s_arsize
  .m_axi_mm2s_arburst(c2_s_axi_arburst),                  // output wire [1 : 0] m_axi_mm2s_arburst
  .m_axi_mm2s_arprot(),                    // output wire [2 : 0] m_axi_mm2s_arprot
  .m_axi_mm2s_arcache(),                  // output wire [3 : 0] m_axi_mm2s_arcache
  .m_axi_mm2s_aruser(),                    // output wire [3 : 0] m_axi_mm2s_aruser
  .m_axi_mm2s_arvalid(c2_s_axi_arvalid),                  // output wire m_axi_mm2s_arvalid
  .m_axi_mm2s_arready(c2_s_axi_arready),                  // input wire m_axi_mm2s_arready
  .m_axi_mm2s_rdata(c2_s_axi_rdata),                      // input wire [511 : 0] m_axi_mm2s_rdata
  .m_axi_mm2s_rresp(c2_s_axi_rresp),                      // input wire [1 : 0] m_axi_mm2s_rresp
  .m_axi_mm2s_rlast(c2_s_axi_rlast),                      // input wire m_axi_mm2s_rlast
  .m_axi_mm2s_rvalid(c2_s_axi_rvalid),                    // input wire m_axi_mm2s_rvalid
  .m_axi_mm2s_rready(c2_s_axi_rready),                    // output wire m_axi_mm2s_rready
  .m_axis_mm2s_tdata(bmap_m_axis_read_tdata),                    // output wire [63 : 0] m_axis_mm2s_tdata
  .m_axis_mm2s_tkeep(bmap_m_axis_read_tkeep),                    // output wire [7 : 0] m_axis_mm2s_tkeep
  .m_axis_mm2s_tlast(bmap_m_axis_read_tlast),                    // output wire m_axis_mm2s_tlast
  .m_axis_mm2s_tvalid(bmap_m_axis_read_tvalid),                  // output wire m_axis_mm2s_tvalid
  .m_axis_mm2s_tready(bmap_m_axis_read_tready)                  // input wire m_axis_mm2s_tready
);






wire ptr_s_buf_read_cmd_tvalid;
wire ptr_s_buf_read_cmd_tready;
wire[79:0] ptr_s_buf_read_cmd_tdata;

nukv_fifogen #(
.DATA_SIZE(80),
.ADDR_BITS(8)
) rxread_ptr_cmdbuf (
    .clk(user_clk),
    .rst(~user_rst_n),
  .s_axis_tvalid(ptr_s_axis_read_cmd_tvalid),            // input wire s_axis_tvalid
  .s_axis_tready(ptr_s_axis_read_cmd_tready),            // output wire s_axis_tready
  .s_axis_tdata(ptr_s_axis_read_cmd_tdata),              // input wire [63 : 0] s_axis_tdata
  .m_axis_tvalid(ptr_s_buf_read_cmd_tvalid),            // output wire m_axis_tvalid
  .m_axis_tready(ptr_s_buf_read_cmd_tready),            // input wire m_axis_tready
  .m_axis_tdata(ptr_s_buf_read_cmd_tdata)
  );

axi_read_kvs_datamover rxread_ptr_datamover (
  .m_axi_mm2s_aclk(sys_clk),                        // input wire m_axi_mm2s_aclk
  .m_axi_mm2s_aresetn(sys_rst_n),                  // input wire m_axi_mm2s_aresetn
  .mm2s_err(),                                      // output wire mm2s_err
  .m_axis_mm2s_cmdsts_aclk(user_clk),        // input wire m_axis_mm2s_cmdsts_aclk
  .m_axis_mm2s_cmdsts_aresetn(user_rst_n),  // input wire m_axis_mm2s_cmdsts_aresetn

.s_axis_mm2s_cmd_tvalid(ptr_s_buf_read_cmd_tvalid),          // input wire s_axis_mm2s_cmd_tvalid
.s_axis_mm2s_cmd_tready(ptr_s_buf_read_cmd_tready),          // output wire s_axis_mm2s_cmd_tready
.s_axis_mm2s_cmd_tdata(ptr_s_buf_read_cmd_tdata),            // input wire [71 : 0] s_axis_mm2s_cmd_tdata
.m_axis_mm2s_sts_tvalid(ptr_m_axis_read_sts_tvalid),          // output wire m_axis_mm2s_sts_tvalid
.m_axis_mm2s_sts_tready(ptr_m_axis_read_sts_tready),          // input wire m_axis_mm2s_sts_tready
.m_axis_mm2s_sts_tdata(ptr_m_axis_read_sts_tdata),            // output wire [7 : 0] m_axis_mm2s_sts_tdata

   
  .m_axis_mm2s_sts_tkeep(),            // output wire [0 : 0] m_axis_mm2s_sts_tkeep
  .m_axis_mm2s_sts_tlast(),            // output wire m_axis_mm2s_sts_tlast
  .m_axi_mm2s_arid(c3_s_axi_arid),                        // output wire [3 : 0] m_axi_mm2s_arid
  .m_axi_mm2s_araddr(c3_s_axi_araddr),                    // output wire [31 : 0] m_axi_mm2s_araddr
  .m_axi_mm2s_arlen(c3_s_axi_arlen),                      // output wire [7 : 0] m_axi_mm2s_arlen
  .m_axi_mm2s_arsize(c3_s_axi_arsize),                    // output wire [2 : 0] m_axi_mm2s_arsize
  .m_axi_mm2s_arburst(c3_s_axi_arburst),                  // output wire [1 : 0] m_axi_mm2s_arburst
  .m_axi_mm2s_arprot(),                    // output wire [2 : 0] m_axi_mm2s_arprot
  .m_axi_mm2s_arcache(),                  // output wire [3 : 0] m_axi_mm2s_arcache
  .m_axi_mm2s_aruser(),                    // output wire [3 : 0] m_axi_mm2s_aruser
  .m_axi_mm2s_arvalid(c3_s_axi_arvalid),                  // output wire m_axi_mm2s_arvalid
  .m_axi_mm2s_arready(c3_s_axi_arready),                  // input wire m_axi_mm2s_arready
  .m_axi_mm2s_rdata(c3_s_axi_rdata),                      // input wire [511 : 0] m_axi_mm2s_rdata
  .m_axi_mm2s_rresp(c3_s_axi_rresp),                      // input wire [1 : 0] m_axi_mm2s_rresp
  .m_axi_mm2s_rlast(c3_s_axi_rlast),                      // input wire m_axi_mm2s_rlast
  .m_axi_mm2s_rvalid(c3_s_axi_rvalid),                    // input wire m_axi_mm2s_rvalid
  .m_axi_mm2s_rready(c3_s_axi_rready),                    // output wire m_axi_mm2s_rready
  .m_axis_mm2s_tdata(ptr_m_axis_read_tdata),                    // output wire [63 : 0] m_axis_mm2s_tdata
  .m_axis_mm2s_tkeep(ptr_m_axis_read_tkeep),                    // output wire [7 : 0] m_axis_mm2s_tkeep
  .m_axis_mm2s_tlast(ptr_m_axis_read_tlast),                    // output wire m_axis_mm2s_tlast
  .m_axis_mm2s_tvalid(ptr_m_axis_read_tvalid),                  // output wire m_axis_mm2s_tvalid
  .m_axis_mm2s_tready(ptr_m_axis_read_tready)                  // input wire m_axis_mm2s_tready
);


wire bmap_s_buf_write_cmd_tvalid;
wire bmap_s_buf_write_cmd_tready;
wire[79:0] bmap_s_buf_write_cmd_tdata;

nukv_fifogen #(
.DATA_SIZE(80),
.ADDR_BITS(8)
) rxwrite_bmap_cmdbuf (
    .clk(user_clk),
    .rst(~user_rst_n),
  .s_axis_tvalid(bmap_s_axis_write_cmd_tvalid),            // input wire s_axis_tvalid
  .s_axis_tready(bmap_s_axis_write_cmd_tready),            // output wire s_axis_tready
  .s_axis_tdata(bmap_s_axis_write_cmd_tdata),              // input wire [63 : 0] s_axis_tdata
  .m_axis_tvalid(bmap_s_buf_write_cmd_tvalid),            // output wire m_axis_tvalid
  .m_axis_tready(bmap_s_buf_write_cmd_tready),            // input wire m_axis_tready
  .m_axis_tdata(bmap_s_buf_write_cmd_tdata)
  );

axi_write_kvs_datamover rxwrite_bmap_datamover (
  .m_axi_s2mm_aclk(sys_clk),                        // input wire m_axi_s2mm_aclk
  .m_axi_s2mm_aresetn(sys_rst_n),                  // input wire m_axi_s2mm_aresetn
  .s2mm_err(),                                      // output wire s2mm_err
  .m_axis_s2mm_cmdsts_awclk(user_clk),      // input wire m_axis_s2mm_cmdsts_awclk
  .m_axis_s2mm_cmdsts_aresetn(user_rst_n),  // input wire m_axis_s2mm_cmdsts_aresetn
 
 .s_axis_s2mm_cmd_tvalid(bmap_s_buf_write_cmd_tvalid),          // input wire s_axis_s2mm_cmd_tvalid
 .s_axis_s2mm_cmd_tready(bmap_s_buf_write_cmd_tready),          // output wire s_axis_s2mm_cmd_tready
 .s_axis_s2mm_cmd_tdata(bmap_s_buf_write_cmd_tdata),            // input wire [71 : 0] s_axis_s2mm_cmd_tdata
 .m_axis_s2mm_sts_tvalid(bmap_m_axis_write_sts_tvalid),          // output wire m_axis_s2mm_sts_tvalid
 .m_axis_s2mm_sts_tready(bmap_m_axis_write_sts_tready),          // input wire m_axis_s2mm_sts_tready
 .m_axis_s2mm_sts_tdata(bmap_m_axis_write_sts_tdata),            // output wire [7 : 0] m_axis_s2mm_sts_tdata
   
  .m_axis_s2mm_sts_tkeep(),            // output wire [0 : 0] m_axis_s2mm_sts_tkeep
  .m_axis_s2mm_sts_tlast(),            // output wire m_axis_s2mm_sts_tlast
  .m_axi_s2mm_awid(c2_s_axi_awid),                        // output wire [3 : 0] m_axi_s2mm_awid
  .m_axi_s2mm_awaddr(c2_s_axi_awaddr),                    // output wire [31 : 0] m_axi_s2mm_awaddr
  .m_axi_s2mm_awlen(c2_s_axi_awlen),                      // output wire [7 : 0] m_axi_s2mm_awlen
  .m_axi_s2mm_awsize(c2_s_axi_awsize),                    // output wire [2 : 0] m_axi_s2mm_awsize
  .m_axi_s2mm_awburst(c2_s_axi_awburst),                  // output wire [1 : 0] m_axi_s2mm_awburst
  .m_axi_s2mm_awprot(),                    // output wire [2 : 0] m_axi_s2mm_awprot
  .m_axi_s2mm_awcache(),                  // output wire [3 : 0] m_axi_s2mm_awcache
  .m_axi_s2mm_awuser(),                    // output wire [3 : 0] m_axi_s2mm_awuser
  .m_axi_s2mm_awvalid(c2_s_axi_awvalid),                  // output wire m_axi_s2mm_awvalid
  .m_axi_s2mm_awready(c2_s_axi_awready),                  // input wire m_axi_s2mm_awready
  .m_axi_s2mm_wdata(c2_s_axi_wdata),                      // output wire [511 : 0] m_axi_s2mm_wdata
  .m_axi_s2mm_wstrb(c2_s_axi_wstrb),                      // output wire [63 : 0] m_axi_s2mm_wstrb
  .m_axi_s2mm_wlast(c2_s_axi_wlast),                      // output wire m_axi_s2mm_wlast
  .m_axi_s2mm_wvalid(c2_s_axi_wvalid),                    // output wire m_axi_s2mm_wvalid
  .m_axi_s2mm_wready(c2_s_axi_wready),                    // input wire m_axi_s2mm_wready
  .m_axi_s2mm_bresp(c2_s_axi_bresp),                      // input wire [1 : 0] m_axi_s2mm_bresp
  .m_axi_s2mm_bvalid(c2_s_axi_bvalid),                    // input wire m_axi_s2mm_bvalid
  .m_axi_s2mm_bready(c2_s_axi_bready),                    // output wire m_axi_s2mm_bready
  .s_axis_s2mm_tdata(bmap_s_axis_write_tdata),                    // input wire [63 : 0] s_axis_s2mm_tdata
  .s_axis_s2mm_tkeep(bmap_s_axis_write_tkeep),                    // input wire [7 : 0] s_axis_s2mm_tkeep
  .s_axis_s2mm_tlast(bmap_s_axis_write_tlast),                    // input wire s_axis_s2mm_tlast
  .s_axis_s2mm_tvalid(bmap_s_axis_write_tvalid),                  // input wire s_axis_s2mm_tvalid
  .s_axis_s2mm_tready(bmap_s_axis_write_tready)                  // output wire s_axis_s2mm_tready
);


wire toeTX_s_buf_write_cmd_tvalid;
wire toeTX_s_buf_write_cmd_tready;
wire[79:0] toeTX_s_buf_write_cmd_tdata;




wire ptr_s_buf_write_cmd_tvalid;
wire ptr_s_buf_write_cmd_tready;
wire[79:0] ptr_s_buf_write_cmd_tdata;

nukv_fifogen #(
.DATA_SIZE(80),
.ADDR_BITS(8)
) rxwrite_ptr_cmdbuf (
    .clk(user_clk),
    .rst(~user_rst_n),
  .s_axis_tvalid(ptr_s_axis_write_cmd_tvalid),            // input wire s_axis_tvalid
  .s_axis_tready(ptr_s_axis_write_cmd_tready),            // output wire s_axis_tready
  .s_axis_tdata(ptr_s_axis_write_cmd_tdata),              // input wire [63 : 0] s_axis_tdata
  .m_axis_tvalid(ptr_s_buf_write_cmd_tvalid),            // output wire m_axis_tvalid
  .m_axis_tready(ptr_s_buf_write_cmd_tready),            // input wire m_axis_tready
  .m_axis_tdata(ptr_s_buf_write_cmd_tdata)
  );


axi_write_kvs_datamover rxwrite_ptr_datamover (
  .m_axi_s2mm_aclk(sys_clk),                        // input wire m_axi_s2mm_aclk
  .m_axi_s2mm_aresetn(sys_rst_n),                  // input wire m_axi_s2mm_aresetn
  .s2mm_err(),                                      // output wire s2mm_err
  .m_axis_s2mm_cmdsts_awclk(user_clk),      // input wire m_axis_s2mm_cmdsts_awclk
  .m_axis_s2mm_cmdsts_aresetn(user_rst_n),  // input wire m_axis_s2mm_cmdsts_aresetn

 
 .s_axis_s2mm_cmd_tvalid(ptr_s_buf_write_cmd_tvalid),          // input wire s_axis_s2mm_cmd_tvalid
 .s_axis_s2mm_cmd_tready(ptr_s_buf_write_cmd_tready),          // output wire s_axis_s2mm_cmd_tready
 .s_axis_s2mm_cmd_tdata(ptr_s_buf_write_cmd_tdata),            // input wire [71 : 0] s_axis_s2mm_cmd_tdata
 .m_axis_s2mm_sts_tvalid(ptr_m_axis_write_sts_tvalid),          // output wire m_axis_s2mm_sts_tvalid
 .m_axis_s2mm_sts_tready(ptr_m_axis_write_sts_tready),          // input wire m_axis_s2mm_sts_tready
 .m_axis_s2mm_sts_tdata(ptr_m_axis_write_sts_tdata),            // output wire [7 : 0] m_axis_s2mm_sts_tdata
   
  .m_axis_s2mm_sts_tkeep(),            // output wire [0 : 0] m_axis_s2mm_sts_tkeep
  .m_axis_s2mm_sts_tlast(),            // output wire m_axis_s2mm_sts_tlast
  .m_axi_s2mm_awid(c3_s_axi_awid),                        // output wire [3 : 0] m_axi_s2mm_awid
  .m_axi_s2mm_awaddr(c3_s_axi_awaddr),                    // output wire [31 : 0] m_axi_s2mm_awaddr
  .m_axi_s2mm_awlen(c3_s_axi_awlen),                      // output wire [7 : 0] m_axi_s2mm_awlen
  .m_axi_s2mm_awsize(c3_s_axi_awsize),                    // output wire [2 : 0] m_axi_s2mm_awsize
  .m_axi_s2mm_awburst(c3_s_axi_awburst),                  // output wire [1 : 0] m_axi_s2mm_awburst
  .m_axi_s2mm_awprot(),                    // output wire [2 : 0] m_axi_s2mm_awprot
  .m_axi_s2mm_awcache(),                  // output wire [3 : 0] m_axi_s2mm_awcache
  .m_axi_s2mm_awuser(),                    // output wire [3 : 0] m_axi_s2mm_awuser
  .m_axi_s2mm_awvalid(c3_s_axi_awvalid),                  // output wire m_axi_s2mm_awvalid
  .m_axi_s2mm_awready(c3_s_axi_awready),                  // input wire m_axi_s2mm_awready
  .m_axi_s2mm_wdata(c3_s_axi_wdata),                      // output wire [511 : 0] m_axi_s2mm_wdata
  .m_axi_s2mm_wstrb(c3_s_axi_wstrb),                      // output wire [63 : 0] m_axi_s2mm_wstrb
  .m_axi_s2mm_wlast(c3_s_axi_wlast),                      // output wire m_axi_s2mm_wlast
  .m_axi_s2mm_wvalid(c3_s_axi_wvalid),                    // output wire m_axi_s2mm_wvalid
  .m_axi_s2mm_wready(c3_s_axi_wready),                    // input wire m_axi_s2mm_wready
  .m_axi_s2mm_bresp(c3_s_axi_bresp),                      // input wire [1 : 0] m_axi_s2mm_bresp
  .m_axi_s2mm_bvalid(c3_s_axi_bvalid),                    // input wire m_axi_s2mm_bvalid
  .m_axi_s2mm_bready(c3_s_axi_bready),                    // output wire m_axi_s2mm_bready
  .s_axis_s2mm_tdata(ptr_s_axis_write_tdata),                    // input wire [63 : 0] s_axis_s2mm_tdata
  .s_axis_s2mm_tkeep(ptr_s_axis_write_tkeep),                    // input wire [7 : 0] s_axis_s2mm_tkeep
  .s_axis_s2mm_tlast(ptr_s_axis_write_tlast),                    // input wire s_axis_s2mm_tlast
  .s_axis_s2mm_tvalid(ptr_s_axis_write_tvalid),                  // input wire s_axis_s2mm_tvalid
  .s_axis_s2mm_tready(ptr_s_axis_write_tready)                  // output wire s_axis_s2mm_tready
);

//wire [3:0] c0_m_axi_arid_x;
//assign c0_m_axi_arid = c0_m_axi_arid_x[0];

//wire [3:0] c0_s_axi_arid_x;
//assign c0_s_axi_arid = c0_s_axi_arid_x[0];




endmodule
`default_nettype wire