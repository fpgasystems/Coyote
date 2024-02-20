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

module static_slave (
  input  logic                    aclk,
  input  logic                    aresetn,
  
  // DMA 
  dmaIntf.m                       m_pr_dma_rd_req,

  // PR
  output logic                    eos_resetn,
  input  logic                    eos,
  output logic [31:0]             eos_time,
  output logic                    pr_irq,

  // Stats
  input  xdma_stat_t              s_xdma_stats,

  // Decouple
  output logic                    decouple,

  // Control bus (HOST)
  AXI4L.s                         s_axi_ctrl
);

// -- Decl ----------------------------------------------------------
// ------------------------------------------------------------------

// Constants
localparam integer AXIL_INT_DATA_BITS = 32;
localparam integer N_REGS = 32;
localparam integer ADDR_LSB = $clog2(AXIL_INT_DATA_BITS/8);
localparam integer ADDR_MSB = $clog2(N_REGS);
localparam integer AXIL_ADDR_BITS = ADDR_LSB + ADDR_MSB;

// Internal registers
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

// Registers
logic [N_REGS-1:0][AXIL_INT_DATA_BITS-1:0] slv_reg;
logic slv_reg_rden;
logic slv_reg_wren;
logic aw_en;

dmaIntf pr_req ();
logic [31:0] pr_used;

// -- Def -----------------------------------------------------------
// ------------------------------------------------------------------

// -- Register map ----------------------------------------------------------------------- 
// CONFIG
// 0 (RW) : Probe
localparam integer PROBE_REG          = 0;
// 1 (W1S) : PR control
localparam integer PR_CTRL_REG        = 1;
  localparam integer PR_START  = 0;
  localparam integer PR_CTL    = 1;
  localparam integer PR_CLR    = 2;
// 2 (RO) : Status
localparam integer PR_STAT_REG        = 2;
  localparam integer PR_DONE   = 0;
  localparam integer PR_DDMA   = 1;
  localparam integer PR_READY  = 2;
// 3 (RO) : Counter
localparam integer PR_CNT_REG         = 3;
// 4 (RW) : Physical address
localparam integer PR_ADDR_LOW_REG    = 4;
localparam integer PR_ADDR_HIGH_REG   = 5;
// 6 (RW) : Length read
localparam integer PR_LEN_REG         = 6;
// 7 (RW) : EOST reg
localparam integer PR_EOST_REG        = 7;
// 8 (RW) : EOST reset
localparam integer PR_EOST_RESET_REG  = 8;
// 8-9 (RW) : Decouple
localparam integer PR_DCPL_REG_SET    = 9;
localparam integer PR_DCPL_REG_CLR    = 10;
// Stats
localparam integer XDMA_STAT_BPSS_RD  = 11;
localparam integer XDMA_STAT_BPSS_WR  = 12;
localparam integer XDMA_STAT_CMPL_RD  = 13;
localparam integer XDMA_STAT_CMPL_WR  = 14;
localparam integer XDMA_STAT_AXIS_RD  = 15;
localparam integer XDMA_STAT_AXIS_WR  = 16;

// ---------------------------------------------------------------------------------------- 
// Write process 
// ----------------------------------------------------------------------------------------
assign slv_reg_wren = axi_wready && s_axi_ctrl.wvalid && axi_awready && s_axi_ctrl.awvalid;

always_ff @(posedge aclk) begin
  if ( aresetn == 1'b0 ) begin
    slv_reg <= 'X;

    slv_reg[PR_CTRL_REG][31:0] <= 0;
    slv_reg[PR_STAT_REG][31:0] <= 0;
    slv_reg[PR_CNT_REG] <= 0;
    slv_reg[PR_EOST_REG] <= RECONFIG_EOS_TIME;
    slv_reg[PR_DCPL_REG_SET][0] <= 1'b0;
    slv_reg[PR_EOST_RESET_REG][0] <= 1'b1;

    pr_irq <= 1'b0;
  end
  else begin
    slv_reg[PR_CTRL_REG][31:0] <= 0;
    slv_reg[PR_STAT_REG][PR_DONE] <= slv_reg[PR_CTRL_REG][PR_CLR] ? 1'b0 : pr_req.rsp.done ? 1'b1 : slv_reg[PR_STAT_REG][PR_DONE];
    slv_reg[PR_STAT_REG][PR_DDMA] <= slv_reg[PR_CTRL_REG][PR_CLR] ? 1'b0 : m_pr_dma_rd_req.rsp.done ? 1'b1 : slv_reg[PR_STAT_REG][PR_DDMA];

    slv_reg[PR_CNT_REG] <= pr_req.rsp.done ? slv_reg[PR_CNT_REG] + 1 : slv_reg[PR_CNT_REG];

    pr_irq <= slv_reg[PR_STAT_REG][PR_DONE];

    if(slv_reg_wren) begin
      case (axi_awaddr[ADDR_LSB+:ADDR_MSB])
        PR_CTRL_REG: // PR control
          for (int i = 0; i < 2; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[PR_CTRL_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        PR_ADDR_LOW_REG: // PR address
          for (int i = 0; i < AXIL_INT_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[PR_ADDR_LOW_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        PR_ADDR_HIGH_REG: // PR address
          for (int i = 0; i < AXIL_INT_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[PR_ADDR_HIGH_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        PR_LEN_REG: // PR length
          for (int i = 0; i < AXIL_INT_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[PR_LEN_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        PR_EOST_REG: // PR eost
          for (int i = 0; i < AXIL_INT_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[PR_EOST_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        PR_EOST_RESET_REG: // PR reset
          for (int i = 0; i < AXIL_INT_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[PR_EOST_RESET_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        PR_DCPL_REG_SET: // Decouple
          for (int i = 0; i < AXIL_INT_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[PR_DCPL_REG_SET][(i*8)+:8] <= slv_reg[PR_DCPL_REG_SET][(i*8)+:8] | s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        PR_DCPL_REG_CLR: // Decouple
          for (int i = 0; i < AXIL_INT_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[PR_DCPL_REG_SET][(i*8)+:8] <= slv_reg[PR_DCPL_REG_SET][(i*8)+:8] & ~s_axi_ctrl.wdata[(i*8)+:8];
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
  if( aresetn == 1'b0 ) begin
    axi_rdata <= 'X;
  end
  else begin
    if(slv_reg_rden) begin
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
          axi_rdata[31:0] <= slv_reg[PR_LEN_REG][31:0];
        PR_EOST_REG:
          axi_rdata <= slv_reg[PR_EOST_REG];

        XDMA_STAT_BPSS_RD: // bpss
            axi_rdata <= s_xdma_stats.bpss_h2c_req_counter;
        XDMA_STAT_BPSS_WR: // bpss
            axi_rdata <= s_xdma_stats.bpss_c2h_req_counter;
        XDMA_STAT_CMPL_RD: // cmpl
            axi_rdata <= s_xdma_stats.bpss_h2c_cmpl_counter;
        XDMA_STAT_CMPL_WR: // cmpl
            axi_rdata <= s_xdma_stats.bpss_c2h_cmpl_counter;
        XDMA_STAT_AXIS_RD: // data
            axi_rdata <= s_xdma_stats.bpss_h2c_axis_counter;
        XDMA_STAT_AXIS_WR: // data
            axi_rdata <= s_xdma_stats.bpss_c2h_axis_counter;            

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
  pr_req.req.paddr[32-1:0] = slv_reg[PR_ADDR_LOW_REG];
  pr_req.req.paddr[PADDR_BITS-1:32] = slv_reg[PR_ADDR_HIGH_REG][7:0];
  pr_req.req.len = slv_reg[PR_LEN_REG][LEN_BITS-1:0];
  // Done signal
  pr_req.rsp.done = eos;
  
  // EOS time
  eos_time = slv_reg[PR_EOST_REG][31:0];

  // EOS reset
  eos_resetn = slv_reg[PR_EOST_RESET_REG][0];
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

endmodule // static_slave