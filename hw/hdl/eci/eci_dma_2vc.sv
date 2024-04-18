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

`ifndef ECI_DMA_2VC_SV
`define ECI_DMA_2VC_SV

import eci_cmd_defs::*;

import lynxTypes::*;

module eci_dma_2vc #(
      // Width of Read Descriptors
      // width of length descriptor 
      parameter LEN_WIDTH = 28,
      parameter TAG_WIDTH = 8,
      parameter AXIS_ADDR_WIDTH  = ECI_ADDR_BITS,
      parameter AXIS_ID_ENABLE   = 1,
      parameter AXIS_ID_WIDTH    = ECI_ID_BITS,   
      parameter AXIS_USER_WIDTH  = 1,
      parameter AXIS_USER_ENABLE = 0,
      parameter AXIS_DEST_WIDTH  = 8,
      parameter AXIS_DEST_ENABLE = 0,
      parameter ENABLE_UNALIGNED = 0,

      // Width of Read data stream 
      parameter AXIS_DATA_WIDTH = ECI_DATA_BITS, // DONT MODIFY 
      parameter AXIS_KEEP_WIDTH = (AXIS_DATA_WIDTH/8),
      parameter AXIS_KEEP_ENABLE = (AXIS_DATA_WIDTH>8),
      parameter AXIS_LAST_ENABLE = 1,

      parameter N_REG_STAGE_1 = 4,
      parameter N_REG_STAGE_2 = 4
) (
      input logic 					                                    aclk, 
      input logic 					                                    aresetn,

      //------Read + Write Descriptors Inputs------//
      
      //------ DMA Read Desc Inputs------//
      input logic [ AXIS_ADDR_WIDTH - 1 : 0 ] 		                    s_axis_read_desc_addr,
      input logic [ LEN_WIDTH - 1 : 0 ] 		                        s_axis_read_desc_len, //bytes 
      input logic 					                                    s_axis_read_desc_valid,
      output logic 					                                    s_axis_read_desc_ready,
      
      // Read Data Output 
      output logic [AXIS_DATA_WIDTH-1:0] 			                    m_axis_read_data_tdata,
      output logic [AXIS_KEEP_WIDTH-1:0] 			                    m_axis_read_data_tkeep,
      output logic 					                                    m_axis_read_data_tlast,
      output logic 					                                    m_axis_read_data_tvalid,
      input logic 					                                    m_axis_read_data_tready,
      
      // Read Descriptor Status Output 
      output logic 					                                    m_axis_read_desc_status_valid,

      //------ DMA Write desc + data Inputs ------//
      input logic [AXIS_ADDR_WIDTH-1:0] 		                        s_axis_write_desc_addr,
      input logic [LEN_WIDTH-1:0] 			                            s_axis_write_desc_len,  // bytes 
      input logic					                                    s_axis_write_desc_valid,
      output logic 					                                    s_axis_write_desc_ready,
      
      // Write Data input 
      input logic [AXIS_DATA_WIDTH-1:0] 		                        s_axis_write_data_tdata,
      input logic [AXIS_KEEP_WIDTH-1:0] 		                        s_axis_write_data_tkeep,
      input logic 					                                    s_axis_write_data_tlast,
      input logic 					                                    s_axis_write_data_tvalid,
      output logic 					                                    s_axis_write_data_tready,

      // Write status output 
      output logic 					                                    m_axis_write_desc_status_valid,
      
      //------ VC interface for read, write to CPU ------//
      
      //------ Read Request + Response VCs------//
      // Output read request to CPU VCs
      // MIB 6
      output logic [ ECI_WORD_BITS - 1 : 0 ]                            rdreq0_vc_data_o,
      output logic 					                                    rdreq0_vc_valid_o,
      output logic [4:0]                                                rdreq0_vc_size_o,
      input logic 					                                    rdreq0_vc_ready_i,

      // MIB 7
      output logic [ ECI_WORD_BITS - 1 : 0 ]                            rdreq1_vc_data_o,
      output logic 					                                    rdreq1_vc_valid_o,
      output logic [4:0]                                                rdreq1_vc_size_o,
      input logic 					                                    rdreq1_vc_ready_i,

      // Input Read response fROM CPU VCs
      // MOB 4
      input logic [ (17 * ECI_WORD_BITS) - 1 : 0 ]                      rdresp0_vc_data_i,
      input logic 					                                    rdresp0_vc_valid_i,
      input logic [4:0]                                                 rdresp0_vc_size_i,
      output logic 					                                    rdresp0_vc_ready_o,

      // MOB 5
      input logic [ (17 * ECI_WORD_BITS) - 1 : 0 ]                      rdresp1_vc_data_i,
      input logic 					                                    rdresp1_vc_valid_i,
      input logic [4:0]                                                 rdresp1_vc_size_i,
      output logic 					                                    rdresp1_vc_ready_o,

      //------ Write Request + Response VCs------//
      // Output write request to VCs
      // MIB 2
      output logic [(17 * ECI_WORD_BITS)-1:0]                           wrreq0_vc_data_o,
      output logic 					                                    wrreq0_vc_valid_o,
      output  logic [4:0]                                               wrreq0_vc_size_o,
      input logic 					                                    wrreq0_vc_ready_i,
      
      // MIB 3
      output logic [(17 * ECI_WORD_BITS)-1:0]                           wrreq1_vc_data_o,
      output logic 					                                    wrreq1_vc_valid_o,
      output  logic [4:0]                                               wrreq1_vc_size_o,
      input logic 					                                    wrreq1_vc_ready_i,

      // Input Read response from VCs
      // MOB 10
      input logic [ECI_WORD_BITS-1:0]                                   wrresp0_vc_data_i,
      input logic 					                                    wrresp0_vc_valid_i,
      input   logic [4:0]                                               wrresp0_vc_size_i,
      output logic 					                                    wrresp0_vc_ready_o,

      // MOB 11
      input logic [ECI_WORD_BITS-1:0]                                   wrresp1_vc_data_i,
      input   logic [4:0]                                               wrresp1_vc_size_i,
      input logic 					                                    wrresp1_vc_valid_i,
      output logic 					                                    wrresp1_vc_ready_o
   );

   // ----------------------------------------------------------------------------------

   localparam AXI_DATA_WIDTH = AXIS_DATA_WIDTH;
   localparam AXI_ADDR_WIDTH = AXIS_ADDR_WIDTH;
   localparam AXI_STRB_WIDTH = ( AXI_DATA_WIDTH / 8 );
   localparam AXI_ID_WIDTH   = AXIS_ID_WIDTH;
   localparam ENABLE_SG      = 0; // Scatter Gather not supported 
   localparam AXI_ARUSER_WIDTH = AXIS_USER_WIDTH;

   localparam N_STAGES_DBL_REG = 3;

   // ----------------------------------------------------------------------------------

   // AXI - Stage 0
   // ECI DMA -> Reg 1
   AXI4 #(.AXI4_DATA_BITS(ECI_DATA_BITS), .AXI4_ADDR_BITS(ECI_ADDR_BITS), .AXI4_ID_BITS(ECI_ID_BITS)) axi_s0 ();

   // AXI - Stage 1
   // Reg 1 -> Reorder buffers
   AXI4 #(.AXI4_DATA_BITS(ECI_DATA_BITS), .AXI4_ADDR_BITS(ECI_ADDR_BITS), .AXI4_ID_BITS(ECI_ID_BITS)) axi_s1 ();

   // AXI - Stage 2
   // Reorder buffers -> Reg 2
   AXI4 #(.AXI4_DATA_BITS(ECI_DATA_BITS), .AXI4_ADDR_BITS(ECI_ADDR_BITS), .AXI4_ID_BITS(ECI_ID_BITS)) axi_s2 [2] ();

   // AXI - Stage 3
   // Reg 2 -> Slaves
   AXI4 #(.AXI4_DATA_BITS(ECI_DATA_BITS), .AXI4_ADDR_BITS(ECI_ADDR_BITS), .AXI4_ID_BITS(ECI_ID_BITS)) axi_s3 [2] ();

   //
   // ECI DMA
   //
   AXI4S #(.AXI4S_DATA_BITS(ECI_DATA_BITS)) m_axis_read ();
   AXI4S #(.AXI4S_DATA_BITS(ECI_DATA_BITS)) s_axis_write ();

   dmaIntf rdCDMA ();
   dmaIntf wrCDMA ();

   assign m_axis_read_data_tvalid   = m_axis_read.tvalid;
   assign m_axis_read_data_tdata    = m_axis_read.tdata;
   assign m_axis_read_data_tkeep    = m_axis_read.tkeep;
   assign m_axis_read_data_tlast    = m_axis_read.tlast;
   assign m_axis_read.tready        = m_axis_read_data_tready;

   assign s_axis_write.tvalid       = s_axis_write_data_tvalid;
   assign s_axis_write.tdata        = s_axis_write_data_tdata;
   assign s_axis_write.tkeep        = s_axis_write_data_tkeep;
   assign s_axis_write.tlast        = s_axis_write_data_tlast;
   assign s_axis_write_data_tready  = s_axis_write.tready;

   assign rdCDMA.req.paddr = s_axis_read_desc_addr;
   assign rdCDMA.req.len = s_axis_read_desc_len;
   assign rdCDMA.req.ctl = 1'b1;
   assign rdCDMA.valid = s_axis_read_desc_valid;
   assign s_axis_read_desc_ready = rdCDMA.ready;
   assign m_axis_read_desc_status_valid = rdCDMA.rsp.done;

   assign wrCDMA.req.paddr = s_axis_write_desc_addr;
   assign wrCDMA.req.len = s_axis_write_desc_len;
   assign wrCDMA.req.ctl = 1'b1;
   assign wrCDMA.valid = s_axis_write_desc_valid;
   assign s_axis_write_desc_ready = wrCDMA.ready;
   assign m_axis_write_desc_status_valid = wrCDMA.rsp.done;

   cdma #(
      .BURST_LEN(2),
      .DATA_BITS(ECI_DATA_BITS),
      .ADDR_BITS(ECI_ADDR_BITS),
      .ID_BITS(ECI_ID_BITS),
      .BURST_OUTSTANDING(32)
   ) inst_axi_dma (
      .aclk(aclk),
      .aresetn(aresetn),

      .rd_CDMA(rdCDMA),
      .wr_CDMA(wrCDMA),

      .m_axi_ddr(axi_s0),

      .s_axis_ddr(s_axis_write),
      .m_axis_ddr(m_axis_read)
   );

   //
   // Reg 1
   //
   axi_reg_array_eci #(.N_STAGES(N_REG_STAGE_1)) inst_axi_reg_1 (.aclk(aclk), .aresetn(aresetn), .s_axi(axi_s0), .m_axi(axi_s1));

   //
   // Reorder buffer
   // 
   eci_reorder_top_2vc #(.N_THREADS(32), .N_BURSTED(2)) inst_reorder (.aclk(aclk), .aresetn(aresetn), .axi_in(axi_s1), .axi_out(axi_s2));

   //
   // Reg 2
   //
   axi_reg_array_eci #(.N_STAGES(N_REG_STAGE_2)) inst_axi_reg_20 (.aclk(aclk), .aresetn(aresetn), .s_axi(axi_s2[0]), .m_axi(axi_s3[0]));
   axi_reg_array_eci #(.N_STAGES(N_REG_STAGE_2)) inst_axi_reg_21 (.aclk(aclk), .aresetn(aresetn), .s_axi(axi_s2[1]), .m_axi(axi_s3[1]));
   
   // 
   // Rd slave
   //
   axi_eci_rd_slv_2vc inst_rd_slave_0 (
      .aclk	(aclk),
      .aresetn	(aresetn),

      // Read addr ch from axi_dma 
      .s_axi_arid	      (axi_s3[0].arid),    
      .s_axi_araddr	   (axi_s3[0].araddr),  
      .s_axi_arlen	   (axi_s3[0].arlen),   
      .s_axi_arvalid	   (axi_s3[0].arvalid), 
      .s_axi_arready	   (axi_s3[0].arready),

      // Read data ch to axi_dma 
      .s_axi_rid	      (axi_s3[0].rid),   
      .s_axi_rdata	   (axi_s3[0].rdata), 
      .s_axi_rvalid	   (axi_s3[0].rvalid),
      .s_axi_rready	   (axi_s3[0].rready),

      // Read request to CPU VCs 
      .mib_vc_data_o	   (rdreq0_vc_data_o), 
      .mib_vc_size_o	   (rdreq0_vc_size_o), 
      .mib_vc_valid_o	(rdreq0_vc_valid_o),
      .mib_vc_ready_i	(rdreq0_vc_ready_i),

      // Read response from CPU VCs 
      .mob_vc_data_i	   (rdresp0_vc_data_i), 
      .mob_vc_size_i	   (rdresp0_vc_size_i), 
      .mob_vc_valid_i	(rdresp0_vc_valid_i), 
      .mob_vc_ready_o	(rdresp0_vc_ready_o)
   );

   axi_eci_rd_slv_2vc inst_rd_slave_1 (
      .aclk	(aclk),
      .aresetn	(aresetn),

      // Read addr ch from axi_dma 
      .s_axi_arid	      (axi_s3[1].arid),    
      .s_axi_araddr	   (axi_s3[1].araddr),  
      .s_axi_arlen	   (axi_s3[1].arlen),   
      .s_axi_arvalid	   (axi_s3[1].arvalid), 
      .s_axi_arready	   (axi_s3[1].arready),

      // Read data ch to axi_dma 
      .s_axi_rid	      (axi_s3[1].rid),   
      .s_axi_rdata	   (axi_s3[1].rdata), 
      .s_axi_rvalid	   (axi_s3[1].rvalid),
      .s_axi_rready	   (axi_s3[1].rready),

      // Read request to CPU VCs 
      .mib_vc_data_o	   (rdreq1_vc_data_o), 
      .mib_vc_size_o	   (rdreq1_vc_size_o), 
      .mib_vc_valid_o	(rdreq1_vc_valid_o),
      .mib_vc_ready_i	(rdreq1_vc_ready_i),

      // Read response from CPU VCs 
      .mob_vc_data_i	   (rdresp1_vc_data_i), 
      .mob_vc_size_i	   (rdresp1_vc_size_i),  
      .mob_vc_valid_i	(rdresp1_vc_valid_i), 
      .mob_vc_ready_o	(rdresp1_vc_ready_o)
   );

   // 
   // Wr slave
   //
   axi_eci_wr_slv_2vc inst_wr_slave_0 (
      .aclk (aclk),
      .aresetn (aresetn),

      // AW channel from axi_dma
      .s_axi_awid	         (axi_s3[0].awid),
      .s_axi_awaddr	      (axi_s3[0].awaddr),
      .s_axi_awlen	      (axi_s3[0].awlen),
      .s_axi_awvalid	      (axi_s3[0].awvalid),
      .s_axi_awready	      (axi_s3[0].awready),

      // W Channel from axi_dma 
      .s_axi_wdata	      (axi_s3[0].wdata),
      .s_axi_wstrb	      (axi_s3[0].wstrb),
      .s_axi_wlast	      (axi_s3[0].wlast),
      .s_axi_wvalid	      (axi_s3[0].wvalid),
      .s_axi_wready	      (axi_s3[0].wready),

      // BResp Channel to axi_dma 
      .s_axi_bid	         (axi_s3[0].bid),
      .s_axi_bresp	      (axi_s3[0].bresp),
      .s_axi_bvalid	      (axi_s3[0].bvalid),
      .s_axi_bready	      (axi_s3[0].bready),

      // Write req + data to CPU VCs 
      .vc_pkt_o		      (wrreq0_vc_data_o),
      .vc_pkt_size_o       (wrreq0_vc_size_o),
      .vc_pkt_valid_o	   (wrreq0_vc_valid_o),
      .vc_pkt_ready_i	   (wrreq0_vc_ready_i),

      // Write response from CPU VCs
      .vc_pkt_i		      (wrresp0_vc_data_i),
      .vc_pkt_size_i        (wrresp0_vc_size_i),
      .vc_pkt_valid_i	   (wrresp0_vc_valid_i),
      .vc_pkt_ready_o	   (wrresp0_vc_ready_o)
   );

   axi_eci_wr_slv_2vc inst_wr_slave_1 (
      .aclk (aclk),
      .aresetn (aresetn),

      // AW channel from axi_dma
      .s_axi_awid	         (axi_s3[1].awid),
      .s_axi_awaddr	      (axi_s3[1].awaddr),
      .s_axi_awlen	      (axi_s3[1].awlen),
      .s_axi_awvalid	      (axi_s3[1].awvalid),
      .s_axi_awready	      (axi_s3[1].awready),

      // W Channel from axi_dma 
      .s_axi_wdata	      (axi_s3[1].wdata),
      .s_axi_wstrb	      (axi_s3[1].wstrb),
      .s_axi_wlast	      (axi_s3[1].wlast),
      .s_axi_wvalid	      (axi_s3[1].wvalid),
      .s_axi_wready	      (axi_s3[1].wready),

      // BResp Channel to axi_dma 
      .s_axi_bid	         (axi_s3[1].bid),
      .s_axi_bresp	      (axi_s3[1].bresp),
      .s_axi_bvalid	      (axi_s3[1].bvalid),
      .s_axi_bready	      (axi_s3[1].bready),

      // Write req + data to CPU VCs 
      .vc_pkt_o		      (wrreq1_vc_data_o),
      .vc_pkt_size_o       (wrreq1_vc_size_o),
      .vc_pkt_valid_o	   (wrreq1_vc_valid_o),
      .vc_pkt_ready_i	   (wrreq1_vc_ready_i),

      // Write response from CPU VCs
      .vc_pkt_i		      (wrresp1_vc_data_i),
      .vc_pkt_size_i        (wrresp1_vc_size_i),
      .vc_pkt_valid_i	   (wrresp1_vc_valid_i),
      .vc_pkt_ready_o	   (wrresp1_vc_ready_o)
   );
   
endmodule //eci_dma
`endif
