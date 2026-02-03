/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2021-2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

import lynxTypes::*;

/**
 * @brief Static layer control & status registers
 * 
 * These registers are used for controlling PR, reading host DMA (XDMA/QDMA) stats, and setting QDMA prefetch tags.
 * NOTE: This module is currently used for both XDMA platforms (UltraScale+) and QDMA platforms (Versal).
 * In the future, depending on the functionality supported by each platform, we may split this module into two.
 * For now, we keep it unified to reduce code duplication. The top-level modules (static_top) simply disable
 * certain features depending on the platform. e.g., on XDMA-based platforms, qdma_pfch_tag_valid is always tied to 0.
 */
module static_slave (
  // Clock, reset
  input  logic                    aclk,
  input  logic                    aresetn,
  
  // PR command containing physical address of bitstream on the host & its length 
  dmaIntf.m                       m_pr_dma_rd_req,

  // End-of-startup; signal indicating PR is completed
  input  logic                    eos,

  // Active low reset after PR completion
  output logic                    eos_resetn,

  // Time to wait after PR before asserting eos (only applicable to UltraScale+ platforms where ICAP completions aren't reliable)
  output logic [31:0]             eos_time,

  // Interrupt raised to the host after PR completion (i.e. once eos is asserted)
  output logic                    pr_irq,

  // Host DMA statistics 
  input  hdma_stat_t              s_hdma_stats,

  // When set, applies decoupling to the shell interfaces (i.e. all valid signals are deasserted)
  output logic                    decouple,

  // QDMA C2H prefetch tag; only applicable to Versal/QDMA platforms
  output logic                    qdma_pfch_tag_valid,
  output logic [11:0]             qdma_pfch_tag_qid,
  output logic [6:0]              qdma_pfch_tag,

  // Control bus (HOST)
  AXI4L.s                         s_axi_ctrl
);

// ---------------------------------------------------------------------------------------- 
// Declarations 
// ----------------------------------------------------------------------------------------

// Constants
localparam integer N_REGS = 32;
localparam integer AXIL_INT_DATA_BITS = 32;
localparam integer ADDR_LSB = $clog2(AXIL_INT_DATA_BITS/8);
localparam integer ADDR_MSB = $clog2(N_REGS);
localparam integer AXIL_ADDR_BITS = ADDR_LSB + ADDR_MSB;

// AXI registers
logic [AXIL_ADDR_BITS-1:0] axi_awaddr;
logic axi_awready;
logic [AXIL_ADDR_BITS-1:0] axi_araddr;
logic axi_arready;
logic [1:0] axi_bresp;
logic axi_bvalid;
logic axi_wready;
logic [AXIL_INT_DATA_BITS-1:0] axi_rdata;
logic [1:0] axi_rresp;
logic axi_rvalid;

// Control registers
logic [N_REGS-1:0][AXIL_INT_DATA_BITS-1:0] slv_reg;
logic slv_reg_rden;
logic slv_reg_wren;
logic aw_en;

// PR descriptor
dmaIntf pr_req ();
logic [31:0] pr_used;

// -- Register map ----------------------------------------------------------------------- 
// 0 (RO) : Static layer probe
localparam integer PROBE_REG          = 0;
// 1 (W1S) : PR control
localparam integer PR_CTRL_REG        = 1;
  localparam integer PR_START  = 0;     // PR Descriptor valid
  localparam integer PR_CTL    = 1;     // Set for last PR descriptor
  localparam integer PR_CLR    = 2;     // Clear done status (which deasserts pr_irq)
// 2 (RO) : PR Status
localparam integer PR_STAT_REG        = 2;
  localparam integer PR_DONE   = 0;     // PR completed
  localparam integer PR_READY  = 1;     // Descriptor queue ready signal
// 3 (RO) : Total number of reconfigurations completed
localparam integer PR_CNT_REG         = 3;
// 4-5 (RW) : Physical address
localparam integer PR_ADDR_LOW_REG    = 4;
localparam integer PR_ADDR_HIGH_REG   = 5;
// 6 (RW) : Length read
localparam integer PR_LEN_REG         = 6;
// 7 (RW) : EOST reg
localparam integer PR_EOST_REG        = 7;
// 8 (RW) : EOST reset
localparam integer PR_EOST_RESET_REG  = 8;
// 9-10 (RW) : Decouple set, clear
localparam integer PR_DCPL_REG_SET    = 9;
localparam integer PR_DCPL_REG_CLR    = 10;
// 11-16 (RO) : Host DMA statistics from/to the static layer
localparam integer HDMA_STAT_BPSS_RD  = 11;
localparam integer HDMA_STAT_BPSS_WR  = 12;
localparam integer HDMA_STAT_CMPL_RD  = 13;
localparam integer HDMA_STAT_CMPL_WR  = 14;
localparam integer HDMA_STAT_AXIS_RD  = 15;
localparam integer HDMA_STAT_AXIS_WR  = 16;
// 17 (RW): QDMA prefetch tag 
localparam integer QDMA_PFCH_TAG_REG  = 17;

// ---------------------------------------------------------------------------------------- 
// Write process 
// ----------------------------------------------------------------------------------------
assign slv_reg_wren = axi_wready && s_axi_ctrl.wvalid && axi_awready && s_axi_ctrl.awvalid;

always_ff @(posedge aclk) begin
  if (aresetn == 1'b0) begin
    slv_reg <= 'X;

    slv_reg[PR_CTRL_REG][31:0] <= 0;
    slv_reg[PR_STAT_REG][31:0] <= 0;
    slv_reg[PR_CNT_REG] <= 0;
    slv_reg[PR_EOST_REG] <= RECONFIG_EOS_TIME;
    slv_reg[PR_DCPL_REG_SET][0] <= 1'b0;
    slv_reg[PR_EOST_RESET_REG][0] <= 1'b1;

    pr_irq <= 1'b0;
  
    slv_reg[QDMA_PFCH_TAG_REG][31:0] <= 0;

  end else begin
    slv_reg[PR_CTRL_REG][31:0] <= 0;
    slv_reg[PR_STAT_REG][PR_DONE] <= slv_reg[PR_CTRL_REG][PR_CLR] ? 1'b0 : eos ? 1'b1 : slv_reg[PR_STAT_REG][PR_DONE];

    slv_reg[PR_CNT_REG] <= eos ? slv_reg[PR_CNT_REG] + 1 : slv_reg[PR_CNT_REG];

    pr_irq <= slv_reg[PR_STAT_REG][PR_DONE];

    if (slv_reg_wren) begin
      case (axi_awaddr[ADDR_LSB+:ADDR_MSB])
        PR_CTRL_REG:
          for (int i = 0; i < AXIL_INT_DATA_BITS/8; i++) begin
            if (s_axi_ctrl.wstrb[i]) begin
              slv_reg[PR_CTRL_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        PR_ADDR_LOW_REG: 
          for (int i = 0; i < AXIL_INT_DATA_BITS/8; i++) begin
            if (s_axi_ctrl.wstrb[i]) begin
              slv_reg[PR_ADDR_LOW_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        PR_ADDR_HIGH_REG: 
          for (int i = 0; i < AXIL_INT_DATA_BITS/8; i++) begin
            if (s_axi_ctrl.wstrb[i]) begin
              slv_reg[PR_ADDR_HIGH_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        PR_LEN_REG: 
          for (int i = 0; i < AXIL_INT_DATA_BITS/8; i++) begin
            if (s_axi_ctrl.wstrb[i]) begin
              slv_reg[PR_LEN_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        PR_EOST_REG:
          for (int i = 0; i < AXIL_INT_DATA_BITS/8; i++) begin
            if (s_axi_ctrl.wstrb[i]) begin
              slv_reg[PR_EOST_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        PR_EOST_RESET_REG: 
          for (int i = 0; i < AXIL_INT_DATA_BITS/8; i++) begin
            if (s_axi_ctrl.wstrb[i]) begin
              slv_reg[PR_EOST_RESET_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        PR_DCPL_REG_SET:
          for (int i = 0; i < AXIL_INT_DATA_BITS/8; i++) begin
            if (s_axi_ctrl.wstrb[i]) begin
              slv_reg[PR_DCPL_REG_SET][(i*8)+:8] <= slv_reg[PR_DCPL_REG_SET][(i*8)+:8] | s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        PR_DCPL_REG_CLR: 
          for (int i = 0; i < AXIL_INT_DATA_BITS/8; i++) begin
            if (s_axi_ctrl.wstrb[i]) begin
              slv_reg[PR_DCPL_REG_SET][(i*8)+:8] <= slv_reg[PR_DCPL_REG_SET][(i*8)+:8] & ~s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        QDMA_PFCH_TAG_REG: 
          for (int i = 0; i < AXIL_INT_DATA_BITS/8; i++) begin
            if (s_axi_ctrl.wstrb[i]) begin
              slv_reg[QDMA_PFCH_TAG_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        
        default : ;
      endcase
    end
  end
end    

// ---------------------------------------------------------------------------------------- 
// Read process 
// ----------------------------------------------------------------------------------------
assign slv_reg_rden = axi_arready & s_axi_ctrl.arvalid & ~axi_rvalid;

always_ff @(posedge aclk) begin
  if (aresetn == 1'b0) begin
    axi_rdata <= 'X;
  end else begin
    if (slv_reg_rden) begin
      axi_rdata <= 0;
      
      case (axi_araddr[ADDR_LSB+:ADDR_MSB])
        PROBE_REG:
          axi_rdata <= STAT_PROBE;
        PR_CTRL_REG:
          axi_rdata <= pr_used;
        PR_STAT_REG:
          axi_rdata[1:0] <= {pr_req.ready, slv_reg[PR_STAT_REG][PR_DONE]};
        PR_CNT_REG:
          axi_rdata <= slv_reg[PR_CNT_REG];
        PR_ADDR_LOW_REG:
          axi_rdata <= slv_reg[PR_ADDR_LOW_REG];
        PR_ADDR_HIGH_REG:
          axi_rdata <= slv_reg[PR_ADDR_HIGH_REG];
        PR_LEN_REG:
          axi_rdata <= slv_reg[PR_LEN_REG];
        PR_EOST_REG:
          axi_rdata <= slv_reg[PR_EOST_REG];

        HDMA_STAT_BPSS_RD: 
          axi_rdata <= s_hdma_stats.bpss_h2c_req_counter;
        HDMA_STAT_BPSS_WR:
          axi_rdata <= s_hdma_stats.bpss_c2h_req_counter;
        HDMA_STAT_CMPL_RD: 
          axi_rdata <= s_hdma_stats.bpss_h2c_cmpl_counter;
        HDMA_STAT_CMPL_WR:
          axi_rdata <= s_hdma_stats.bpss_c2h_cmpl_counter;
        HDMA_STAT_AXIS_RD:
          axi_rdata <= s_hdma_stats.bpss_h2c_axis_counter;
        HDMA_STAT_AXIS_WR:
          axi_rdata <= s_hdma_stats.bpss_c2h_axis_counter;  

        QDMA_PFCH_TAG_REG:
          axi_rdata <= slv_reg[QDMA_PFCH_TAG_REG];            

        default: ;
      endcase
    end
  end 
end

// ---------------------------------------------------------------------------------------- 
// Output
// ----------------------------------------------------------------------------------------

// PR
always_comb begin
  // Decoupling
  decouple = slv_reg[PR_DCPL_REG_SET][0];

  // PR request
  pr_req.valid = slv_reg[PR_CTRL_REG][PR_START];
  pr_req.req = 0;
  pr_req.req.last = slv_reg[PR_CTRL_REG][PR_CTL];
  pr_req.req.paddr[31:0] = slv_reg[PR_ADDR_LOW_REG];
  pr_req.req.paddr[PADDR_BITS-1:32] = slv_reg[PR_ADDR_HIGH_REG];
  pr_req.req.len = slv_reg[PR_LEN_REG][LEN_BITS-1:0];
  
  // EOS time
  eos_time = slv_reg[PR_EOST_REG][31:0];

  // EOS reset
  eos_resetn = slv_reg[PR_EOST_RESET_REG][0];

  // QDMA prefetch tag
  qdma_pfch_tag = slv_reg[QDMA_PFCH_TAG_REG][6:0];
  qdma_pfch_tag_qid = slv_reg[QDMA_PFCH_TAG_REG][19:8];
  qdma_pfch_tag_valid = slv_reg[QDMA_PFCH_TAG_REG][31];
end

// DMA out
axis_data_fifo_static_slave inst_pr_fifo (
    .s_axis_aclk(aclk),
    .s_axis_aresetn(aresetn),
    .s_axis_tdata(pr_req.req),
    .s_axis_tvalid(pr_req.valid),
    .s_axis_tready(pr_req.ready),
    .m_axis_tdata(m_pr_dma_rd_req.req),
    .m_axis_tvalid(m_pr_dma_rd_req.valid),
    .m_axis_tready(m_pr_dma_rd_req.ready),
    .axis_wr_data_count(pr_used)
);

// ---------------------------------------------------------------------------------------- 
// AXI
// ----------------------------------------------------------------------------------------

// I/O
assign s_axi_ctrl.awready = axi_awready;
assign s_axi_ctrl.arready = axi_arready;
assign s_axi_ctrl.bresp = axi_bresp;
assign s_axi_ctrl.bvalid = axi_bvalid;
assign s_axi_ctrl.wready = axi_wready;
assign s_axi_ctrl.rdata = axi_rdata;
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

// rvalid and rresp
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