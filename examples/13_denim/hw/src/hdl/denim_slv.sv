/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2026, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

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
 * @brief   DENIM control register slave
 *
 * Bridges the host's setCSR/getCSR to the DENIM datapath, which lives in the
 * network clock domain. Writes are forwarded as {addr, data} beats on the
 * config channel. Reads are served from a shadow of the register file that
 * DENIM streams back continuously.
 */
module denim_slv (
  input  logic                        aclk,
  input  logic                        aresetn,

  AXI4L.s                             axi_ctrl,

  /* To the DENIM datapath, crossed to nclk in network_top */
  metaIntf.m                          denim_cnfg,
  metaIntf.s                          denim_stat
);

// -- Decl ----------------------------------------------------------
// ------------------------------------------------------------------
// 8 global registers plus 8 slots of 8. Sized from the same numbers as
// denim_pkg.
localparam integer N_RULES_L = 8;
localparam integer N_REGS    = 8 + N_RULES_L * 8;
localparam integer ADDR_LSB  = $clog2(AXIL_DATA_BITS/8);
localparam integer ADDR_MSB  = $clog2(N_REGS);
localparam integer AXI_ADDR_BITS = ADDR_LSB + ADDR_MSB;

localparam integer REG_SLV_STATUS = 7;

// Internal registers
logic [AXI_ADDR_BITS-1:0] axi_awaddr;
logic axi_awready;
logic [AXI_ADDR_BITS-1:0] axi_araddr;
logic axi_arready;
logic [1:0] axi_bresp;
logic axi_bvalid;
logic axi_wready;
logic [AXIL_DATA_BITS-1:0] axi_rdata;
logic [1:0] axi_rresp;
logic axi_rvalid;

logic slv_reg_rden;
logic slv_reg_wren;
logic aw_en;


/**
 * Config writes
 */
logic [71:0] cfg_data_r;
logic        cfg_valid_r;
logic        cfg_lost;
logic        cfg_partial;
logic        wr_pending;
logic        cfg_wr;

assign slv_reg_wren = axi_wready && axi_ctrl.wvalid && axi_awready && axi_ctrl.awvalid;

// A write beat leaves only for a write that actually carries bytes.
assign cfg_wr = slv_reg_wren && (|axi_ctrl.wstrb);

// One config beat per completed write transaction, gated on wr_pending.
always_ff @(posedge aclk) begin
  if (aresetn == 1'b0) begin
    cfg_data_r  <= '0;
    cfg_valid_r <= 1'b0;
    cfg_lost    <= 1'b0;
    cfg_partial <= 1'b0;
    wr_pending  <= 1'b0;
  end
  else begin
    if (denim_cnfg.valid && denim_cnfg.ready) begin
      cfg_valid_r <= 1'b0;
    end

    // A whole word crosses at a time, so a partial write cannot be honoured.
    if (cfg_wr && !(&axi_ctrl.wstrb)) begin
      cfg_partial <= 1'b1;
    end

    if (cfg_wr && !wr_pending) begin
      if (cfg_valid_r && !(denim_cnfg.valid && denim_cnfg.ready)) begin
        cfg_lost <= 1'b1;
      end
      else begin
        cfg_data_r  <= {axi_awaddr[ADDR_LSB+:ADDR_MSB], axi_ctrl.wdata};
        cfg_valid_r <= 1'b1;
      end
      wr_pending <= 1'b1;
    end

    if (!axi_ctrl.awvalid) begin
      wr_pending <= 1'b0;
    end
  end
end

assign denim_cnfg.data  = cfg_data_r;
assign denim_cnfg.valid = cfg_valid_r;

/**
 * Register mirror
 */
// DENIM walks its whole register file onto this channel continuously, so the
// shadow converges within one pass and a dropped beat heals on the next.
logic [AXIL_DATA_BITS-1:0] shadow [N_REGS];

assign denim_stat.ready = 1'b1;

always_ff @(posedge aclk) begin
  if (aresetn == 1'b0) begin
    for (int i = 0; i < N_REGS; i++) shadow[i] <= '0;
  end
  else if (denim_stat.valid && denim_stat.ready) begin
    if (denim_stat.data[71:64] < N_REGS) begin
      shadow[denim_stat.data[71:64]] <= denim_stat.data[63:0];
    end
  end
end

/**
 * Reads
 */
assign slv_reg_rden = axi_arready & axi_ctrl.arvalid & ~axi_rvalid;

always_ff @(posedge aclk) begin
  if (aresetn == 1'b0) begin
    axi_rdata <= 0;
  end
  else begin
    if (slv_reg_rden) begin
      if (axi_araddr[ADDR_LSB+:ADDR_MSB] == REG_SLV_STATUS[ADDR_MSB-1:0]) begin
        axi_rdata <= {62'd0, cfg_partial, cfg_lost};
      end
      else begin
        axi_rdata <= shadow[axi_araddr[ADDR_LSB+:ADDR_MSB]];
      end
    end
  end
end

// AXI CTRL  
// Don't edit

// I/O
assign axi_ctrl.awready = axi_awready;
assign axi_ctrl.arready = axi_arready;
assign axi_ctrl.bresp = axi_bresp;
assign axi_ctrl.bvalid = axi_bvalid;
assign axi_ctrl.wready = axi_wready;
assign axi_ctrl.rdata = axi_rdata;
assign axi_ctrl.rresp = axi_rresp;
assign axi_ctrl.rvalid = axi_rvalid;

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
      if (~axi_awready && axi_ctrl.awvalid && axi_ctrl.wvalid && aw_en)
        begin
          axi_awready <= 1'b1;
          aw_en <= 1'b0;
          axi_awaddr <= axi_ctrl.awaddr;
        end
      else if (axi_ctrl.bready && axi_bvalid)
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
      if (~axi_arready && axi_ctrl.arvalid)
        begin
          axi_arready <= 1'b1;
          axi_araddr  <= axi_ctrl.araddr;
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
      if (axi_awready && axi_ctrl.awvalid && ~axi_bvalid && axi_wready && axi_ctrl.wvalid)
        begin
          axi_bvalid <= 1'b1;
          axi_bresp  <= 2'b0;
        end                   
      else
        begin
          if (axi_ctrl.bready && axi_bvalid) 
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
      if (~axi_wready && axi_ctrl.wvalid && axi_ctrl.awvalid && aw_en )
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
      if (axi_arready && axi_ctrl.arvalid && ~axi_rvalid)
        begin
          axi_rvalid <= 1'b1;
          axi_rresp  <= 2'b0;
        end   
      else if (axi_rvalid && axi_ctrl.rready)
        begin
          axi_rvalid <= 1'b0;
        end                
    end
end    

endmodule
