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

module cnfg_slave_avx #(
    parameter integer           ID_REG = 0 
) (
    input  logic                aclk,
    input  logic                aresetn,

    // Control bus (HOST)
    AXI4.s                      s_axim_ctrl,

`ifdef EN_BPSS
    // Request user logic
    metaIntf.s                  s_bpss_rd_req,
    metaIntf.s                  s_bpss_wr_req,
    metaIntf.m                  m_bpss_rd_done,
    metaIntf.m                  m_bpss_wr_done,
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
localparam integer ADDR_LSB = $clog2(AVX_DATA_BITS/8);
localparam integer ADDR_MSB = $clog2(N_REGS);
localparam integer AVX_ADDR_BITS = ADDR_LSB + ADDR_MSB;

localparam integer CTRL_BYTES = 8;

// Internal regs
logic [AVX_ADDR_BITS-1:0] axi_awaddr;
logic axi_awready;
logic axi_wready;
logic [1:0] axi_bresp;
logic axi_bvalid;
logic [AVX_ADDR_BITS-1:0] axi_araddr;
logic axi_arready;
logic [AVX_DATA_BITS-1:0] axi_rdata;
logic [1:0] axi_rresp;
logic axi_rlast;
logic axi_rvalid;

logic [AVX_DATA_BITS-1:0] axi_rdata_bram;
logic axi_mux;

logic [1:0] axi_arburst;
logic [1:0] axi_awburst;
logic [7:0] axi_arlen;
logic [7:0] axi_awlen;
logic [7:0] axi_awlen_cntr;
logic [7:0] axi_arlen_cntr;

logic aw_wrap_en;
logic ar_wrap_en;
logic [31:0] aw_wrap_size; 
logic [31:0] ar_wrap_size; 

logic axi_awv_awr_flag;
logic axi_arv_arr_flag; 

// Slave registers
logic [N_REGS-1:0][AVX_DATA_BITS-1:0] slv_reg;
logic slv_reg_rden;
logic slv_reg_wren;

// Internal signals
logic irq_pending;
logic rd_sent_host, rd_sent_card, rd_sent_sync;
logic wr_sent_host, wr_sent_card, wr_sent_sync;

logic [31:0] rd_queue_used;
logic [31:0] wr_queue_used;

metaIntf #(.STYPE(logic[PID_BITS-1:0])) meta_host_done_rd_out ();
metaIntf #(.STYPE(logic[PID_BITS-1:0])) meta_card_done_rd_out ();
metaIntf #(.STYPE(logic[PID_BITS-1:0])) meta_sync_done_rd_out ();
metaIntf #(.STYPE(logic[PID_BITS-1:0])) meta_done_rd ();
logic rd_C;
logic [3:0] a_we_rd;
logic [PID_BITS-1:0] a_addr_rd;
logic [PID_BITS-1:0] b_addr_rd;
logic [31:0] a_data_in_rd;
logic [31:0] a_data_out_rd;
logic [31:0] b_data_out_rd;
logic rd_clear;
logic [PID_BITS-1:0] rd_clear_addr;

metaIntf #(.STYPE(logic[PID_BITS-1:0])) meta_host_done_wr_out ();
metaIntf #(.STYPE(logic[PID_BITS-1:0])) meta_card_done_wr_out ();
metaIntf #(.STYPE(logic[PID_BITS-1:0])) meta_sync_done_wr_out ();
metaIntf #(.STYPE(logic[PID_BITS-1:0])) meta_done_wr ();
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
metaIntf #(.STYPE(wback_t)) wback [2+N_RDMA] ();
metaIntf #(.STYPE(wback_t)) wback_arb [2+N_RDMA] ();
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
`endif

// -- Def --------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------

// -- Register map ----------------------------------------------------------------------- 
// 0 (W1S|W1C) : Control 
localparam integer CTRL_REG                                 = 0;
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
    localparam integer CTRL_VADDR_RD_OFFS   = 64;
    localparam integer CTRL_VADDR_WR_OFFS   = 128;
    localparam integer CTRL_LEN_RD_OFFS     = 192;
    localparam integer CTRL_LEN_WR_OFFS     = 224;
// 1 (RO) : Page fault 
localparam integer PF_REG                                   = 1;
    localparam integer VADDR_MISS_OFFS      = 0;
    localparam integer LEN_MISS_OFFS        = 64;
    localparam integer PID_MISS_OFFS        = 96;
// 2, 3 (W1S|W1C|R) : Datapath control set/clear
localparam integer CTRL_DP_REG_SET                          = 2;
localparam integer CTRL_DP_REG_CLR                          = 3;
    localparam integer CTRL_DP_DECOUPLE     = 0;
// 4 (RO) : Status
localparam integer STAT_REG                                 = 4;
    localparam integer STAT_CMD_USED_RD_OFFS    = 0;
    localparam integer STAT_CMD_USED_WR_OFFS    = 16;
    localparam integer STAT_SENT_HOST_RD_OFFS   = 32;
    localparam integer STAT_SENT_HOST_WR_OFFS   = 64;
    localparam integer STAT_SENT_CARD_RD_OFFS   = 96;
    localparam integer STAT_SENT_CARD_WR_OFFS   = 128;
    localparam integer STAT_SENT_SYNC_RD_OFFS   = 160;
    localparam integer STAT_SENT_SYNC_WR_OFFS   = 192;
    localparam integer STAT_PFAULTS_OFFS        = 224;
// 5 (RW) : Writeback locations
localparam integer WBACK_REG                                = 5;
    localparam integer WBACK_RD_OFFS            = 0;
    localparam integer WBACK_WR_OFFS            = 64;
    localparam integer WBACK_RDMA_0_OFFS        = 128;
    localparam integer WBACK_RDMA_1_OFFS        = 192;

// RDMA 0
// 10-12 (W1S) : Post
localparam integer RDMA_0_POST_REG                          = 16;
localparam integer RDMA_0_POST_REG_0                        = 17;
localparam integer RDMA_0_POST_REG_1                        = 18;
// 11 (RO) : Status cmd used
localparam integer RDMA_0_STAT_REG                          = 19;
    localparam integer RDMA_STAT_CMD_USED_OFFS  = 0;
    localparam integer RDMA_POSTED_OFFS         = 32;

// RDMA 1
// 12 (W1S) : Post
localparam integer RDMA_1_POST_REG                          = 24;
localparam integer RDMA_1_POST_REG_0                        = 25;
localparam integer RDMA_1_POST_REG_1                        = 26;
// 13 (RO) : Status cmd used
localparam integer RDMA_1_STAT_REG                          = 27;

// 64 (RO) : Status DMA completion
localparam integer STAT_DMA_REG                             = 2**PID_BITS;
//

// ---------------------------------------------------------------------------------------- 
// Write process 
// ----------------------------------------------------------------------------------------
assign slv_reg_wren = axi_wready && s_axim_ctrl.wvalid;

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

    end
    else begin
        slv_reg[CTRL_REG][CTRL_BYTES*8-1:0] <= 0;

`ifdef EN_RDMA_0
        rdma_0_post <= 1'b0;
`endif

`ifdef EN_RDMA_1
        rdma_1_post <= 1'b0;
`endif

        // Page fault
        if(s_pfault_rd.valid || s_pfault_wr.valid) begin
            irq_pending <= 1'b1;
            slv_reg[PF_REG][VADDR_MISS_OFFS+:VADDR_BITS] <= s_pfault_rd.valid ? s_pfault_rd.data[0+:VADDR_BITS] : s_pfault_wr.data[0+:VADDR_BITS]; // miss length
            slv_reg[PF_REG][LEN_MISS_OFFS+:LEN_BITS]  <= s_pfault_rd.valid ? s_pfault_rd.data[VADDR_BITS+:LEN_BITS] : s_pfault_wr.data[VADDR_BITS+:LEN_BITS]; // miss length
            slv_reg[PF_REG][PID_MISS_OFFS+:PID_BITS]  <= s_pfault_rd.valid ? s_pfault_rd.data[VADDR_BITS+LEN_BITS+:PID_BITS] : s_pfault_wr.data[VADDR_BITS+LEN_BITS+:PID_BITS]; // miss pid
        end
        if(slv_reg[CTRL_REG][CTRL_CLR_IRQ_PENDING]) begin
            irq_pending <= 1'b0;
        end

        // Slave write
        if(slv_reg_wren) begin
            case (axi_awaddr[ADDR_LSB+:ADDR_MSB]) 
                CTRL_REG: // Control
                    for (int i = 0; i < (AVX_DATA_BITS/8); i++) begin
                        if(s_axim_ctrl.wstrb[i]) begin
                            slv_reg[CTRL_REG][(i*8)+:8] <= s_axim_ctrl.wdata[(i*8)+:8];
                        end
                    end
                CTRL_DP_REG_SET: // Control datapath set
                    for (int i = 0; i < CTRL_BYTES; i++) begin
                        if(s_axim_ctrl.wstrb[i]) begin
                            slv_reg[CTRL_DP_REG_SET][(i*8)+:8] <= slv_reg[CTRL_DP_REG_SET][(i*8)+:8] | s_axim_ctrl.wdata[(i*8)+:8];
                        end
                    end
                CTRL_DP_REG_CLR: // Control datapath clear
                    for (int i = 0; i < CTRL_BYTES; i++) begin
                        if(s_axim_ctrl.wstrb[i]) begin
                            slv_reg[CTRL_DP_REG_SET][(i*8)+:8] <= slv_reg[CTRL_DP_REG_SET][(i*8)+:8] & ~s_axim_ctrl.wdata[(i*8)+:8];
                        end
                    end

`ifdef EN_WB
                WBACK_REG: // Writeback
                    for (int i = 0; i < AVX_DATA_BITS/8; i++) begin
                        if(s_axim_ctrl.wstrb[i]) begin
                            slv_reg[WBACK_REG][(i*8)+:8] <= s_axim_ctrl.wdata[(i*8)+:8];
                        end
                    end
`endif

`ifdef EN_RDMA_0
                RDMA_0_POST_REG: begin // Post
                    rdma_0_post <= s_axim_ctrl.wdata[0];
                    for (int i = 0; i < AVX_DATA_BITS/8; i++) begin
                        if(s_axim_ctrl.wstrb[i]) begin
                            slv_reg[RDMA_0_POST_REG][(i*8)+:8] <= s_axim_ctrl.wdata[(i*8)+:8];
                        end
                    end
                end
                RDMA_0_POST_REG_0: // Post
                    for (int i = 0; i < AVX_DATA_BITS/8; i++) begin
                        if(s_axim_ctrl.wstrb[i]) begin
                            slv_reg[RDMA_0_POST_REG_0][(i*8)+:8] <= s_axim_ctrl.wdata[(i*8)+:8];
                        end
                    end
                RDMA_0_POST_REG_1: // Post
                    for (int i = 0; i < AVX_DATA_BITS/8; i++) begin
                        if(s_axim_ctrl.wstrb[i]) begin
                            slv_reg[RDMA_0_POST_REG_1][(i*8)+:8] <= s_axim_ctrl.wdata[(i*8)+:8];
                        end
                    end
`endif

`ifdef EN_RDMA_1
                RDMA_1_POST_REG: begin // Post
                    rdma_1_post <= s_axim_ctrl.wdata[0];
                    for (int i = 0; i < AVX_DATA_BITS/8; i++) begin
                        if(s_axim_ctrl.wstrb[i]) begin
                            slv_reg[RDMA_1_POST_REG][(i*8)+:8] <= s_axim_ctrl.wdata[(i*8)+:8];
                        end
                    end
                end
                RDMA_1_POST_REG_0: // Post
                    for (int i = 0; i < AVX_DATA_BITS/8; i++) begin
                        if(s_axim_ctrl.wstrb[i]) begin
                            slv_reg[RDMA_1_POST_REG_0][(i*8)+:8] <= s_axim_ctrl.wdata[(i*8)+:8];
                        end
                    end
                RDMA_1_POST_REG_1: // Post
                    for (int i = 0; i < AVX_DATA_BITS/8; i++) begin
                        if(s_axim_ctrl.wstrb[i]) begin
                            slv_reg[RDMA_1_POST_REG_1][(i*8)+:8] <= s_axim_ctrl.wdata[(i*8)+:8];
                        end
                    end
`endif

                default: ;
            endcase
        end

        // Status counters
        slv_reg[STAT_REG][STAT_SENT_HOST_RD_OFFS+:32] <= slv_reg[STAT_REG][STAT_SENT_HOST_RD_OFFS+:32] + rd_sent_host;
        slv_reg[STAT_REG][STAT_SENT_HOST_WR_OFFS+:32] <= slv_reg[STAT_REG][STAT_SENT_HOST_WR_OFFS+:32] + wr_sent_host;
        slv_reg[STAT_REG][STAT_SENT_CARD_RD_OFFS+:32] <= slv_reg[STAT_REG][STAT_SENT_CARD_RD_OFFS+:32] + rd_sent_card;
        slv_reg[STAT_REG][STAT_SENT_CARD_WR_OFFS+:32] <= slv_reg[STAT_REG][STAT_SENT_CARD_WR_OFFS+:32] + wr_sent_card;
        slv_reg[STAT_REG][STAT_SENT_SYNC_RD_OFFS+:32] <= slv_reg[STAT_REG][STAT_SENT_SYNC_RD_OFFS+:32] + rd_sent_sync;
        slv_reg[STAT_REG][STAT_SENT_SYNC_WR_OFFS+:32] <= slv_reg[STAT_REG][STAT_SENT_SYNC_WR_OFFS+:32] + wr_sent_sync;
        slv_reg[STAT_REG][STAT_PFAULTS_OFFS+:32] <= slv_reg[STAT_REG][STAT_PFAULTS_OFFS+:32] + (s_pfault_rd.valid || s_pfault_wr.valid);

`ifdef EN_RDMA_0
        slv_reg[RDMA_0_STAT_REG][RDMA_POSTED_OFFS+:32] <= slv_reg[RDMA_0_STAT_REG][RDMA_POSTED_OFFS+:32] + rdma_0_post;
`endif

`ifdef EN_RDMA_1
        slv_reg[RDMA_1_STAT_REG][RDMA_POSTED_OFFS+:32] <= slv_reg[RDMA_1_STAT_REG][RDMA_POSTED_OFFS+:32] + rdma_1_post;
`endif

    end
end

// ---------------------------------------------------------------------------------------- 
// Read process 
// ----------------------------------------------------------------------------------------
assign slv_reg_rden = axi_arv_arr_flag; // & ~axi_rvalid;

always_ff @(posedge aclk) begin
  if( aresetn == 1'b0 ) begin
    axi_rdata <= 'X;
    axi_mux <= 'X;
  end
  else begin
    if(slv_reg_rden) begin
      axi_rdata <= 0;
      axi_mux <= 1'b0;

      case (axi_araddr[ADDR_LSB+:ADDR_MSB]) inside
        [PF_REG:PF_REG]:
            axi_rdata[0+:128] <= slv_reg[PF_REG][127:0];
        [CTRL_DP_REG_SET:CTRL_DP_REG_CLR]:
            axi_rdata[15:0] <= slv_reg[CTRL_DP_REG_SET][15:0];
        [STAT_REG:STAT_REG]: begin
            axi_rdata[31:0] <= {wr_queue_used[15:0], rd_queue_used[15:0]};
            axi_rdata[255:32] <= slv_reg[STAT_REG][255:32];        
        end

`ifdef EN_WB
        [WBACK_REG:WBACK_REG]:
            axi_rdata <= slv_reg[WBACK_REG];
`endif

`ifdef EN_RDMA_0
        [RDMA_0_POST_REG_0:RDMA_0_POST_REG_0]:
            axi_rdata <= slv_reg[RDMA_0_POST_REG_0];
        [RDMA_0_POST_REG_1:RDMA_0_POST_REG_1]:
            axi_rdata[127:0] <= slv_reg[RDMA_0_POST_REG_1][127:0];
        [RDMA_0_STAT_REG:RDMA_0_STAT_REG]:
            axi_rdata[63:0] <= {slv_reg[RDMA_0_STAT_REG][RDMA_POSTED_OFFS+:32], rdma_0_queue_used[31:0]};
`endif

`ifdef EN_RDMA_1
        [RDMA_1_POST_REG_0:RDMA_1_POST_REG_0]:
            axi_rdata <= slv_reg[RDMA_1_POST_REG_0];
        [RDMA_1_POST_REG_1:RDMA_1_POST_REG_1]:
            axi_rdata[127:0] <= slv_reg[RDMA_1_POST_REG_1][127:0];
        [RDMA_1_STAT_REG:RDMA_1_STAT_REG]:
            axi_rdata[63:0] <= {slv_reg[RDMA_1_STAT_REG][RDMA_POSTED_OFFS+:32], rdma_1_queue_used[31:0]};
`endif

        [STAT_DMA_REG:STAT_DMA_REG+(2**PID_BITS)-1]: begin
            axi_mux <= 1'b1; 
        end
        
        default: ;
      endcase
    end
  end 
end

assign axi_rdata_bram[AVX_DATA_BITS-1:128] = 0; 
assign axi_rdata_bram[63:0] = {b_data_out_wr, b_data_out_rd};
`ifdef EN_RDMA_0
assign axi_rdata_bram[64+:32] = b_data_out_rdma_0;
`else 
assign axi_rdata_bram[64+:32] = 0;
`endif
`ifdef EN_RDMA_1
assign axi_rdata_bram[96+:32] = b_data_out_rdma_1;
`else 
assign axi_rdata_bram[96+:32] = 0;
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
assign a_addr_rd = rd_clear ? rd_clear_addr : meta_done_rd.data;
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
assign a_addr_wr = wr_clear ? wr_clear_addr : meta_done_wr.data;
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
assign rd_req_cnfg.data.vaddr = slv_reg[CTRL_REG][CTRL_VADDR_RD_OFFS+:VADDR_BITS];
assign rd_req_cnfg.data.len = slv_reg[CTRL_REG][CTRL_LEN_RD_OFFS+:LEN_BITS];
assign rd_req_cnfg.data.stream = slv_reg[CTRL_REG][CTRL_STREAM_RD];
assign rd_req_cnfg.data.sync = slv_reg[CTRL_REG][CTRL_SYNC_RD];
assign rd_req_cnfg.data.ctl = 1'b1;
assign rd_req_cnfg.data.dest = slv_reg[CTRL_REG][CTRL_DEST_RD+:DEST_BITS];
assign rd_req_cnfg.data.pid = slv_reg[CTRL_REG][CTRL_PID_RD+:PID_BITS];
assign rd_req_cnfg.data.vfid = ID_REG;
assign rd_req_cnfg.data.host = 0;
assign rd_req_cnfg.data.rsrvd = 0;
assign rd_req_cnfg.valid = slv_reg[CTRL_REG][CTRL_START_RD];

assign wr_req_cnfg.data.vaddr = slv_reg[CTRL_REG][CTRL_VADDR_WR_OFFS+:VADDR_BITS];
assign wr_req_cnfg.data.len = slv_reg[CTRL_REG][CTRL_LEN_WR_OFFS+:LEN_BITS];
assign wr_req_cnfg.data.sync = slv_reg[CTRL_REG][CTRL_SYNC_WR];
assign wr_req_cnfg.data.ctl = 1'b1;
assign wr_req_cnfg.data.stream = slv_reg[CTRL_REG][CTRL_STREAM_WR];
assign wr_req_cnfg.data.dest = slv_reg[CTRL_REG][CTRL_DEST_WR+:DEST_BITS];
assign wr_req_cnfg.data.pid = slv_reg[CTRL_REG][CTRL_PID_WR+:PID_BITS];
assign wr_req_cnfg.data.vfid = ID_REG;
assign wr_req_cnfg.data.host = 0;
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

`ifdef EN_BPSS

metaIntf #(.STYPE(req_t)) bpss_rd_req_q ();
metaIntf #(.STYPE(req_t)) bpss_wr_req_q ();

// Command queues (user logic)
axis_data_fifo_req_96_used inst_cmd_queue_rd_user (
  .s_axis_aresetn(aresetn),
  .s_axis_aclk(aclk),
  .s_axis_tvalid(s_bpss_rd_req.valid),
  .s_axis_tready(s_bpss_rd_req.ready),
  .s_axis_tdata(s_bpss_rd_req.data),
  .m_axis_tvalid(bpss_rd_req_q.valid),
  .m_axis_tready(bpss_rd_req_q.ready),
  .m_axis_tdata(bpss_rd_req_q.data),
  .axis_wr_data_count()
);

axis_data_fifo_req_96_used inst_cmd_queue_wr_user (
  .s_axis_aresetn(aresetn),
  .s_axis_aclk(aclk),
  .s_axis_tvalid(s_bpss_wr_req.valid),
  .s_axis_tready(s_bpss_wr_req.ready),
  .s_axis_tdata(s_bpss_wr_req.data),
  .m_axis_tvalid(bpss_wr_req_q.valid),
  .m_axis_tready(bpss_wr_req_q.ready),
  .m_axis_tdata(bpss_wr_req_q.data),
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
  .S01_AXIS_TVALID(bpss_rd_req_q.valid),
  .S01_AXIS_TREADY(bpss_rd_req_q.ready),
  .S01_AXIS_TDATA(bpss_rd_req_q.data),

  .M00_AXIS_ACLK(aclk),
  .M00_AXIS_ARESETN(aresetn),
  .M00_AXIS_TVALID(m_rd_req.valid),
  .M00_AXIS_TREADY(m_rd_req.ready),
  .M00_AXIS_TDATA(m_rd_req.data),

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
  .S01_AXIS_TVALID(bpss_wr_req_q.valid),
  .S01_AXIS_TREADY(bpss_wr_req_q.ready),
  .S01_AXIS_TDATA(bpss_wr_req_q.data),

  .M00_AXIS_ACLK(aclk),
  .M00_AXIS_ARESETN(aresetn),
  .M00_AXIS_TVALID(m_wr_req.valid),
  .M00_AXIS_TREADY(m_wr_req.ready),
  .M00_AXIS_TDATA(m_wr_req.data),

  .S00_ARB_REQ_SUPPRESS(0),
  .S01_ARB_REQ_SUPPRESS(0)
);

`else

assign m_rd_req.data = rd_req_host.data;
assign m_rd_req.valid = rd_req_host.valid;
assign rd_req_host.ready = m_rd_req.ready;

assign m_wr_req.data = wr_req_host.data;
assign m_wr_req.valid = wr_req_host.valid;
assign wr_req_host.ready = m_wr_req.ready;

`endif

// ---------------------------------------------------------------------------------------- 
// RDMA
// ----------------------------------------------------------------------------------------
`ifdef EN_RDMA_0

// RDMA requests
metaIntf #(.STYPE(rdma_req_t)) rdma_0_sq_cnfg();
metaIntf #(.STYPE(rdma_req_t)) rdma_0_sq;

// Assign
assign rdma_0_sq_cnfg.data.opcode                   = slv_reg[RDMA_0_POST_REG][1+:RDMA_OPCODE_BITS]; // opcode
assign rdma_0_sq_cnfg.data.qpn[0+:PID_BITS]         = slv_reg[RDMA_0_POST_REG][1+RDMA_OPCODE_BITS+:PID_BITS]; // local cpid
assign rdma_0_sq_cnfg.data.qpn[PID_BITS+:DEST_BITS] = ID_REG; // local region
assign rdma_0_sq_cnfg.data.host                     = slv_reg[RDMA_0_POST_REG][1+RDMA_OPCODE_BITS+PID_BITS+DEST_BITS]; // host
assign rdma_0_sq_cnfg.data.mode                     = RDMA_MODE_PARSE; // mode
assign rdma_0_sq_cnfg.data.last                     = 1'b1;
assign rdma_0_sq_cnfg.data.msg[0+:192]              = slv_reg[RDMA_0_POST_REG][255:64];
assign rdma_0_sq_cnfg.data.msg[192+:256]            = slv_reg[RDMA_0_POST_REG_0];
assign rdma_0_sq_cnfg.data.msg[448+:64]             = slv_reg[RDMA_0_POST_REG_1][63:0];
assign rdma_0_sq_cnfg.data.rsrvd                    = 0; // reserved
assign rdma_0_sq_cnfg.valid                         = rdma_0_post;

// Arbiter
`ifdef EN_RPC

axis_interconnect_merger_256 inst_sq_merger_0 (
    .ACLK(aclk),
    .ARESETN(aresetn),

    .S00_AXIS_ACLK(aclk),
    .S00_AXIS_ARESETN(aresetn),
    .S00_AXIS_TVALID(rdma_0_sq_cnfg.valid),
    .S00_AXIS_TREADY(rdma_0_sq_cnfg.ready),
    .S00_AXIS_TDATA(rdma_0_sq_cnfg.data),

    .S01_AXIS_ACLK(aclk),
    .S01_AXIS_ARESETN(aresetn),
    .S01_AXIS_TVALID(s_rdma_0_sq.valid),
    .S01_AXIS_TREADY(s_rdma_0_sq.ready),
    .S01_AXIS_TDATA(s_rdma_0_sq.data),

    .M00_AXIS_ACLK(aclk),
    .M00_AXIS_ARESETN(aresetn),
    .M00_AXIS_TVALID(rdma_0_sq.valid),
    .M00_AXIS_TREADY(rdma_0_sq.ready),
    .M00_AXIS_TDATA(rdma_0_sq.data),

    .S00_ARB_REQ_SUPPRESS(1'b0), 
    .S01_ARB_REQ_SUPPRESS(1'b0) 
);

`else

`META_ASSIGN(rdma_0_sq_cnfg, rdma_0_sq)

`endif

// Parser
rdma_req_parser #(.ID_REG(ID_REG)) inst_parser_0 (.aclk(aclk), .aresetn(aresetn), .s_req(rdma_0_sq), .m_req(m_rdma_0_sq), .used(rdma_0_queue_used));

// ACKs
assign rdma_0_clear = slv_reg[RDMA_0_POST_REG][1+RDMA_OPCODE_BITS+PID_BITS+DEST_BITS+3];
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

assign rdma_0_ack.ready = (rdma_0_C & rdma_0_ack.valid);

`ifdef EN_RPC
assign m_rdma_0_ack.valid = (rdma_0_C & rdma_0_ack.valid);
assign m_rdma_0_ack.data = rdma_0_ack.data;
`endif

assign a_we_rdma_0 = (rdma_0_clear || rdma_0_C) ? ~0 : 0;
assign a_addr_rdma_0 = rdma_0_clear ? rdma_0_clear_addr : rdma_0_ack.data.pid;
assign a_data_in_rdma_0 = rdma_0_clear ? 0 : a_data_out_rdma_0 + 1'b1;
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

`endif

`ifdef EN_RDMA_1

// RDMA requests
metaIntf #(.STYPE(rdma_req_t)) rdma_1_sq_cnfg();
metaIntf #(.STYPE(rdma_req_t)) rdma_1_sq();

// Assign
assign rdma_1_sq_cnfg.data.opcode                   = slv_reg[RDMA_1_POST_REG][1+:RDMA_OPCODE_BITS]; // opcode
assign rdma_1_sq_cnfg.data.qpn[0+:PID_BITS]         = slv_reg[RDMA_1_POST_REG][1+RDMA_OPCODE_BITS+:PID_BITS]; // local cpid
assign rdma_1_sq_cnfg.data.qpn[PID_BITS+:DEST_BITS] = ID_REG; // local region
assign rdma_1_sq_cnfg.data.host                     = slv_reg[RDMA_1_POST_REG][1+RDMA_OPCODE_BITS+PID_BITS+DEST_BITS]; // host
assign rdma_1_sq_cnfg.data.mode                     = RDMA_MODE_PARSE; // mode
assign rdma_1_sq_cnfg.data.last                     = 1'b1;
assign rdma_1_sq_cnfg.data.msg[0+:192]              = slv_reg[RDMA_1_POST_REG][255:64];
assign rdma_1_sq_cnfg.data.msg[192+:256]            = slv_reg[RDMA_1_POST_REG_0];
assign rdma_1_sq_cnfg.data.msg[448+:64]             = slv_reg[RDMA_1_POST_REG_1][63:0];
assign rdma_1_sq_cnfg.data.rsrvd                    = 0; // reserved
assign rdma_1_sq_cnfg.valid                         = rdma_1_post;

// Arbiter
`ifdef EN_RPC

axis_interconnect_merger_256 inst_sq_merger_1 (
    .ACLK(aclk),
    .ARESETN(aresetn),

    .S00_AXIS_ACLK(aclk),
    .S00_AXIS_ARESETN(aresetn),
    .S00_AXIS_TVALID(rdma_1_sq_cnfg.valid),
    .S00_AXIS_TREADY(rdma_1_sq_cnfg.ready),
    .S00_AXIS_TDATA(rdma_1_sq_cnfg.data),

    .S01_AXIS_ACLK(aclk),
    .S01_AXIS_ARESETN(aresetn),
    .S01_AXIS_TVALID(s_rdma_1_sq.valid),
    .S01_AXIS_TREADY(s_rdma_1_sq.ready),
    .S01_AXIS_TDATA(s_rdma_1_sq.data),

    .M00_AXIS_ACLK(aclk),
    .M00_AXIS_ARESETN(aresetn),
    .M00_AXIS_TVALID(rdma_1_sq.valid),
    .M00_AXIS_TREADY(rdma_1_sq.ready),
    .M00_AXIS_TDATA(rdma_1_sq.data),

    .S00_ARB_REQ_SUPPRESS(1'b0), 
    .S01_ARB_REQ_SUPPRESS(1'b0) 
);

`else

`META_ASSIGN(rdma_1_sq_cnfg, rdma_1_sq)

`endif

// Parser
rdma_req_parser #(.ID_REG(ID_REG)) inst_parser_1 (.aclk(aclk), .aresetn(aresetn), .s_req(rdma_1_sq), .m_req(m_rdma_1_sq), .used(rdma_1_queue_used));

// ACKs
assign rdma_1_clear = slv_reg[RDMA_1_POST_REG][1+RDMA_OPCODE_BITS+PID_BITS+DEST_BITS+3];
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

assign rdma_1_ack.ready = (rdma_1_C & rdma_1_ack.valid);

`ifdef EN_RPC
assign m_rdma_1_ack.valid = (rdma_1_C & rdma_1_ack.valid);
assign m_rdma_1_ack.data = rdma_1_ack.data;
`endif

assign a_we_rdma_1 = (rdma_1_clear || rdma_1_C) ? ~0 : 0;
assign a_addr_rdma_1 = rdma_1_clear ? rdma_1_clear_addr : rdma_1_ack.data.pid;
assign a_data_in_rdma_1 = rdma_1_clear ? 0 : a_data_out_rdma_1 + 1'b1;
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

`endif

// ---------------------------------------------------------------------------------------- 
// Writeback
// ----------------------------------------------------------------------------------------

`ifdef EN_WB

assign wback[0].valid = rd_clear || rd_C;
assign wback[0].data.paddr = rd_clear ? (rd_clear_addr << 2) + slv_reg[WBACK_REG][WBACK_RD_OFFS+:PADDR_BITS] : (meta_done_rd.data << 2) + slv_reg[WBACK_REG][WBACK_RD_OFFS+:PADDR_BITS];
assign wback[0].data.value = rd_clear ? 0 : a_data_out_rd + 1'b1;
queue_meta #(.QDEPTH(N_OUTSTANDING)) inst_meta_wback_rd (.aclk(aclk), .aresetn(aresetn), .s_meta(wback[0]), .m_meta(wback_q[0]));

assign wback[1].valid = wr_clear || wr_C;
assign wback[1].data.paddr = wr_clear ? (wr_clear_addr << 2) + slv_reg[WBACK_REG][WBACK_WR_OFFS+:PADDR_BITS] : (meta_done_wr.data << 2) + slv_reg[WBACK_REG][WBACK_WR_OFFS+:PADDR_BITS];
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
    queue_meta #(.QDEPTH(N_OUTSTANDING)) inst_meta_wback_rdma_1 (.aclk(aclk), .aresetn(aresetn), .s_meta(wback[3]), .m_meta(wback_arb[3]));
    `endif
`else
    `ifdef EN_RDMA_1
    assign wback[2].valid = rdma_1_clear || rdma_1_C;
    assign wback[2].data.paddr = rdma_1_clear ? (rdma_1_clear_addr << 2) + slv_reg[WBACK_REG][WBACK_RDMA_1_OFFS+:PADDR_BITS] : (rdma_1_ack.data << 2) + slv_reg[WBACK_REG][WBACK_RDMA_1_OFFS+:PADDR_BITS];
    assign wback[2].data.value = rdma_1_clear ? 1 : a_data_out_rdma_1 + 1'b1;
    queue_meta #(.QDEPTH(N_OUTSTANDING)) inst_meta_wback_rdma_1 (.aclk(aclk), .aresetn(aresetn), .s_meta(wback[2]), .m_meta(wback_arb[2]));
    `endif
`endif

// RR
meta_arbiter #(.N_ID(N_RDMA+2), .N_ID_BITS($clog2(N_RDMA+2), .DATA_BITS(PID_BITS)) inst_wb_arb (
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
assign s_axim_ctrl.awready = axi_awready;
assign s_axim_ctrl.wready = axi_wready;
assign s_axim_ctrl.bresp = axi_bresp;
assign s_axim_ctrl.bvalid = axi_bvalid;
assign s_axim_ctrl.arready = axi_arready;
assign s_axim_ctrl.rdata = axi_mux ? axi_rdata_bram : axi_rdata;
assign s_axim_ctrl.rresp = axi_rresp;
assign s_axim_ctrl.rlast = axi_rlast;
assign s_axim_ctrl.rvalid = axi_rvalid;
assign s_axim_ctrl.bid = s_axim_ctrl.awid;
assign s_axim_ctrl.rid = s_axim_ctrl.arid;
assign aw_wrap_size = (AVX_DATA_BITS/8 * (axi_awlen)); 
assign ar_wrap_size = (AVX_DATA_BITS/8 * (axi_arlen)); 
assign aw_wrap_en = ((axi_awaddr & aw_wrap_size) == aw_wrap_size)? 1'b1: 1'b0;
assign ar_wrap_en = ((axi_araddr & ar_wrap_size) == ar_wrap_size)? 1'b1: 1'b0;

// awready
always @( posedge aclk )
begin
    if ( aresetn == 1'b0 )
    begin
        axi_awready <= 1'b0;
        axi_awv_awr_flag <= 1'b0;
    end 
    else
    begin    
        if (~axi_awready && s_axim_ctrl.awvalid && ~axi_awv_awr_flag && ~axi_arv_arr_flag)
        begin
            // slave is ready to accept an address and
            // associated control signals
            axi_awready <= 1'b1;
            axi_awv_awr_flag  <= 1'b1; 
            // used for generation of bresp() and bvalid
        end
        else if (s_axim_ctrl.wlast && axi_wready)          
        // preparing to accept next address after current write burst tx completion
        begin
            axi_awv_awr_flag  <= 1'b0;
        end
        else        
        begin
            axi_awready <= 1'b0;
        end
    end 
end       

// awaddr
always @( posedge aclk )
begin
    if ( aresetn == 1'b0 )
    begin
        axi_awaddr <= 0;
        axi_awlen_cntr <= 0;
        axi_awburst <= 0;
        axi_awlen <= 0;
    end 
    else
    begin    
        if (~axi_awready && s_axim_ctrl.awvalid && ~axi_awv_awr_flag)
        begin
            // address latching 
            axi_awaddr <= s_axim_ctrl.awaddr[AVX_ADDR_BITS-1:0];  
            axi_awburst <= s_axim_ctrl.awburst; 
            axi_awlen <= s_axim_ctrl.awlen;     
            // start address of transfer
            axi_awlen_cntr <= 0;
        end   
        else if((axi_awlen_cntr <= axi_awlen) && axi_wready && s_axim_ctrl.wvalid)        
        begin

            axi_awlen_cntr <= axi_awlen_cntr + 1;

            case (axi_awburst)
            2'b00: // fixed burst
            // The write address for all the beats in the transaction are fixed
                begin
                axi_awaddr <= axi_awaddr;          
                //for awsize = 4 bytes (010)
                end   
            2'b01: //incremental burst
            // The write address for all the beats in the transaction are increments by awsize
                begin
                axi_awaddr[AVX_ADDR_BITS-1:ADDR_LSB] <= axi_awaddr[AVX_ADDR_BITS-1:ADDR_LSB] + 1;
                axi_awaddr[ADDR_LSB-1:0]  <= {ADDR_LSB{1'b0}};   
                end   
            2'b10: //Wrapping burst
            // The write address wraps when the address reaches wrap boundary 
                if (aw_wrap_en)
                begin
                    axi_awaddr <= (axi_awaddr - aw_wrap_size); 
                end
                else 
                begin
                    axi_awaddr[AVX_ADDR_BITS-1:ADDR_LSB] <= axi_awaddr[AVX_ADDR_BITS-1:ADDR_LSB] + 1;
                    axi_awaddr[ADDR_LSB-1:0]  <= {ADDR_LSB{1'b0}}; 
                end                      
            default: //reserved (incremental burst for example)
                begin
                    axi_awaddr <= axi_awaddr[AVX_ADDR_BITS-1:ADDR_LSB] + 1;
                end
            endcase              
        end
    end 
end       

// wready 
always @( posedge aclk )
begin
    if ( aresetn == 1'b0 )
    begin
        axi_wready <= 1'b0;
    end 
    else
    begin    
        if ( ~axi_wready && s_axim_ctrl.wvalid && axi_awv_awr_flag)
        begin
            // slave can accept the write data
            axi_wready <= 1'b1;
        end
        //else if (~axi_awv_awr_flag)
        else if (s_axim_ctrl.wlast && axi_wready)
        begin
            axi_wready <= 1'b0;
        end
    end 
end       


// bvalid & bresp
always @( posedge aclk )
begin
    if ( aresetn == 1'b0 )
    begin
        axi_bvalid <= 0;
        axi_bresp <= 2'b0;
    end 
    else
    begin    
        if (axi_awv_awr_flag && axi_wready && s_axim_ctrl.wvalid && ~axi_bvalid && s_axim_ctrl.wlast )
        begin
            axi_bvalid <= 1'b1;
            axi_bresp  <= 2'b0; 
            // 'OKAY' response 
        end                   
        else
        begin
            if (s_axim_ctrl.bready && axi_bvalid) 
            //check if bready is asserted while bvalid is high) 
            //(there is a possibility that bready is always asserted high)   
            begin
                axi_bvalid <= 1'b0; 
            end  
        end
    end
    end   

// arready
always @( posedge aclk )
begin
    if ( aresetn == 1'b0 )
    begin
        axi_arready <= 1'b0;
        axi_arv_arr_flag <= 1'b0;
    end 
    else
    begin    
        if (~axi_arready && s_axim_ctrl.arvalid && ~axi_awv_awr_flag && ~axi_arv_arr_flag)
        begin
            axi_arready <= 1'b1;
            axi_arv_arr_flag <= 1'b1;
        end
        else if (axi_rvalid && s_axim_ctrl.rready && axi_arlen_cntr == axi_arlen)
        // preparing to accept next address after current read completion
        begin
            axi_arv_arr_flag  <= 1'b0;
        end
        else        
        begin
            axi_arready <= 1'b0;
        end
    end 
end       

// araddr
always @( posedge aclk )
begin
    if ( aresetn == 1'b0 )
    begin
        axi_araddr <= 0;
        axi_arlen_cntr <= 0;
        axi_arburst <= 0;
        axi_arlen <= 0;
        axi_rlast <= 1'b0;
    end 
    else
    begin    
        if (~axi_arready && s_axim_ctrl.arvalid && ~axi_arv_arr_flag)
        begin
            // address latching 
            axi_araddr <= s_axim_ctrl.araddr[AVX_ADDR_BITS-1:0]; 
            axi_arburst <= s_axim_ctrl.arburst; 
            axi_arlen <= s_axim_ctrl.arlen;     
            // start address of transfer
            axi_arlen_cntr <= 0;
            axi_rlast <= 1'b0;
        end   
        else if((axi_arlen_cntr <= axi_arlen) && axi_rvalid && s_axim_ctrl.rready)        
        begin
            
            axi_arlen_cntr <= axi_arlen_cntr + 1;
            axi_rlast <= 1'b0;
        
            case (axi_arburst)
            2'b00: // fixed burst
                // The read address for all the beats in the transaction are fixed
                begin
                    axi_araddr       <= axi_araddr;        
                end   
            2'b01: //incremental burst
            // The read address for all the beats in the transaction are increments by awsize
                begin
                    axi_araddr[AVX_ADDR_BITS-1:ADDR_LSB] <= axi_araddr[AVX_ADDR_BITS-1:ADDR_LSB] + 1; 
                    axi_araddr[ADDR_LSB-1:0]  <= {ADDR_LSB{1'b0}};   
                end   
            2'b10: //Wrapping burst
            // The read address wraps when the address reaches wrap boundary 
                if (ar_wrap_en) 
                begin
                    axi_araddr <= (axi_araddr - ar_wrap_size); 
                end
                else 
                begin
                axi_araddr[AVX_ADDR_BITS-1:ADDR_LSB] <= axi_araddr[AVX_ADDR_BITS-1:ADDR_LSB] + 1; 
                axi_araddr[ADDR_LSB-1:0]  <= {ADDR_LSB{1'b0}};   
                end                      
            default: //reserved (incremental burst for example)
                begin
                axi_araddr <= axi_araddr[AVX_ADDR_BITS-1:ADDR_LSB]+1;
                end
            endcase              
        end
        else if((axi_arlen_cntr == axi_arlen) && ~axi_rlast && axi_arv_arr_flag )   
        begin
            axi_rlast <= 1'b1;
        end          
        else if (s_axim_ctrl.rready)   
        begin
            axi_rlast <= 1'b0;
        end          
    end 
end       

// arvalid
always @( posedge aclk )
begin
    if ( aresetn == 1'b0 )
    begin
        axi_rvalid <= 0;
        axi_rresp  <= 0;
    end 
    else
    begin    
        if (axi_arv_arr_flag && ~axi_rvalid)
        begin
            axi_rvalid <= 1'b1;
            axi_rresp  <= 2'b0; 
            // 'OKAY' response
        end   
        else if (axi_rvalid && s_axim_ctrl.rready)
        begin
            axi_rvalid <= 1'b0;
        end            
    end
end    



endmodule