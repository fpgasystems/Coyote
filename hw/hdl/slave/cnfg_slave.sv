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

import lynxTypes::*;

`include "axi_macros.svh"
`include "lynx_macros.svh"

module cnfg_slave #(
  parameter integer           ID_REG = 0 
) (
  input  logic                aclk,
  input  logic                aresetn,
  
  // Control bus (HOST)
  AXI4L.s                      s_axi_ctrl,

`ifdef EN_BPSS
  // Request user logic
  metaIntf.s                  s_bpss_rd_req,
  metaIntf.s                  s_bpss_wr_req,
  metaIntf.m                  m_bpss_rd_done,
  metaIntf.m                  m_bpss_wr_done,
`endif

`ifdef MULT_STRM_AXI
    metaIntf.m                  m_rd_user_mux,
    metaIntf.m                  m_wr_user_mux,
`endif 

`ifdef EN_RDMA_0
	// RDMA request QSFP0
	metaIntf.m  			    m_rdma_0_sq,
    metaIntf.s  			    s_rdma_0_ack,
`ifdef EN_RPC
    metaIntf.s                  s_rdma_0_sq,
    metaIntf.m                  m_rdma_0_ack,
`endif  
`endif

`ifdef EN_RDMA_1
	// RDMA request QSFP1
	metaIntf.m  			    m_rdma_1_sq,
    metaIntf.s  			    s_rdma_1_ack,
`ifdef EN_RPC
    metaIntf.s                  s_rdma_1_sq,
    metaIntf.m                  m_rdma_1_ack,
`endif     
`endif 
   
  // Request out
  metaIntf.m                  m_rd_req,
  metaIntf.m                  m_wr_req,

  // Config intf
`ifdef EN_STRM
    metaIntf.s                  s_host_done_rd,
    metaIntf.s                  s_host_done_wr,
`endif
    
`ifdef EN_MEM
    metaIntf.s                  s_card_done_rd,
    metaIntf.s                  s_card_done_wr,
    metaIntf.s                  s_sync_done_rd,
    metaIntf.s                  s_sync_done_wr,
`endif

`ifdef EN_WB
    metaIntf.m                  m_wback,
`endif

    metaIntf.s                  s_pfault_rd,    
    metaIntf.s                  s_pfault_wr,

  // TCP Session Management
`ifdef EN_TCP_0
    metaIntf.m                  m_open_port_cmd_0,
    metaIntf.m                  m_open_con_cmd_0,
    metaIntf.m                  m_close_con_cmd_0,
    metaIntf.s                  s_open_con_sts_0,
    metaIntf.s                  s_open_port_sts_0,
`endif

`ifdef EN_TCP_1
    metaIntf.m                  m_open_port_cmd_1,
    metaIntf.m                  m_open_con_cmd_1,
    metaIntf.m                  m_close_con_cmd_1,
    metaIntf.s                  s_open_con_sts_1,
    metaIntf.s                  s_open_port_sts_1,
`endif

  // Control
  output logic                restart_rd,
  output logic                restart_wr,
  output logic                decouple,
  output logic                pf_irq
);  

// -- Decl -------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------

// Constants
localparam integer N_REGS = 2 * (2**PID_BITS);
localparam integer ADDR_LSB = $clog2(AXIL_DATA_BITS/8);
localparam integer ADDR_MSB = $clog2(N_REGS);
localparam integer AXIL_ADDR_BITS = ADDR_LSB + ADDR_MSB;
localparam integer N_WBS = N_RDMA + 2;
localparam integer N_WBS_BITS = $clog2(N_WBS);

localparam integer CTRL_BYTES = 8;

// Internal registers
logic [AXIL_ADDR_BITS-1:0] axi_awaddr;
logic axi_awready;
logic [AXIL_ADDR_BITS-1:0] axi_araddr;
logic axi_arready;
logic [1:0] axi_bresp;
logic axi_bvalid;
logic axi_wready;
logic [AXIL_DATA_BITS-1:0] axi_rdata;
logic [1:0] axi_rresp;
logic axi_rvalid;

logic [3:0][AXIL_DATA_BITS-1:0] axi_rdata_bram;
logic [1:0] axi_mux;

// Slave Registers
logic [N_REGS-1:0][AXIL_DATA_BITS-1:0] slv_reg;
logic slv_reg_rden;
logic slv_reg_wren;
logic aw_en;

// Internal signals
logic irq_pending;
logic rd_sent_host, rd_sent_card, rd_sent_sync;
logic wr_sent_host, wr_sent_card, wr_sent_sync;

logic [31:0] rd_queue_used;
logic [31:0] wr_queue_used;

metaIntf #(.STYPE(dma_rsp_t)) meta_host_done_rd_out ();
metaIntf #(.STYPE(dma_rsp_t)) meta_card_done_rd_out ();
metaIntf #(.STYPE(dma_rsp_t)) meta_sync_done_rd_out ();
metaIntf #(.STYPE(dma_rsp_t)) meta_done_rd ();

logic rd_C;
logic [3:0] a_we_rd;
logic [PID_BITS-1:0] a_addr_rd;
logic [PID_BITS-1:0] b_addr_rd;
logic [31:0] a_data_in_rd;
logic [31:0] a_data_out_rd;
logic [31:0] b_data_out_rd;
logic rd_clear;
logic [PID_BITS-1:0] rd_clear_addr;

metaIntf #(.STYPE(dma_rsp_t)) meta_host_done_wr_out ();
metaIntf #(.STYPE(dma_rsp_t)) meta_card_done_wr_out ();
metaIntf #(.STYPE(dma_rsp_t)) meta_sync_done_wr_out ();
metaIntf #(.STYPE(dma_rsp_t)) meta_done_wr ();

logic wr_C;
logic [3:0] a_we_wr;
logic [PID_BITS-1:0] a_addr_wr;
logic [PID_BITS-1:0] b_addr_wr;
logic [31:0] a_data_in_wr;
logic [31:0] a_data_out_wr;
logic [31:0] b_data_out_wr;
logic wr_clear;
logic [PID_BITS-1:0] wr_clear_addr;

`ifdef EN_WB
metaIntf #(.STYPE(wback_t)) wback [N_WBS] ();
metaIntf #(.STYPE(wback_t)) wback_q [N_WBS] ();
metaIntf #(.STYPE(wback_t)) wback_arb ();
`endif

`ifdef EN_RDMA_0
logic [31:0] rdma_0_queue_used;
logic rdma_0_post;

metaIntf #(.STYPE(rdma_ack_t)) rdma_0_ack ();
logic rdma_0_C;
logic [3:0] a_we_rdma_0;
logic [PID_BITS-1:0] a_addr_rdma_0;
logic [PID_BITS-1:0] b_addr_rdma_0;
logic [31:0] a_data_in_rdma_0;
logic [31:0] a_data_out_rdma_0;
logic [31:0] b_data_out_rdma_0;
logic rdma_0_clear;
logic [PID_BITS-1:0] rdma_0_clear_addr;

metaIntf #(.STYPE(rdma_ack_t)) cmplt_que_rdma_0_in ();
metaIntf #(.STYPE(rdma_ack_t)) cmplt_que_rdma_0_out ();
`endif

`ifdef EN_RDMA_1
logic [31:0] rdma_1_queue_used;
logic rdma_1_post;

metaIntf #(.STYPE(rdma_ack_t)) rdma_1_ack ();
logic rdma_1_C;
logic [3:0] a_we_rdma_1;
logic [PID_BITS-1:0] a_addr_rdma_1;
logic [PID_BITS-1:0] b_addr_rdma_1;
logic [31:0] a_data_in_rdma_1;
logic [31:0] a_data_out_rdma_1;
logic [31:0] b_data_out_rdma_1;
logic rdma_1_clear;
logic [PID_BITS-1:0] rdma_1_clear_addr;

metaIntf #(.STYPE(rdma_ack_t)) cmplt_que_rdma_1_in ();
metaIntf #(.STYPE(rdma_ack_t)) cmplt_que_rdma_1_out ();
`endif

`ifdef EN_TCP_0 
metaIntf #(.STYPE(tcp_listen_req_t)) open_port_cmd_0_qin ();
metaIntf #(.STYPE(tcp_listen_rsp_t)) open_port_sts_0_qin ();
metaIntf #(.STYPE(tcp_open_req_t)) open_con_cmd_0_qin ();
metaIntf #(.STYPE(tcp_open_rsp_t)) open_con_sts_0_qin ();
metaIntf #(.STYPE(tcp_close_req_t)) close_con_cmd_0_qin ();

metaIntf #(.STYPE(tcp_listen_req_t)) open_port_cmd_0_qout ();
metaIntf #(.STYPE(tcp_listen_rsp_t)) open_port_sts_0_qout ();
metaIntf #(.STYPE(tcp_open_req_t)) open_con_cmd_0_qout ();
metaIntf #(.STYPE(tcp_open_rsp_t)) open_con_sts_0_qout ();
metaIntf #(.STYPE(tcp_close_req_t)) close_con_cmd_0_qout ();

`META_ASSIGN(open_port_cmd_0_qout, m_open_port_cmd_0)
`META_ASSIGN(open_con_cmd_0_qout, m_open_con_cmd_0)
`META_ASSIGN(close_con_cmd_0_qout, m_close_con_cmd_0)
`META_ASSIGN(s_open_con_sts_0, open_con_sts_0_qin)
`META_ASSIGN(s_open_port_sts_0, open_port_sts_0_qin)


meta_queue #(.DATA_BITS(16)) open_port_cmd_0_queue (.aclk(aclk), .aresetn(aresetn), .s_meta(open_port_cmd_0_qin), .m_meta(open_port_cmd_0_qout));
meta_queue #(.DATA_BITS(8)) open_port_sts_0_queue (.aclk(aclk), .aresetn(aresetn), .s_meta(open_port_sts_0_qin), .m_meta(open_port_sts_0_qout));
meta_queue #(.DATA_BITS(48)) open_con_cmd_0_queue (.aclk(aclk), .aresetn(aresetn), .s_meta(open_con_cmd_0_qin), .m_meta(open_con_cmd_0_qout));
meta_queue #(.DATA_BITS(72)) open_con_sts_0_queue (.aclk(aclk), .aresetn(aresetn), .s_meta(open_con_sts_0_qin), .m_meta(open_con_sts_0_qout));
meta_queue #(.DATA_BITS(16)) close_con_cmd_0_queue (.aclk(aclk), .aresetn(aresetn), .s_meta(close_con_cmd_0_qin), .m_meta(close_con_cmd_0_qout));

`endif

`ifdef EN_TCP_1
metaIntf #(.STYPE(tcp_listen_req_t)) open_port_cmd_1_qin ();
metaIntf #(.STYPE(tcp_listen_rsp_t)) open_port_sts_1_qin ();
metaIntf #(.STYPE(tcp_open_req_t)) open_con_cmd_1_qin ();
metaIntf #(.STYPE(tcp_open_rsp_t)) open_con_sts_1_qin ();
metaIntf #(.STYPE(tcp_close_req_t)) close_con_cmd_1_qin ();

metaIntf #(.STYPE(tcp_listen_req_t)) open_port_cmd_1_qout ();
metaIntf #(.STYPE(tcp_listen_rsp_t)) open_port_sts_1_qout ();
metaIntf #(.STYPE(tcp_open_req_t)) open_con_cmd_1_qout ();
metaIntf #(.STYPE(tcp_open_rsp_t)) open_con_sts_1_qout ();
metaIntf #(.STYPE(tcp_close_req_t)) close_con_cmd_1_qout ();

`META_ASSIGN(open_port_cmd_1_qout, m_open_port_cmd_1)
`META_ASSIGN(open_con_cmd_1_qout, m_open_con_cmd_1)
`META_ASSIGN(close_con_cmd_1_qout, m_close_con_cmd_1)
`META_ASSIGN(s_open_con_sts_1, open_con_sts_1_qin)
`META_ASSIGN(s_open_port_sts_1, open_port_sts_1_qin)


meta_queue #(.DATA_BITS(16)) open_port_cmd_1_queue (.aclk(aclk), .aresetn(aresetn), .s_meta(open_port_cmd_1_qin), .m_meta(open_port_cmd_1_qout));
meta_queue #(.DATA_BITS(8)) open_port_sts_1_queue (.aclk(aclk), .aresetn(aresetn), .s_meta(open_port_sts_1_qin), .m_meta(open_port_sts_1_qout));
meta_queue #(.DATA_BITS(48)) open_con_cmd_1_queue (.aclk(aclk), .aresetn(aresetn), .s_meta(open_con_cmd_1_qin), .m_meta(open_con_cmd_1_qout));
meta_queue #(.DATA_BITS(72)) open_con_sts_1_queue (.aclk(aclk), .aresetn(aresetn), .s_meta(open_con_sts_1_qin), .m_meta(open_con_sts_1_qout));
meta_queue #(.DATA_BITS(16)) close_con_cmd_1_queue (.aclk(aclk), .aresetn(aresetn), .s_meta(close_con_cmd_1_qin), .m_meta(close_con_cmd_1_qout));
`endif

// -- Def --------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------

// -- Register map ----------------------------------------------------------------------- 
// 0 (W1S|W1C) : Control 
localparam integer CTRL_REG                               = 0;
      localparam integer CTRL_START_RD        = 0;
      localparam integer CTRL_START_WR        = 1;
      localparam integer CTRL_SYNC_RD         = 2;
      localparam integer CTRL_SYNC_WR         = 3;
      localparam integer CTRL_STREAM_RD       = 4;
      localparam integer CTRL_STREAM_WR       = 5;
      localparam integer CTRL_CLR_STAT_RD     = 6;
      localparam integer CTRL_CLR_STAT_WR     = 7;
      localparam integer CTRL_CLR_IRQ_PENDING = 8;
      localparam integer CTRL_DEST_RD         = 9;
      localparam integer CTRL_DEST_WR         = 13;
      localparam integer CTRL_PID_RD          = 17;
      localparam integer CTRL_PID_WR          = 23;
// 1 (RW) : Virtual address read
localparam integer VADDR_RD_REG                           = 1;
// 2 (RW) : Length read
localparam integer LEN_RD_REG                             = 2;
// 3 (RW) : Virtual address write
localparam integer VADDR_WR_REG                           = 3;
// 4 (RW) : Length write
localparam integer LEN_WR_REG                             = 4;
// 5 (RO) : Virtual address miss
localparam integer VADDR_MISS_REG                         = 5;
// 6 (RO) : Length miss
localparam integer LEN_PID_MISS_REG                       = 6;
// 7,8 (W1S|W1C|R) : Datapath control set/clear
localparam integer CTRL_DP_REG_SET                        = 7;
localparam integer CTRL_DP_REG_CLR                        = 8;
      localparam integer CTRL_DP_DECOUPLE     = 0;
// 9 - 10 (RO) : Status 
localparam integer STAT_CMD_USED_RD_REG                   = 9;
localparam integer STAT_CMD_USED_WR_REG                   = 10;
// 11 - 17 (RO) : Status
localparam integer STAT_SENT_HOST_RD_REG                  = 11;
localparam integer STAT_SENT_HOST_WR_REG                  = 12;
localparam integer STAT_SENT_CARD_RD_REG                  = 13;
localparam integer STAT_SENT_CARD_WR_REG                  = 14;
localparam integer STAT_SENT_SYNC_RD_REG                  = 15;
localparam integer STAT_SENT_SYNC_WR_REG                  = 16;
localparam integer STAT_PFAULTS_REG                       = 17;
// 18 - 19 (RW) : Writeback
localparam integer WBACK_REG_0                            = 18;
localparam integer WBACK_REG_1                            = 19;
localparam integer WBACK_REG_2                            = 20;
localparam integer WBACK_REG_3                            = 21;
// RDMA 0
// 20, 21, 22, 23 (RW) : RDMA post
localparam integer RDMA_0_POST_REG                        = 32;
localparam integer RDMA_0_POST_REG_0                      = 33;
localparam integer RDMA_0_POST_REG_1                      = 34;
localparam integer RDMA_0_POST_REG_2                      = 35;
localparam integer RDMA_0_POST_REG_3                      = 36;
localparam integer RDMA_0_POST_REG_4                      = 37;
localparam integer RDMA_0_POST_REG_5                      = 38;
localparam integer RDMA_0_POST_REG_6                      = 39;
localparam integer RDMA_0_POST_REG_7                      = 40;
// 24, 25 (RO) : RDMA status
localparam integer RDMA_0_STAT_CMD_USED_REG               = 41;
localparam integer RDMA_0_STAT_POSTED_REG                 = 42;
localparam integer RDMA_0_CMPLT_REG                       = 43;
    localparam integer RDMA_CMPLT_PID_OFFS      = 16;
    localparam integer RDMA_CMPLT_SSN_OFFS      = 32;
// RDMA 1
// 26, 27, 28, 29 (RW) : RDMA post
localparam integer RDMA_1_POST_REG                        = 48;
localparam integer RDMA_1_POST_REG_0                      = 49;
localparam integer RDMA_1_POST_REG_1                      = 50;
localparam integer RDMA_1_POST_REG_2                      = 51;
localparam integer RDMA_1_POST_REG_3                      = 52;
localparam integer RDMA_1_POST_REG_4                      = 53;
localparam integer RDMA_1_POST_REG_5                      = 54;
localparam integer RDMA_1_POST_REG_6                      = 55;
localparam integer RDMA_1_POST_REG_7                      = 56;
// 23 (RO) : RDMA status
localparam integer RDMA_1_STAT_CMD_USED_REG               = 57;
localparam integer RDMA_1_STAT_POSTED_REG                 = 58;
localparam integer RDMA_1_CMPLT_REG                       = 59;

// 64 (RO) : Status DMA completion
localparam integer STAT_DMA_REG                           = 2**PID_BITS;
//
// TCP 0
localparam integer TCP_0_OPEN_CON_REG                       = 65;
localparam integer TCP_0_OPEN_PORT_REG                      = 66;
localparam integer TCP_0_OPEN_CON_STS_REG                   = 67;
localparam integer TCP_0_OPEN_PORT_STS_REG                  = 68;
localparam integer TCP_0_CLOSE_CON_REG                      = 69;

// TCP 1
localparam integer TCP_1_OPEN_CON_REG                       = 81;
localparam integer TCP_1_OPEN_PORT_REG                      = 82;
localparam integer TCP_1_OPEN_CON_STS_REG                   = 83;
localparam integer TCP_1_OPEN_PORT_STS_REG                  = 84;
localparam integer TCP_1_CLOSE_CON_REG                      = 85;

// ---------------------------------------------------------------------------------------- 
// Write process 
// ----------------------------------------------------------------------------------------
assign slv_reg_wren = axi_wready && s_axi_ctrl.wvalid && axi_awready && s_axi_ctrl.awvalid;

always_ff @(posedge aclk) begin
  if ( aresetn == 1'b0 ) begin
    slv_reg <= 'X;
    
    slv_reg[CTRL_REG][CTRL_BYTES*8-1:0] <= 0;
    slv_reg[CTRL_DP_REG_SET][CTRL_BYTES*8-1:0] <= 0;

    irq_pending <= 1'b0; 

`ifdef EN_RDMA_0
        rdma_0_post <= 1'b0;
`endif

`ifdef EN_RDMA_1
        rdma_1_post <= 1'b0;
`endif

`ifdef EN_TCP_0
        open_port_cmd_0_qin.valid <= 1'b0;
        open_con_cmd_0_qin.valid <= 1'b0;
        close_con_cmd_0_qin.valid <= 1'b0;
`endif

`ifdef EN_TCP_1
        open_port_cmd_1_qin.valid <= 1'b0;
        open_con_cmd_1_qin.valid <= 1'b0;
        close_con_cmd_1_qin.valid <= 1'b0;
`endif
  end
  else begin
    slv_reg[CTRL_REG][CTRL_BYTES*8-1:0] <= 0; // Control

`ifdef EN_RDMA_0
        rdma_0_post <= 1'b0;
`endif

`ifdef EN_RDMA_1
        rdma_1_post <= 1'b0;
`endif

`ifdef EN_TCP_0
        open_port_cmd_0_qin.valid <= 1'b0;
        open_con_cmd_0_qin.valid <= 1'b0;
        close_con_cmd_0_qin.valid <= 1'b0;
`endif

`ifdef EN_TCP_1
        open_port_cmd_1_qin.valid <= 1'b0;
        open_con_cmd_1_qin.valid <= 1'b0;
        close_con_cmd_1_qin.valid <= 1'b0;
`endif

    // Page fault
    if(s_pfault_rd.valid || s_pfault_wr.valid) begin
      irq_pending <= 1'b1;
      slv_reg[VADDR_MISS_REG] <= s_pfault_rd.valid ? s_pfault_rd.data[0+:VADDR_BITS] : s_pfault_wr.data[0+:VADDR_BITS]; // miss length
      slv_reg[LEN_PID_MISS_REG][0+:LEN_BITS]   <= s_pfault_rd.valid ? s_pfault_rd.data[VADDR_BITS+:LEN_BITS] : s_pfault_wr.data[VADDR_BITS+:LEN_BITS]; // miss length
      slv_reg[LEN_PID_MISS_REG][32+:PID_BITS]   <= s_pfault_rd.valid ? s_pfault_rd.data[VADDR_BITS+LEN_BITS+:PID_BITS] : s_pfault_wr.data[VADDR_BITS+LEN_BITS+:PID_BITS]; // miss pid
    end
    if(slv_reg[CTRL_REG][CTRL_CLR_IRQ_PENDING]) begin
      irq_pending <= 1'b0;
    end

    // Slave write
    if(slv_reg_wren) begin
      case (axi_awaddr[ADDR_LSB+:ADDR_MSB])
        CTRL_REG: // Control
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[CTRL_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        VADDR_RD_REG: // Virtual address read
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[VADDR_RD_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        LEN_RD_REG: // Length read
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[LEN_RD_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        VADDR_WR_REG: // Virtual address write
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[VADDR_WR_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        LEN_WR_REG: // Length write
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[LEN_WR_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        CTRL_DP_REG_SET: // Datapath control set
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[CTRL_DP_REG_SET][(i*8)+:8] <= slv_reg[CTRL_DP_REG_SET][(i*8)+:8] | s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        CTRL_DP_REG_CLR: // Datapath control clear
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[CTRL_DP_REG_SET][(i*8)+:8] <= slv_reg[CTRL_DP_REG_SET][(i*8)+:8] & ~s_axi_ctrl.wdata[(i*8)+:8];
            end
          end

`ifdef EN_WB
        WBACK_REG_0: // Writeback read
          for (int i = 0; i <  AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[WBACK_REG_0][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        WBACK_REG_1: // Writeback read
          for (int i = 0; i <  AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[WBACK_REG_1][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        WBACK_REG_2: // Writeback read
          for (int i = 0; i <  AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[WBACK_REG_2][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        WBACK_REG_3: // Writeback read
          for (int i = 0; i <  AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[WBACK_REG_3][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
`endif

`ifdef EN_RDMA_0
        RDMA_0_POST_REG: begin // Post ctrl
          rdma_0_post <= s_axi_ctrl.wdata[0];
          for (int i = 0; i < 1; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[RDMA_0_POST_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        end
        RDMA_0_POST_REG_0: // Post
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[RDMA_0_POST_REG_0][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        RDMA_0_POST_REG_1: // Post
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[RDMA_0_POST_REG_1][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        RDMA_0_POST_REG_2: // Post final
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[RDMA_0_POST_REG_2][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        RDMA_0_POST_REG_3: // Post final
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[RDMA_0_POST_REG_3][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        RDMA_0_POST_REG_4: // Post final
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[RDMA_0_POST_REG_4][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        RDMA_0_POST_REG_5: // Post final
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[RDMA_0_POST_REG_5][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        RDMA_0_POST_REG_6: // Post final
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[RDMA_0_POST_REG_6][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        RDMA_0_POST_REG_7: // Post final
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[RDMA_0_POST_REG_7][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
`endif

`ifdef EN_RDMA_1
        RDMA_1_POST_REG: begin // Post ctrl
          rdma_1_post <= s_axi_ctrl.wdata[0];
          for (int i = 0; i < 1; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[RDMA_1_POST_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        end
        RDMA_1_POST_REG_0: // Post
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[RDMA_1_POST_REG_0][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        RDMA_1_POST_REG_1: // Post
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[RDMA_1_POST_REG_1][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        RDMA_1_POST_REG_2: // Post final
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[RDMA_1_POST_REG_2][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        RDMA_1_POST_REG_3: // Post final
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[RDMA_1_POST_REG_3][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        RDMA_1_POST_REG_4: // Post final
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[RDMA_1_POST_REG_4][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        RDMA_1_POST_REG_5: // Post final
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[RDMA_1_POST_REG_5][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        RDMA_1_POST_REG_6: // Post final
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[RDMA_1_POST_REG_6][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        RDMA_1_POST_REG_7: // Post final
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[RDMA_1_POST_REG_7][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
`endif

`ifdef EN_TCP_0 
        TCP_0_OPEN_CON_REG : begin // open_con
            for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
                if(s_axi_ctrl.wstrb[i]) begin
                slv_reg[2][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
                end
            end
            if (s_axi_ctrl.wstrb != 0) begin
                open_con_cmd_0_qin.valid <= 1'b1;
            end
        end
        TCP_0_OPEN_PORT_REG : begin // open_port
            for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
                if(s_axi_ctrl.wstrb[i]) begin
                slv_reg[3][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
                end
            end
            if (s_axi_ctrl.wstrb != 0) begin
                open_port_cmd_0_qin.valid <= 1'b1;
            end
        end
        TCP_0_CLOSE_CON_REG : begin // close_con
            for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
                if(s_axi_ctrl.wstrb[i]) begin
                slv_reg[4][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
                end
            end
            if (s_axi_ctrl.wstrb != 0) begin
                close_con_cmd_0_qin.valid <= 1'b1;
            end
        end
`endif

`ifdef EN_TCP_1 
        TCP_1_OPEN_CON_REG : begin // open_con
            for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
                if(s_axi_ctrl.wstrb[i]) begin
                slv_reg[2][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
                end
            end
            if (s_axi_ctrl.wstrb != 0) begin
                open_con_cmd_1_qin.valid <= 1'b1;
            end
        end
        TCP_1_OPEN_PORT_REG : begin // open_port
            for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
                if(s_axi_ctrl.wstrb[i]) begin
                slv_reg[3][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
                end
            end
            if (s_axi_ctrl.wstrb != 0) begin
                open_port_cmd_1_qin.valid <= 1'b1;
            end
        end
        TCP_1_CLOSE_CON_REG : begin // close_con
            for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
                if(s_axi_ctrl.wstrb[i]) begin
                slv_reg[4][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
                end
            end
            if (s_axi_ctrl.wstrb != 0) begin
                close_con_cmd_1_qin.valid <= 1'b1;
            end
        end
`endif
        default : ;
      endcase
    end

    // Status counters
    slv_reg[STAT_SENT_HOST_RD_REG][31:0] <= slv_reg[STAT_SENT_HOST_RD_REG][31:0] + rd_sent_host;
    slv_reg[STAT_SENT_HOST_WR_REG][31:0] <= slv_reg[STAT_SENT_HOST_WR_REG][31:0] + wr_sent_host;
    slv_reg[STAT_SENT_CARD_RD_REG][31:0] <= slv_reg[STAT_SENT_CARD_RD_REG][31:0] + rd_sent_card;
    slv_reg[STAT_SENT_CARD_WR_REG][31:0] <= slv_reg[STAT_SENT_CARD_WR_REG][31:0] + wr_sent_card;
    slv_reg[STAT_SENT_SYNC_RD_REG][31:0] <= slv_reg[STAT_SENT_SYNC_RD_REG][31:0] + rd_sent_sync;
    slv_reg[STAT_SENT_SYNC_WR_REG][31:0] <= slv_reg[STAT_SENT_SYNC_WR_REG][31:0] + wr_sent_sync;
    slv_reg[STAT_PFAULTS_REG][31:0] <= slv_reg[STAT_PFAULTS_REG] + (s_pfault_rd.valid || s_pfault_wr.valid);

`ifdef EN_RDMA_0
    slv_reg[RDMA_0_STAT_POSTED_REG][31:0] <= slv_reg[RDMA_0_STAT_POSTED_REG][31:0] + rdma_0_post;
`endif

`ifdef EN_RDMA_1
    slv_reg[RDMA_1_STAT_POSTED_REG][31:0] <= slv_reg[RDMA_1_STAT_POSTED_REG][31:0] + rdma_1_post;
`endif

  end
end    

// Output TCP
`ifdef EN_TCP_0
always_comb begin
	open_con_cmd_0_qin.data = slv_reg[TCP_0_OPEN_CON_REG];
	open_port_cmd_0_qin.data = slv_reg[TCP_0_OPEN_PORT_REG];
	close_con_cmd_0_qin.data = slv_reg[TCP_0_CLOSE_CON_REG];
end
`endif
`ifdef EN_TCP_1
always_comb begin
	open_con_cmd_1_qin.data = slv_reg[TCP_1_OPEN_CON_REG];
	open_port_cmd_1_qin.data = slv_reg[TCP_1_OPEN_PORT_REG];
	close_con_cmd_1_qin.data = slv_reg[TCP_1_CLOSE_CON_REG];
end
`endif

// ---------------------------------------------------------------------------------------- 
// Read process 
// ----------------------------------------------------------------------------------------
assign slv_reg_rden = axi_arready & s_axi_ctrl.arvalid & ~axi_rvalid;

always_ff @(posedge aclk) begin
  if( aresetn == 1'b0 ) begin
    axi_rdata <= 'X;
    axi_mux <= 'X;

`ifdef EN_TCP_0
    open_con_sts_0_qout.ready <= 1'b0;
    open_port_sts_0_qout.ready <= 1'b0;
`endif

`ifdef EN_TCP_1
    open_con_sts_1_qout.ready <= 1'b0;
    open_port_sts_1_qout.ready <= 1'b0;
`endif
  end
  else begin

`ifdef EN_TCP_0
    open_con_sts_0_qout.ready <= 1'b0;
    open_port_sts_0_qout.ready <= 1'b0;
`endif

`ifdef EN_TCP_1
    open_con_sts_1_qout.ready <= 1'b0;
    open_port_sts_1_qout.ready <= 1'b0;
`endif

    if(slv_reg_rden) begin
      axi_rdata <= 0;
      axi_mux <= 0;

      case (axi_araddr[ADDR_LSB+:ADDR_MSB]) inside
        VADDR_RD_REG: // Virtual address read
          axi_rdata[VADDR_BITS-1:0] <= slv_reg[VADDR_RD_REG][VADDR_BITS-1:0];
        LEN_RD_REG: // Length read
          axi_rdata[LEN_BITS-1:0] <= slv_reg[LEN_RD_REG][LEN_BITS-1:0];
        VADDR_WR_REG: // Virtual address write
          axi_rdata[VADDR_BITS-1:0] <= slv_reg[VADDR_WR_REG][VADDR_BITS-1:0];
        LEN_WR_REG: // Length write
          axi_rdata[LEN_BITS-1:0] <= slv_reg[LEN_WR_REG][LEN_BITS-1:0];
        VADDR_MISS_REG: // Virtual address miss
          axi_rdata[VADDR_BITS-1:0] <= slv_reg[VADDR_MISS_REG][VADDR_BITS-1:0];
        LEN_PID_MISS_REG: // Length miss
          axi_rdata[PID_BITS+LEN_BITS-1:0] <= slv_reg[LEN_PID_MISS_REG][PID_BITS+LEN_BITS-1:0];
        CTRL_DP_REG_SET: // Datapath
          axi_rdata[15:0] <= slv_reg[CTRL_DP_REG_SET][15:0];
        CTRL_DP_REG_CLR: // Datapath
          axi_rdata[15:0] <= slv_reg[CTRL_DP_REG_SET][15:0];
        STAT_CMD_USED_RD_REG: // Status queues used read
          axi_rdata[15:0] <= rd_queue_used[15:0];
        STAT_CMD_USED_WR_REG: // Status queues used write
          axi_rdata[15:0] <= wr_queue_used[15:0];
        STAT_SENT_HOST_RD_REG: // Status sent read
          axi_rdata[31:0] <= slv_reg[STAT_SENT_HOST_RD_REG][31:0];
        STAT_SENT_HOST_WR_REG: // Status sent write
          axi_rdata[31:0] <= slv_reg[STAT_SENT_HOST_WR_REG][31:0];
        STAT_SENT_CARD_RD_REG: // Status sent read
          axi_rdata[31:0] <= slv_reg[STAT_SENT_CARD_RD_REG][31:0];
        STAT_SENT_CARD_WR_REG: // Status sent write
          axi_rdata[31:0] <= slv_reg[STAT_SENT_CARD_WR_REG][31:0];
        STAT_SENT_SYNC_RD_REG: // Status sent read
          axi_rdata[31:0] <= slv_reg[STAT_SENT_SYNC_RD_REG][31:0];
        STAT_SENT_SYNC_WR_REG: // Status sent write
          axi_rdata[31:0] <= slv_reg[STAT_SENT_SYNC_WR_REG][31:0];
        STAT_PFAULTS_REG: // Status page faults
          axi_rdata[31:0] <= slv_reg[STAT_PFAULTS_REG][31:0];

`ifdef EN_WB
        WBACK_REG_0: // Writeback read
          axi_rdata <= slv_reg[WBACK_REG_0];
        WBACK_REG_1: // Writeback read
          axi_rdata <= slv_reg[WBACK_REG_1];
        WBACK_REG_2: // Writeback read
          axi_rdata <= slv_reg[WBACK_REG_2];
        WBACK_REG_3: // Writeback read
          axi_rdata <= slv_reg[WBACK_REG_3];
`endif

`ifdef EN_RDMA_0
        RDMA_0_POST_REG_0: // Post
          axi_rdata <= slv_reg[RDMA_0_POST_REG_0];
        RDMA_0_POST_REG_1: // Post
          axi_rdata <= slv_reg[RDMA_0_POST_REG_1];
        RDMA_0_POST_REG_2: // Post final
          axi_rdata <= slv_reg[RDMA_0_POST_REG_2];
        RDMA_0_POST_REG_3: // Post final
          axi_rdata <= slv_reg[RDMA_0_POST_REG_3];
        RDMA_0_POST_REG_4: // Post final
          axi_rdata <= slv_reg[RDMA_0_POST_REG_4];
        RDMA_0_POST_REG_5: // Post final
          axi_rdata <= slv_reg[RDMA_0_POST_REG_5];
        RDMA_0_POST_REG_6: // Post final
          axi_rdata <= slv_reg[RDMA_0_POST_REG_6];
        RDMA_0_POST_REG_7: // Post final
          axi_rdata <= slv_reg[RDMA_0_POST_REG_7];
        RDMA_0_STAT_CMD_USED_REG: // Status queue used
          axi_rdata[31:0] <= rdma_0_queue_used[31:0];
        RDMA_0_STAT_POSTED_REG: // Posts
          axi_rdata[31:0] <= slv_reg[RDMA_0_STAT_POSTED_REG][31:0];
        RDMA_0_CMPLT_REG: begin
          axi_rdata[0] <= cmplt_que_rdma_0_out.data.valid; 
          axi_rdata[RDMA_CMPLT_PID_OFFS+:PID_BITS] <= cmplt_que_rdma_0_out.data.pid;
          axi_rdata[RDMA_CMPLT_SSN_OFFS+:RDMA_MSN_BITS] <= cmplt_que_rdma_0_out.ssn;
        end
`endif

`ifdef EN_RDMA_1
        RDMA_1_POST_REG_0: // Post
          axi_rdata <= slv_reg[RDMA_1_POST_REG_0];
        RDMA_1_POST_REG_1: // Post
          axi_rdata <= slv_reg[RDMA_1_POST_REG_1];
        RDMA_1_POST_REG_2: // Post final
          axi_rdata <= slv_reg[RDMA_1_POST_REG_2];
        RDMA_1_POST_REG_3: // Post final
          axi_rdata <= slv_reg[RDMA_1_POST_REG_3];
        RDMA_1_POST_REG_4: // Post final
          axi_rdata <= slv_reg[RDMA_1_POST_REG_4];
        RDMA_1_POST_REG_5: // Post final
          axi_rdata <= slv_reg[RDMA_1_POST_REG_5];
        RDMA_1_POST_REG_6: // Post final
          axi_rdata <= slv_reg[RDMA_1_POST_REG_6];
        RDMA_1_POST_REG_7: // Post final
          axi_rdata <= slv_reg[RDMA_1_POST_REG_7];
        RDMA_1_STAT_CMD_USED_REG: // Status queue used
          axi_rdata[31:0] <= rdma_1_queue_used[31:0];
        RDMA_1_STAT_POSTED_REG: // Posts
          axi_rdata[31:0] <= slv_reg[RDMA_1_STAT_POSTED_REG][31:0];
        RDMA_1_CMPLT_REG: begin
          axi_rdata[0] <= cmplt_que_rdma_1_out.data.valid; 
          axi_rdata[RDMA_CMPLT_PID_OFFS+:PID_BITS] <= cmplt_que_rdma_1_out.data.pid;
          axi_rdata[RDMA_CMPLT_SSN_OFFS+:RDMA_MSN_BITS] <= cmplt_que_rdma_1_out.ssn;
        end
`endif

        [STAT_DMA_REG:STAT_DMA_REG+(2**PID_BITS)-1]: begin
          axi_mux <= 1;
        end

        [STAT_DMA_REG+(2**PID_BITS):STAT_DMA_REG+2*(2**PID_BITS)-1]: begin
          axi_mux <= 2;
        end

`ifdef EN_TCP_0
        [TCP_0_OPEN_CON_STS_REG:TCP_0_OPEN_CON_STS_REG] : begin // open_status
            if (open_con_sts_0_qout.valid) begin
                axi_rdata[14:0] <= open_con_sts_0_qout.data[14:0]; //session
                axi_rdata[15:15] <= open_con_sts_0_qout.data[16]; //success
                axi_rdata[47:16] <= open_con_sts_0_qout.data[55:24]; //ip
                axi_rdata[63:48] <= open_con_sts_0_qout.data[71:56]; //port  
                open_con_sts_0_qout.ready <= 1'b1;
            end
            else begin
                axi_rdata <= '0;
            end
        end
        [TCP_0_OPEN_PORT_STS_REG:TCP_0_OPEN_PORT_STS_REG] : begin // port_status
            if (open_port_sts_0_qout.valid) begin
                axi_rdata <= open_port_sts_0_qout.data;
                open_port_sts_0_qout.ready <= 1'b1;
            end
            else begin
                axi_rdata <= '0;
            end
        end
`endif

`ifdef EN_TCP_1
        [TCP_1_OPEN_CON_STS_REG:TCP_1_OPEN_CON_STS_REG] : begin // open_status
            if (open_con_sts_1_qout.valid) begin
                axi_rdata[14:0] <= open_con_sts_1_qout.data[14:0]; //session
                axi_rdata[15:15] <= open_con_sts_1_qout.data[16]; //success
                axi_rdata[47:16] <= open_con_sts_1_qout.data[55:24]; //ip
                axi_rdata[63:48] <= open_con_sts_1_qout.data[71:56]; //port  
                open_con_sts_1_qout.ready <= 1'b1;
            end
            else begin
                axi_rdata <= '0;
            end
        end
        [TCP_1_OPEN_PORT_STS_REG:TCP_1_OPEN_PORT_STS_REG] : begin // port_status
            if (open_port_sts_1_qout.valid) begin
                axi_rdata <= open_port_sts_1_qout.data;
                open_port_sts_1_qout.ready <= 1'b1;
            end
            else begin
                axi_rdata <= '0;
            end
        end
`endif

        default: ;
      endcase
    end
  end 
end

assign axi_rdata_bram[0] = {b_data_out_wr, b_data_out_rd};
`ifdef EN_RDMA_0
assign axi_rdata_bram[1][0+:32] = b_data_out_rdma_0;
`else 
assign axi_rdata_bram[1][0+:32] = 0;
`endif
`ifdef EN_RDMA_1
assign axi_rdata_bram[1][32+:32] = b_data_out_rdma_1;
`else 
assign axi_rdata_bram[1][32+:32] = 0;
`endif

// ---------------------------------------------------------------------------------------- 
// CPID 
// ----------------------------------------------------------------------------------------

// RD
assign rd_clear = slv_reg[CTRL_REG][CTRL_CLR_STAT_RD];
assign rd_clear_addr = slv_reg[CTRL_REG][CTRL_PID_RD+:PID_BITS];

always_comb begin
    meta_done_rd.valid = 1'b0;
    meta_done_rd.data = 0;

`ifdef EN_STRM
    meta_host_done_rd_out.ready = 1'b0;
`endif

`ifdef EN_MEM
    meta_card_done_rd_out.ready = 1'b0;
    meta_sync_done_rd_out.ready = 1'b0;
`endif

`ifdef EN_STRM
    if(meta_host_done_rd_out.valid) begin
        meta_done_rd.valid = 1'b1;
        meta_done_rd.data = meta_host_done_rd_out.data;
        meta_host_done_rd_out.ready = meta_done_rd.ready;
    end
    `ifdef EN_MEM
        else
    `endif
`endif

`ifdef EN_MEM
    if(meta_card_done_rd_out.valid) begin
        meta_done_rd.valid = 1'b1;
        meta_done_rd.data = meta_card_done_rd_out.data;
        meta_card_done_rd_out.ready = meta_done_rd.ready;
    end
    else if(meta_sync_done_rd_out.valid) begin
        meta_done_rd.valid = 1'b1;
        meta_done_rd.data = meta_sync_done_rd_out.data;
        meta_sync_done_rd_out.ready = meta_done_rd.ready;
    end
`endif 

end

// queue in
`ifdef EN_STRM 
queue_meta #(.QDEPTH(N_OUTSTANDING)) inst_meta_host_done_rd (.aclk(aclk), .aresetn(aresetn), .s_meta(s_host_done_rd), .m_meta(meta_host_done_rd_out));
`endif

`ifdef EN_MEM
queue_meta #(.QDEPTH(N_OUTSTANDING)) inst_meta_card_done_rd (.aclk(aclk), .aresetn(aresetn), .s_meta(s_card_done_rd), .m_meta(meta_card_done_rd_out));
queue_meta #(.QDEPTH(N_OUTSTANDING)) inst_meta_sync_done_rd (.aclk(aclk), .aresetn(aresetn), .s_meta(s_sync_done_rd), .m_meta(meta_sync_done_rd_out));
`endif

always_ff @(posedge aclk) begin
    if(aresetn == 1'b0) begin
        rd_C <= 1'b0; 
    end
    else begin
        rd_C <= rd_C ? 1'b0 : (meta_done_rd.valid ? 1'b1 : rd_C);
    end
end

assign meta_done_rd.ready = (rd_C & meta_done_rd.valid);

`ifdef EN_BPSS
assign m_bpss_rd_done.valid = (rd_C & meta_done_rd.valid);
assign m_bpss_rd_done.data = meta_done_rd.data;
`endif

assign a_we_rd = (rd_clear || rd_C) ? ~0 : 0;
assign a_addr_rd = rd_clear ? rd_clear_addr : meta_done_rd.data.pid;
assign a_data_in_rd = rd_clear ? 0 : a_data_out_rd + 1'b1;
assign b_addr_rd = axi_araddr[ADDR_LSB+:PID_BITS];

ram_tp_nc #(
    .ADDR_BITS(PID_BITS),
    .DATA_BITS(32)
) inst_rd_stat (
    .clk(aclk),
    .a_en(1'b1),
    .a_we(a_we_rd),
    .a_addr(a_addr_rd),
    .b_en(1'b1),
    .b_addr(b_addr_rd),
    .a_data_in(a_data_in_rd),
    .a_data_out(a_data_out_rd),
    .b_data_out(b_data_out_rd)
);

// WR
assign wr_clear = slv_reg[CTRL_REG][CTRL_CLR_STAT_WR];
assign wr_clear_addr = slv_reg[CTRL_REG][CTRL_PID_WR+:PID_BITS];

always_comb begin
    meta_done_wr.valid = 1'b0;
    meta_done_wr.data = 0;

`ifdef EN_STRM
    meta_host_done_wr_out.ready = 1'b0;
`endif

`ifdef EN_MEM
    meta_card_done_wr_out.ready = 1'b0;
    meta_sync_done_wr_out.ready = 1'b0;
`endif

`ifdef EN_STRM
    if(meta_host_done_wr_out.valid) begin
        meta_done_wr.valid = 1'b1;
        meta_done_wr.data = meta_host_done_wr_out.data;
        meta_host_done_wr_out.ready = meta_done_wr.ready;
    end
    `ifdef EN_MEM
        else
    `endif
`endif

`ifdef EN_MEM
    if(meta_card_done_wr_out.valid) begin
        meta_done_wr.valid = 1'b1;
        meta_done_wr.data = meta_card_done_wr_out.data;
        meta_card_done_wr_out.ready = meta_done_wr.ready;
    end
    else if(meta_sync_done_wr_out.valid) begin
        meta_done_wr.valid = 1'b1;
        meta_done_wr.data = meta_sync_done_wr_out.data;
        meta_sync_done_wr_out.ready = meta_done_wr.ready;
    end
`endif 

end

// queue in
`ifdef EN_STRM 
queue_meta #(.QDEPTH(N_OUTSTANDING)) inst_meta_host_done_wr (.aclk(aclk), .aresetn(aresetn), .s_meta(s_host_done_wr), .m_meta(meta_host_done_wr_out));
`endif

`ifdef EN_MEM
queue_meta #(.QDEPTH(N_OUTSTANDING)) inst_meta_cawr_done_wr (.aclk(aclk), .aresetn(aresetn), .s_meta(s_card_done_wr), .m_meta(meta_card_done_wr_out));
queue_meta #(.QDEPTH(N_OUTSTANDING)) inst_meta_sync_done_wr (.aclk(aclk), .aresetn(aresetn), .s_meta(s_sync_done_wr), .m_meta(meta_sync_done_wr_out));
`endif

always_ff @(posedge aclk) begin
    if(aresetn == 1'b0) begin
        wr_C <= 1'b0; 
    end
    else begin
        wr_C <= wr_C ? 1'b0 : (meta_done_wr.valid ? 1'b1 : wr_C);
    end
end

assign meta_done_wr.ready = (wr_C & meta_done_wr.valid);

`ifdef EN_BPSS
assign m_bpss_wr_done.valid = (wr_C & meta_done_wr.valid);
assign m_bpss_wr_done.data = meta_done_wr.data;
`endif

assign a_we_wr = (wr_clear || wr_C) ? ~0 : 0;
assign a_addr_wr = wr_clear ? wr_clear_addr : meta_done_wr.data.pid;
assign a_data_in_wr = wr_clear ? 0 : a_data_out_wr + 1'b1;
assign b_addr_wr = axi_araddr[ADDR_LSB+:PID_BITS];

ram_tp_nc #(
    .ADDR_BITS(PID_BITS),
    .DATA_BITS(32)
) inst_wr_stat (
    .clk(aclk),
    .a_en(1'b1),
    .a_we(a_we_wr),
    .a_addr(a_addr_wr),
    .b_en(1'b1),
    .b_addr(b_addr_wr),
    .a_data_in(a_data_in_wr),
    .a_data_out(a_data_out_wr),
    .b_data_out(b_data_out_wr)
);

// ---------------------------------------------------------------------------------------- 
// Output
// ----------------------------------------------------------------------------------------

// Status
`ifdef EN_STRM 
    `ifdef EN_MEM
        assign rd_sent_host = (m_rd_req.valid && m_rd_req.ready && m_rd_req.data.ctl) && m_rd_req.data.stream;
        assign wr_sent_host = (m_wr_req.valid && m_wr_req.ready && m_wr_req.data.ctl) && m_wr_req.data.stream;
        assign rd_sent_card = (m_rd_req.valid && m_rd_req.ready && m_rd_req.data.ctl) && !m_rd_req.data.stream && !m_rd_req.data.sync;
        assign wr_sent_card = (m_wr_req.valid && m_wr_req.ready && m_wr_req.data.ctl) && !m_wr_req.data.stream && !m_wr_req.data.sync;
        assign rd_sent_sync = (m_rd_req.valid && m_rd_req.ready && m_rd_req.data.ctl) && !m_rd_req.data.stream && m_rd_req.data.sync;
        assign wr_sent_sync = (m_wr_req.valid && m_wr_req.ready && m_wr_req.data.ctl) && !m_wr_req.data.stream && m_wr_req.data.sync;
    `else
        assign rd_sent_host = (m_rd_req.valid && m_rd_req.ready && m_rd_req.data.ctl);
        assign wr_sent_host = (m_wr_req.valid && m_wr_req.ready && m_wr_req.data.ctl);
        assign rd_sent_card = 1'b0;
        assign wr_sent_card = 1'b0;
        assign rd_sent_sync = 1'b0;
        assign wr_sent_sync = 1'b0;
    `endif
`elsif EN_MEM
        assign rd_sent_host = 1'b0;
        assign wr_sent_host = 1'b0;
        assign rd_sent_card = (m_rd_req.valid && m_rd_req.ready && m_rd_req.data.ctl) && !m_rd_req.data.sync;
        assign wr_sent_card = (m_wr_req.valid && m_wr_req.ready && m_wr_req.data.ctl) && !m_wr_req.data.sync;
        assign rd_sent_sync = (m_rd_req.valid && m_rd_req.ready && m_rd_req.data.ctl) && m_rd_req.data.sync;
        assign wr_sent_sync = (m_wr_req.valid && m_wr_req.ready && m_wr_req.data.ctl) && m_wr_req.data.sync;
`endif

// Page fault
assign s_pfault_rd.ready = 1'b1;
assign s_pfault_wr.ready = 1'b1;
assign restart_rd = slv_reg[CTRL_REG][CTRL_CLR_IRQ_PENDING];
assign restart_wr = slv_reg[CTRL_REG][CTRL_CLR_IRQ_PENDING];
assign pf_irq = irq_pending;

// Decoupling
assign decouple = slv_reg[CTRL_DP_REG_SET][CTRL_DP_DECOUPLE];

metaIntf #(.STYPE(req_t)) rd_req_cnfg();
metaIntf #(.STYPE(req_t)) wr_req_cnfg();
metaIntf #(.STYPE(req_t)) rd_req_host();
metaIntf #(.STYPE(req_t)) wr_req_host();

// Assign 
assign rd_req_cnfg.data.vaddr = slv_reg[VADDR_RD_REG][VADDR_BITS-1:0];
assign rd_req_cnfg.data.len = slv_reg[LEN_RD_REG][LEN_BITS-1:0];
assign rd_req_cnfg.data.sync = slv_reg[CTRL_REG][CTRL_SYNC_RD];
assign rd_req_cnfg.data.ctl = 1'b1;
assign rd_req_cnfg.data.stream = slv_reg[CTRL_REG][CTRL_STREAM_RD];
assign rd_req_cnfg.data.dest = slv_reg[CTRL_REG][CTRL_DEST_RD+:DEST_BITS];
assign rd_req_cnfg.data.pid = slv_reg[CTRL_REG][CTRL_PID_RD+:PID_BITS];
assign rd_req_cnfg.data.vfid = ID_REG;
assign rd_req_cnfg.data.host = 1'b1;
assign rd_req_cnfg.data.rsrvd = 0;
assign rd_req_cnfg.valid = slv_reg[CTRL_REG][CTRL_START_RD];

assign wr_req_cnfg.data.vaddr = slv_reg[VADDR_WR_REG][VADDR_BITS-1:0];
assign wr_req_cnfg.data.len = slv_reg[LEN_WR_REG][LEN_BITS-1:0];
assign wr_req_cnfg.data.sync = slv_reg[CTRL_REG][CTRL_SYNC_WR];
assign wr_req_cnfg.data.ctl = 1'b1;
assign wr_req_cnfg.data.stream = slv_reg[CTRL_REG][CTRL_STREAM_WR];
assign wr_req_cnfg.data.dest = slv_reg[CTRL_REG][CTRL_DEST_WR+:DEST_BITS];
assign wr_req_cnfg.data.pid = slv_reg[CTRL_REG][CTRL_PID_WR+:PID_BITS];
assign wr_req_cnfg.data.vfid = ID_REG;
assign wr_req_cnfg.data.host = 1'b1;
assign wr_req_cnfg.data.rsrvd = 0;
assign wr_req_cnfg.valid = slv_reg[CTRL_REG][CTRL_START_WR];

// Command queues
axis_data_fifo_req_96_used inst_cmd_queue_rd (
  .s_axis_aresetn(aresetn),
  .s_axis_aclk(aclk),
  .s_axis_tvalid(rd_req_cnfg.valid),
  .s_axis_tready(rd_req_cnfg.ready),
  .s_axis_tdata(rd_req_cnfg.data),
  .m_axis_tvalid(rd_req_host.valid),
  .m_axis_tready(rd_req_host.ready),
  .m_axis_tdata(rd_req_host.data),
  .axis_wr_data_count(rd_queue_used)
);

axis_data_fifo_req_96_used inst_cmd_queue_wr (
  .s_axis_aresetn(aresetn),
  .s_axis_aclk(aclk),
  .s_axis_tvalid(wr_req_cnfg.valid),
  .s_axis_tready(wr_req_cnfg.ready),
  .s_axis_tdata(wr_req_cnfg.data),
  .m_axis_tvalid(wr_req_host.valid),
  .m_axis_tready(wr_req_host.ready),
  .m_axis_tdata(wr_req_host.data),
  .axis_wr_data_count(wr_queue_used)
);

metaIntf #(.STYPE(req_t)) m_rd_req_int ();
metaIntf #(.STYPE(req_t)) m_wr_req_int ();

`ifdef EN_BPSS
metaIntf #(.STYPE(req_t)) bpss_rd_req_qin ();
metaIntf #(.STYPE(req_t)) bpss_wr_req_qin ();

metaIntf #(.STYPE(req_t)) bpss_rd_req_qout ();
metaIntf #(.STYPE(req_t)) bpss_wr_req_qout ();

// Assign 
assign bpss_rd_req_qin.data.vaddr = s_bpss_rd_req.data.vaddr;
assign bpss_rd_req_qin.data.len = s_bpss_rd_req.data.len;
assign bpss_rd_req_qin.data.sync = s_bpss_rd_req.data.sync;
assign bpss_rd_req_qin.data.ctl = s_bpss_rd_req.data.ctl;
assign bpss_rd_req_qin.data.stream = s_bpss_rd_req.data.stream;
assign bpss_rd_req_qin.data.dest = s_bpss_rd_req.data.dest;
assign bpss_rd_req_qin.data.pid = s_bpss_rd_req.data.pid;
assign bpss_rd_req_qin.data.vfid = s_bpss_rd_req.data.vfid;
assign bpss_rd_req_qin.data.host = 1'b0;
assign bpss_rd_req_qin.data.rsrvd = s_bpss_rd_req.data.rsrvd;
assign bpss_rd_req_qin.valid = s_bpss_rd_req.data.valid;
assign s_bpss_rd_req.ready = bpss_rd_req_qin.ready;

assign bpss_wr_req_qin.data.vaddr = s_bpss_wr_req.data.vaddr;
assign bpss_wr_req_qin.data.len = s_bpss_wr_req.data.len;
assign bpss_wr_req_qin.data.sync = s_bpss_wr_req.data.sync;
assign bpss_wr_req_qin.data.ctl = s_bpss_wr_req.data.ctl;
assign bpss_wr_req_qin.data.stream = s_bpss_wr_req.data.stream;
assign bpss_wr_req_qin.data.dest = s_bpss_wr_req.data.dest;
assign bpss_wr_req_qin.data.pid = s_bpss_wr_req.data.pid;
assign bpss_wr_req_qin.data.vfid = s_bpss_wr_req.data.vfid;
assign bpss_wr_req_qin.data.host = 1'b0;
assign bpss_wr_req_qin.data.rsrvd = s_bpss_wr_req.data.rsrvd;
assign bpss_wr_req_qin.valid = s_bpss_wr_req.data.valid;
assign s_bpss_wr_req.ready = bpss_wr_req_qin.ready;

// Command queues (user logic)
axis_data_fifo_req_96_used inst_cmd_queue_rd_user (
  .s_axis_aresetn(aresetn),
  .s_axis_aclk(aclk),
  .s_axis_tvalid(bpss_rd_req_qin.valid),
  .s_axis_tready(bpss_rd_req_qin.ready),
  .s_axis_tdata(bpss_rd_req_qin.data),
  .m_axis_tvalid(bpss_rd_req_qout.valid),
  .m_axis_tready(bpss_rd_req_qout.ready),
  .m_axis_tdata(bpss_rd_req_qout.data),
  .axis_wr_data_count()
);

axis_data_fifo_req_96_used inst_cmd_queue_wr_user (
  .s_axis_aresetn(aresetn),
  .s_axis_aclk(aclk),
  .s_axis_tvalid(bpss_wr_req_qin.valid),
  .s_axis_tready(bpss_wr_req_qin.ready),
  .s_axis_tdata(bpss_wr_req_qin.data),
  .m_axis_tvalid(bpss_wr_req_qout.valid),
  .m_axis_tready(bpss_wr_req_qout.ready),
  .m_axis_tdata(bpss_wr_req_qout.data),
  .axis_wr_data_count()
);

axis_interconnect_cnfg_req_arbiter inst_rd_interconnect_user (
  .ACLK(aclk),
  .ARESETN(aresetn),

  .S00_AXIS_ACLK(aclk),
  .S00_AXIS_ARESETN(aresetn),
  .S00_AXIS_TVALID(rd_req_host.valid),
  .S00_AXIS_TREADY(rd_req_host.ready),
  .S00_AXIS_TDATA(rd_req_host.data),

  .S01_AXIS_ACLK(aclk),
  .S01_AXIS_ARESETN(aresetn),
  .S01_AXIS_TVALID(bpss_rd_req_qout.valid),
  .S01_AXIS_TREADY(bpss_rd_req_qout.ready),
  .S01_AXIS_TDATA(bpss_rd_req_qout.data),

  .M00_AXIS_ACLK(aclk),
  .M00_AXIS_ARESETN(aresetn),
  .M00_AXIS_TVALID(m_rd_req_int.valid),
  .M00_AXIS_TREADY(m_rd_req_int.ready),
  .M00_AXIS_TDATA(m_rd_req_int.data),

  .S00_ARB_REQ_SUPPRESS(0),
  .S01_ARB_REQ_SUPPRESS(0)
);

axis_interconnect_cnfg_req_arbiter inst_wr_interconnect (
  .ACLK(aclk),
  .ARESETN(aresetn),

  .S00_AXIS_ACLK(aclk),
  .S00_AXIS_ARESETN(aresetn),
  .S00_AXIS_TVALID(wr_req_host.valid),
  .S00_AXIS_TREADY(wr_req_host.ready),
  .S00_AXIS_TDATA(wr_req_host.data),

  .S01_AXIS_ACLK(aclk),
  .S01_AXIS_ARESETN(aresetn),
  .S01_AXIS_TVALID(bpss_wr_req_qout.valid),
  .S01_AXIS_TREADY(bpss_wr_req_qout.ready),
  .S01_AXIS_TDATA(bpss_wr_req_qout.data),

  .M00_AXIS_ACLK(aclk),
  .M00_AXIS_ARESETN(aresetn),
  .M00_AXIS_TVALID(m_wr_req_int.valid),
  .M00_AXIS_TREADY(m_wr_req_int.ready),
  .M00_AXIS_TDATA(m_wr_req_int.data),

  .S00_ARB_REQ_SUPPRESS(0),
  .S01_ARB_REQ_SUPPRESS(0)
);

`else

assign m_rd_req_int.data = rd_req_host.data;
assign m_rd_req_int.valid = rd_req_host.valid;
assign rd_req_host.ready = m_rd_req_int.ready;

assign m_wr_req_int.data = wr_req_host.data;
assign m_wr_req_int.valid = wr_req_host.valid;
assign wr_req_host.ready = m_wr_req_int.ready;

`endif

`ifdef MULT_STRM_AXI
// rd req
assign m_rd_req.valid = m_rd_req_int.valid & m_rd_req.ready & m_rd_user_mux.ready;
assign m_rd_req.data = m_rd_req_int.data;

assign m_rd_user_mux.valid = m_rd_req_int.valid & m_rd_req.ready & m_rd_user_mux.ready & m_rd_req_int.data.stream; 
assign m_rd_user_mux.data = {m_rd_req_int.data.len, m_rd_req_int.data.dest};

assign m_rd_req_int.ready = m_rd_req.ready & m_rd_user_mux.ready;

// wr req
assign m_wr_req.valid = m_wr_req_int.valid & m_wr_req.ready & m_wr_user_mux.ready;
assign m_wr_req.data = m_wr_req_int.data;

assign m_wr_user_mux.valid = m_wr_req_int.valid & m_wr_req.ready & m_wr_user_mux.ready & m_wr_req_int.data.stream; 
assign m_wr_user_mux.data = {m_wr_req_int.data.len, m_wr_req_int.data.dest};

assign m_wr_req_int.ready = m_wr_req.ready & m_wr_user_mux.ready;

`else

`META_ASSIGN(m_rd_req_int, m_rd_req)
`META_ASSIGN(m_wr_req_int, m_wr_req)

`endif 

// ---------------------------------------------------------------------------------------- 
// RDMA 
// ----------------------------------------------------------------------------------------
`ifdef EN_RDMA_0

//
// SQ
//
metaIntf #(.STYPE(rdma_req_t)) rdma_0_sq_cnfg();
metaIntf #(.STYPE(rdma_req_t)) rdma_0_sq_cnfg_q();
metaIntf #(.STYPE(rdma_req_t)) rdma_0_sq();

// Assign
assign rdma_0_sq_cnfg.data.opcode                   = slv_reg[RDMA_0_POST_REG][1+:RDMA_OPCODE_BITS]; // opcode
assign rdma_0_sq_cnfg.data.qpn[0+:PID_BITS]         = slv_reg[RDMA_0_POST_REG][1+RDMA_OPCODE_BITS+:PID_BITS]; // local cpid
assign rdma_0_sq_cnfg.data.qpn[PID_BITS+:DEST_BITS] = ID_REG; // local region
assign rdma_0_sq_cnfg.data.host                     = 1'b1; //slv_reg[RDMA_0_POST_REG][1+RDMA_OPCODE_BITS+PID_BITS+DEST_BITS]; // host
assign rdma_0_sq_cnfg.data.mode                     = RDMA_MODE_PARSE; // mode
assign rdma_0_sq_cnfg.data.last                     = 1'b1;
assign rdma_0_sq_cnfg.data.cmplt                    = slv_reg[RDMA_0_POST_REG][1+RDMA_OPCODE_BITS+PID_BITS+DEST_BITS+3];
assign rdma_0_sq_cnfg.data.ssn                      = slv_reg[RDMA_0_POST_REG][32+:RDMA_MSN_BITS];
assign rdma_0_sq_cnfg.data.offs                     = 0;
assign rdma_0_sq_cnfg.data.msg[0+:64]               = slv_reg[RDMA_0_POST_REG_0]; //
assign rdma_0_sq_cnfg.data.msg[64+:64]              = slv_reg[RDMA_0_POST_REG_1]; //
assign rdma_0_sq_cnfg.data.msg[128+:64]             = slv_reg[RDMA_0_POST_REG_2]; //
assign rdma_0_sq_cnfg.data.rsrvd                    = 0; // reserved
assign rdma_0_sq_cnfg.valid                         = rdma_0_post;

// Command queue rdma (host)
axis_data_fifo_req_256_used inst_cmd_queue_host_rdma_0 (
  .s_axis_aresetn(aresetn),
  .s_axis_aclk(aclk),
  .s_axis_tvalid(rdma_0_sq_cnfg.valid),
  .s_axis_tready(rdma_0_sq_cnfg.ready),
  .s_axis_tdata(rdma_0_sq_cnfg.data),
  .m_axis_tvalid(rdma_0_sq_cnfg_q.valid),
  .m_axis_tready(rdma_0_sq_cnfg_q.ready),
  .m_axis_tdata(rdma_0_sq_cnfg_q.data),
  .axis_wr_data_count(rdma_0_queue_used)
);

`ifdef EN_RPC

metaIntf #(.STYPE(rdma_req_t)) s_rdma_0_sq_q();

// Command queue rdma (user)
axis_data_fifo_req_256_used inst_cmd_queue_user_rdma_0 (
  .s_axis_aresetn(aresetn),
  .s_axis_aclk(aclk),
  .s_axis_tvalid(s_rdma_0_sq.valid),
  .s_axis_tready(s_rdma_0_sq.ready),
  .s_axis_tdata(s_rdma_0_sq.data),
  .m_axis_tvalid(s_rdma_0_sq_q.valid),
  .m_axis_tready(s_rdma_0_sq_q.ready),
  .m_axis_tdata(s_rdma_0_sq_q.data),
  .axis_wr_data_count()
);

// Arbiter
axis_interconnect_merger_256 inst_sq_merger_0 (
    .ACLK(aclk),
    .ARESETN(aresetn),

    .S00_AXIS_ACLK(aclk),
    .S00_AXIS_ARESETN(aresetn),
    .S00_AXIS_TVALID(rdma_0_sq_cnfg_q.valid),
    .S00_AXIS_TREADY(rdma_0_sq_cnfg_q.ready),
    .S00_AXIS_TDATA(rdma_0_sq_cnfg_q.data),

    .S01_AXIS_ACLK(aclk),
    .S01_AXIS_ARESETN(aresetn),
    .S01_AXIS_TVALID(s_rdma_0_sq_q.valid),
    .S01_AXIS_TREADY(s_rdma_0_sq_q.ready),
    .S01_AXIS_TDATA(s_rdma_0_sq_q.data),

    .M00_AXIS_ACLK(aclk),
    .M00_AXIS_ARESETN(aresetn),
    .M00_AXIS_TVALID(rdma_0_sq.valid),
    .M00_AXIS_TREADY(rdma_0_sq.ready),
    .M00_AXIS_TDATA(rdma_0_sq.data),

    .S00_ARB_REQ_SUPPRESS(1'b0), 
    .S01_ARB_REQ_SUPPRESS(1'b0) 
);

`else

`META_ASSIGN(rdma_0_sq_cnfg_q, rdma_0_sq)

`endif

// Parsing
rdma_req_parser #(.ID_REG(ID_REG)) inst_parser_0 (.aclk(aclk), .aresetn(aresetn), .s_req(rdma_0_sq), .m_req(m_rdma_0_sq));

// 
// CQ
//
assign rdma_0_clear = slv_reg[RDMA_0_POST_REG][1+RDMA_OPCODE_BITS+PID_BITS+DEST_BITS];
assign rdma_0_clear_addr = slv_reg[RDMA_0_POST_REG][1+RDMA_OPCODE_BITS+:PID_BITS];

// Queue in
queue_meta #(.QDEPTH(N_OUTSTANDING)) inst_meta_rdma_0_ack (.aclk(aclk), .aresetn(aresetn), .s_meta(s_rdma_0_ack), .m_meta(rdma_0_ack));

always_ff @(posedge aclk) begin
    if(aresetn == 1'b0) begin
        rdma_0_C <= 1'b0; 
    end
    else begin
        rdma_0_C <= rdma_0_C ? 1'b0 : (rdma_0_ack.valid ? 1'b1 : rdma_0_C);
    end
end

assign rdma_0_ack.ready = (rdma_0_C && rdma_0_ack.valid);

assign a_we_rdma_0 = (rdma_0_clear || rdma_0_C) ? ~0 : 0;
assign a_data_in_rdma_0 = rdma_0_clear ? 0 : a_data_out_rdma_0 + 1;
assign a_addr_rdma_0 = rdma_0_clear ? rdma_0_clear_addr : rdma_0_ack.data.pid;
assign b_addr_rdma_0 = axi_araddr[ADDR_LSB+:PID_BITS];

ram_tp_nc #(
    .ADDR_BITS(PID_BITS),
    .DATA_BITS(32)
) inst_rdma_0_ack (
    .clk(aclk),
    .a_en(1'b1),
    .a_we(a_we_rdma_0),
    .a_addr(a_addr_rdma_0),
    .b_en(1'b1),
    .b_addr(b_addr_rdma_0),
    .a_data_in(a_data_in_rdma_0),
    .a_data_out(a_data_out_rdma_0),
    .b_data_out(b_data_out_rdma_0)
);

// Completion queue
assign cmplt_que_rdma_0_in.valid = rdma_0_ack.valid & rdma_0_ack.ready;
assign cmplt_que_rdma_0_in.data = rdma_0_ack.data;
assign cmplt_que_rdma_0_out.ready = (slv_reg_rden && axi_araddr[ADDR_LSB+:ADDR_MSB] == RDMA_0_CMPLT_REG);
queue_meta #(.QDEPTH(N_OUTSTANDING)) inst_cmplt_rdma_0_ack (.aclk(aclk), .aresetn(aresetn), .s_meta(cmplt_que_rdma_0_in), .m_meta(cmplt_que_rdma_0_out));

// RPC
`ifdef EN_RPC
assign m_rdma_0_ack.valid = rdma_0_ack.valid & rdma_0_ack.ready;
assign m_rdma_0_ack.data = rdma_0_ack.data;
`endif

`endif

`ifdef EN_RDMA_1

//
// SQ
//
metaIntf #(.STYPE(rdma_req_t)) rdma_1_sq_cnfg();
metaIntf #(.STYPE(rdma_req_t)) rdma_1_sq_cnfg_q();
metaIntf #(.STYPE(rdma_req_t)) rdma_1_sq();

// Assign
assign rdma_1_sq_cnfg.data.opcode                   = slv_reg[RDMA_1_POST_REG][1+:RDMA_OPCODE_BITS]; // opcode
assign rdma_1_sq_cnfg.data.qpn[0+:PID_BITS]         = slv_reg[RDMA_1_POST_REG][1+RDMA_OPCODE_BITS+:PID_BITS]; // local cpid
assign rdma_1_sq_cnfg.data.qpn[PID_BITS+:DEST_BITS] = ID_REG; // local region
assign rdma_1_sq_cnfg.data.host                     = 1'b1; //slv_reg[RDMA_1_POST_REG][1+RDMA_OPCODE_BITS+PID_BITS+DEST_BITS]; // host
assign rdma_1_sq_cnfg.data.mode                     = RDMA_MODE_PARSE; // mode
assign rdma_1_sq_cnfg.data.last                     = 1'b1;
assign rdma_1_sq_cnfg.data.cmplt                    = slv_reg[RDMA_1_POST_REG][1+RDMA_OPCODE_BITS+PID_BITS+DEST_BITS+3];
assign rdma_1_sq_cnfg.data.ssn                      = slv_reg[RDMA_1_POST_REG][32+:RDMA_MSN_BITS];
assign rdma_1_sq_cnfg.data.offs                     = 0;
assign rdma_1_sq_cnfg.data.msg[0+:64]               = slv_reg[RDMA_1_POST_REG_0]; //
assign rdma_1_sq_cnfg.data.msg[64+:64]              = slv_reg[RDMA_1_POST_REG_1]; //
assign rdma_1_sq_cnfg.data.msg[128+:64]             = slv_reg[RDMA_1_POST_REG_2]; //
assign rdma_1_sq_cnfg.data.rsrvd                    = 0; // reserved
assign rdma_1_sq_cnfg.valid                         = rdma_1_post;

// Command queue rdma (host)
axis_data_fifo_req_256_used inst_cmd_queue_host_rdma_1 (
  .s_axis_aresetn(aresetn),
  .s_axis_aclk(aclk),
  .s_axis_tvalid(rdma_1_sq_cnfg.valid),
  .s_axis_tready(rdma_1_sq_cnfg.ready),
  .s_axis_tdata(rdma_1_sq_cnfg.data),
  .m_axis_tvalid(rdma_1_sq_cnfg_q.valid),
  .m_axis_tready(rdma_1_sq_cnfg_q.ready),
  .m_axis_tdata(rdma_1_sq_cnfg_q.data),
  .axis_wr_data_count(rdma_1_queue_used)
);

`ifdef EN_RPC

metaIntf #(.STYPE(rdma_req_t)) s_rdma_1_sq_q();

// Command queue rdma (user)
axis_data_fifo_req_256_used inst_cmd_queue_user_rdma_1(
  .s_axis_aresetn(aresetn),
  .s_axis_aclk(aclk),
  .s_axis_tvalid(s_rdma_1_sq.valid),
  .s_axis_tready(s_rdma_1_sq.ready),
  .s_axis_tdata(s_rdma_1_sq.data),
  .m_axis_tvalid(s_rdma_1_sq_q.valid),
  .m_axis_tready(s_rdma_1_sq_q.ready),
  .m_axis_tdata(s_rdma_1_sq_q.data),
  .axis_wr_data_count()
);


// Arbiter
axis_interconnect_merger_256 inst_sq_merger_1 (
    .ACLK(aclk),
    .ARESETN(aresetn),

    .S00_AXIS_ACLK(aclk),
    .S00_AXIS_ARESETN(aresetn),
    .S00_AXIS_TVALID(rdma_1_sq_cnfg_q.valid),
    .S00_AXIS_TREADY(rdma_1_sq_cnfg_q.ready),
    .S00_AXIS_TDATA(rdma_1_sq_cnfg_q.data),

    .S01_AXIS_ACLK(aclk),
    .S01_AXIS_ARESETN(aresetn),
    .S01_AXIS_TVALID(s_rdma_1_sq_q.valid),
    .S01_AXIS_TREADY(s_rdma_1_sq_q.ready),
    .S01_AXIS_TDATA(s_rdma_1_sq_q.data),

    .M00_AXIS_ACLK(aclk),
    .M00_AXIS_ARESETN(aresetn),
    .M00_AXIS_TVALID(rdma_1_sq.valid),
    .M00_AXIS_TREADY(rdma_1_sq.ready),
    .M00_AXIS_TDATA(rdma_1_sq.data),

    .S00_ARB_REQ_SUPPRESS(1'b0), 
    .S01_ARB_REQ_SUPPRESS(1'b0) 
);

`else

`META_ASSIGN(rdma_1_sq_cnfg_q, rdma_1_sq)

`endif

// Parser
rdma_req_parser #(.ID_REG(ID_REG)) inst_parser_1 (.aclk(aclk), .aresetn(aresetn), .s_req(rdma_1_sq), .m_req(m_rdma_1_sq));

// 
// CQ
//
assign rdma_1_clear = slv_reg[RDMA_1_POST_REG][1+RDMA_OPCODE_BITS+PID_BITS+DEST_BITS];
assign rdma_1_clear_addr = slv_reg[RDMA_1_POST_REG][1+RDMA_OPCODE_BITS+:PID_BITS];

// Queue in
queue_meta #(.QDEPTH(N_OUTSTANDING)) inst_meta_rdma_1_ack (.aclk(aclk), .aresetn(aresetn), .s_meta(s_rdma_1_ack), .m_meta(rdma_1_ack));

always_ff @(posedge aclk) begin
    if(aresetn == 1'b0) begin
        rdma_1_C <= 1'b0; 
    end
    else begin
        rdma_1_C <= rdma_1_C ? 1'b0 : (rdma_1_ack.valid ? 1'b1 : rdma_1_C);
    end
end

assign rdma_1_ack.ready = (rdma_1_C && rdma_1_ack.valid);

assign a_we_rdma_1 = (rdma_1_clear || rdma_1_C) ? ~0 : 0;
assign a_data_in_rdma_1 = rdma_1_clear ? 0 : a_data_out_rdma_1 + 1;
assign a_addr_rdma_1 = rdma_1_clear ? rdma_1_clear_addr : rdma_1_ack.data.pid;
assign b_addr_rdma_1 = axi_araddr[ADDR_LSB+:PID_BITS];

ram_tp_nc #(
    .ADDR_BITS(PID_BITS),
    .DATA_BITS(32)
) inst_rdma_1_ack (
    .clk(aclk),
    .a_en(1'b1),
    .a_we(a_we_rdma_1),
    .a_addr(a_addr_rdma_1),
    .b_en(1'b1),
    .b_addr(b_addr_rdma_1),
    .a_data_in(a_data_in_rdma_1),
    .a_data_out(a_data_out_rdma_1),
    .b_data_out(b_data_out_rdma_1)
);

// Completion queue
assign cmplt_que_rdma_1_in.valid = rdma_1_ack.valid & rdma_1_ack.ready;
assign cmplt_que_rdma_1_in.data = rdma_1_ack.data;
assign cmplt_que_rdma_1_out.ready = (slv_reg_rden && axi_araddr[ADDR_LSB+:ADDR_MSB] == RDMA_1_CMPLT_REG);
queue_meta #(.QDEPTH(N_OUTSTANDING)) inst_cmplt_rdma_1_ack (.aclk(aclk), .aresetn(aresetn), .s_meta(cmplt_que_rdma_1_in), .m_meta(cmplt_que_rdma_1_out));

// RPC
`ifdef EN_RPC
assign m_rdma_1_ack.valid = rdma_1_ack.valid & rdma_1_ack.ready;
assign m_rdma_1_ack.data = rdma_1_ack.data;
`endif

`endif

// ---------------------------------------------------------------------------------------- 
// Writeback
// ----------------------------------------------------------------------------------------

`ifdef EN_WB

assign wback[0].valid = rd_clear || rd_C;
assign wback[0].data.paddr = rd_clear ? (rd_clear_addr << 2) + slv_reg[WBACK_REG][WBACK_RD_OFFS+:PADDR_BITS] : (meta_done_rd.data.pid << 2) + slv_reg[WBACK_REG][WBACK_RD_OFFS+:PADDR_BITS];
assign wback[0].data.value = rd_clear ? 0 : a_data_out_rd + 1'b1;
queue_meta #(.QDEPTH(N_OUTSTANDING)) inst_meta_wback_rd (.aclk(aclk), .aresetn(aresetn), .s_meta(wback[0]), .m_meta(wback_q[0]));

assign wback[1].valid = wr_clear || wr_C;
assign wback[1].data.paddr = wr_clear ? (wr_clear_addr << 2) + slv_reg[WBACK_REG][WBACK_WR_OFFS+:PADDR_BITS] : (meta_done_wr.data.pid << 2) + slv_reg[WBACK_REG][WBACK_WR_OFFS+:PADDR_BITS];
assign wback[1].data.value = wr_clear ? 0 : a_data_out_wr + 1'b1;
queue_meta #(.QDEPTH(N_OUTSTANDING)) inst_meta_wback_wr (.aclk(aclk), .aresetn(aresetn), .s_meta(wback[1]), .m_meta(wback_q[1]));

`ifdef EN_RDMA_0
assign wback[2].valid = rdma_0_clear || rdma_0_C;
assign wback[2].data.paddr = rdma_0_clear ? (rdma_0_clear_addr << 2) + slv_reg[WBACK_REG][WBACK_RDMA_0_OFFS+:PADDR_BITS] : (rdma_0_ack.data << 2) + slv_reg[WBACK_REG][WBACK_RDMA_0_OFFS+:PADDR_BITS];
assign wback[2].data.value = rdma_0_clear ? 0 : a_data_out_rdma_0 + 1'b1;
queue_meta #(.QDEPTH(N_OUTSTANDING)) inst_meta_wback_rdma_0 (.aclk(aclk), .aresetn(aresetn), .s_meta(wback[2]), .m_meta(wback_q[2]));

    `ifdef EN_RDMA_1
    assign wback[3].valid = rdma_1_clear || rdma_1_C;
    assign wback[3].data.paddr = rdma_1_clear ? (rdma_1_clear_addr << 2) + slv_reg[WBACK_REG][WBACK_RDMA_1_OFFS+:PADDR_BITS] : (rdma_1_ack.data << 2) + slv_reg[WBACK_REG][WBACK_RDMA_1_OFFS+:PADDR_BITS];
    assign wback[3].data.value = rdma_1_clear ? 1 : a_data_out_rdma_1 + 1'b1;
    queue_meta #(.QDEPTH(N_OUTSTANDING)) inst_meta_wback_rdma_1 (.aclk(aclk), .aresetn(aresetn), .s_meta(wback[3]), .m_meta(wback_q[3]));
    `endif
`else
    `ifdef EN_RDMA_1
    assign wback[2].valid = rdma_1_clear || rdma_1_C;
    assign wback[2].data.paddr = rdma_1_clear ? (rdma_1_clear_addr << 2) + slv_reg[WBACK_REG][WBACK_RDMA_1_OFFS+:PADDR_BITS] : (rdma_1_ack.data << 2) + slv_reg[WBACK_REG][WBACK_RDMA_1_OFFS+:PADDR_BITS];
    assign wback[2].data.value = rdma_1_clear ? 1 : a_data_out_rdma_1 + 1'b1;
    queue_meta #(.QDEPTH(N_OUTSTANDING)) inst_meta_wback_rdma_1 (.aclk(aclk), .aresetn(aresetn), .s_meta(wback[2]), .m_meta(wback_q[2]));
    `endif
`endif

// RR
meta_arbiter #(.N_ID(N_WBS), .N_ID_BITS(N_WBS_BITS), .DATA_BITS(PID_BITS)) inst_wb_arb (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_meta(wback_q),
    .m_meta(wback_arb),
    .id_out()
);

queue_meta #(.QDEPTH(N_OUTSTANDING)) inst_meta_wback (.aclk(aclk), .aresetn(aresetn), .s_meta(wback_arb), .m_meta(m_wback));

`endif

// ---------------------------------------------------------------------------------------- 
// AXI
// ----------------------------------------------------------------------------------------

// I/O
assign s_axi_ctrl.awready = axi_awready;
assign s_axi_ctrl.arready = axi_arready;
assign s_axi_ctrl.bresp = axi_bresp;
assign s_axi_ctrl.bvalid = axi_bvalid;
assign s_axi_ctrl.wready = axi_wready;
assign s_axi_ctrl.rdata = (axi_mux == 2) ? axi_rdata_bram[1] : (axi_mux == 1) ? 
    axi_rdata_bram[0] : axi_rdata;
assign s_axi_ctrl.rresp = axi_rresp;
assign s_axi_ctrl.rvalid = axi_rvalid;

// awready and awaddr
always_ff @(posedge aclk) begin
  if ( aresetn == 1'b0 )
    begin
      axi_awready <= 1'b0;
      axi_awaddr <= 0;
      aw_en <= 1'b1;
    end 
  else
    begin    
      if (~axi_awready && s_axi_ctrl.awvalid && s_axi_ctrl.wvalid && aw_en)
        begin
          axi_awready <= 1'b1;
          aw_en <= 1'b0;
          axi_awaddr <= s_axi_ctrl.awaddr;
        end
      else if (s_axi_ctrl.bready && axi_bvalid)
        begin
          aw_en <= 1'b1;
          axi_awready <= 1'b0;
        end
      else           
        begin
          axi_awready <= 1'b0;
        end
    end 
end  

// arready and araddr
always_ff @(posedge aclk) begin
  if ( aresetn == 1'b0 )
    begin
      axi_arready <= 1'b0;
      axi_araddr  <= 0;
    end 
  else
    begin    
      if (~axi_arready && s_axi_ctrl.arvalid)
        begin
          axi_arready <= 1'b1;
          axi_araddr  <= s_axi_ctrl.araddr;
        end
      else
        begin
          axi_arready <= 1'b0;
        end
    end 
end    

// bvalid and bresp
always_ff @(posedge aclk) begin
  if ( aresetn == 1'b0 )
    begin
      axi_bvalid  <= 0;
      axi_bresp   <= 2'b0;
    end 
  else
    begin    
      if (axi_awready && s_axi_ctrl.awvalid && ~axi_bvalid && axi_wready && s_axi_ctrl.wvalid)
        begin
          axi_bvalid <= 1'b1;
          axi_bresp  <= 2'b0;
        end                   
      else
        begin
          if (s_axi_ctrl.bready && axi_bvalid) 
            begin
              axi_bvalid <= 1'b0; 
            end  
        end
    end
end

// wready
always_ff @(posedge aclk) begin
  if ( aresetn == 1'b0 )
    begin
      axi_wready <= 1'b0;
    end 
  else
    begin    
      if (~axi_wready && s_axi_ctrl.wvalid && s_axi_ctrl.awvalid && aw_en )
        begin
          axi_wready <= 1'b1;
        end
      else
        begin
          axi_wready <= 1'b0;
        end
    end 
end  

// rvalid and rresp (1Del?)
always_ff @(posedge aclk) begin
  if ( aresetn == 1'b0 )
    begin
      axi_rvalid <= 0;
      axi_rresp  <= 0;
    end 
  else
    begin    
      if (axi_arready && s_axi_ctrl.arvalid && ~axi_rvalid)
        begin
          axi_rvalid <= 1'b1;
          axi_rresp  <= 2'b0;
        end   
      else if (axi_rvalid && s_axi_ctrl.rready)
        begin
          axi_rvalid <= 1'b0;
        end                
    end
end    

endmodule
