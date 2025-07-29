/*
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025, Systems Group, ETH Zurich
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

/**
 *  Packet Sniifer slave
 */ 
import lynxTypes::*;

module packet_sniffer_slv (
  input  logic                        aclk,
  input  logic                        aresetn,
  
  AXI4L.s                             axi_ctrl,

  output logic [0:0]                  sniffer_ctrl_0,
  output logic [0:0]                  sniffer_ctrl_1,
  output logic [63:0]                 sniffer_ctrl_filter,
  input  logic [1:0]                  sniffer_state,
  input  logic [31:0]                 sniffer_size,
  input  logic [63:0]                 sniffer_timer,
  output logic [VADDR_BITS-1:0]       sniffer_host_vaddr,
  output logic [LEN_BITS-1:0]         sniffer_host_len,
  output logic [PID_BITS-1:0]         sniffer_host_pid,
  output logic [DEST_BITS-1:0]        sniffer_host_dest
);

// -- Decl ----------------------------------------------------------
// ------------------------------------------------------------------
// Constants
localparam integer N_REGS = 10;
localparam integer ADDR_LSB = $clog2(AXIL_DATA_BITS/8);
localparam integer ADDR_MSB = $clog2(N_REGS);
localparam integer AXI_ADDR_BITS = ADDR_LSB + ADDR_MSB;

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

// Registers
logic [N_REGS-1:0][AXIL_DATA_BITS-1:0] slv_reg;
logic slv_reg_rden;
logic slv_reg_wren;
logic aw_en;

// -- Def -----------------------------------------------------------
// ------------------------------------------------------------------

// -- Register map ----------------------------------------------------------------------- 
// 0 (WR)   : Ctrl reg to start/end sniffering
localparam integer SNIFFER_CTRL_REG_0 = 0;
// 1 (WR)   : Ctrl reg to indicate valid host memory information
localparam integer SNIFFER_CTRL_REG_1 = 1;
// 2 (WR)   : Ctrl reg to set sniffer filter
localparam integer SNIFFER_FILTER_REG = 2;
// 3 (RO)   : Current state of sniffer
localparam integer SNIFFER_STATE_REG  = 3;
// 4 (RO)   : Size of captured packets
localparam integer SNIFFER_SIZE_REG   = 4;
// 5 (RO)   : Internal Timer
localparam integer SNIFFER_TIMER_REG  = 5;
// 6 (WR)   : Vaddr
localparam integer SNIFFER_VADDR_REG  = 6;
// 7 (WR)   : Length
localparam integer SNIFFER_LEN_REG    = 7;
// 8 (WR)   : Pid
localparam integer SNIFFER_PID_REG    = 8;
// 9 (WR)   : Dest
localparam integer SNIFFER_DEST_REG   = 9;

// Write process
assign slv_reg_wren = axi_wready && axi_ctrl.wvalid && axi_awready && axi_ctrl.awvalid;

always_ff @(posedge aclk) begin
  if ( aresetn == 1'b0 ) begin
    slv_reg <= 0;
  end
  else begin
    // Control
    if(slv_reg_wren) begin
      case (axi_awaddr[ADDR_LSB+:ADDR_MSB])
        SNIFFER_CTRL_REG_0:  // Control 0
          for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[SNIFFER_CTRL_REG_0][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        SNIFFER_CTRL_REG_1:  // Control 1
          for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[SNIFFER_CTRL_REG_1][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        SNIFFER_FILTER_REG:  // Filter config
          for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[SNIFFER_FILTER_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        SNIFFER_VADDR_REG: // Vaddr
          for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[SNIFFER_VADDR_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        SNIFFER_LEN_REG: // Length
          for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[SNIFFER_LEN_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        SNIFFER_PID_REG: // PID
          for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[SNIFFER_PID_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        SNIFFER_DEST_REG: // DEST 
          for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[SNIFFER_DEST_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        default : ;
      endcase
    end
  end
end    

// Read process
assign slv_reg_rden = axi_arready & axi_ctrl.arvalid & ~axi_rvalid;

always_ff @(posedge aclk) begin
  if( aresetn == 1'b0 ) begin
    axi_rdata <= 0;
  end
  else begin
    if(slv_reg_rden) begin
      axi_rdata <= 0;

      case (axi_araddr[ADDR_LSB+:ADDR_MSB])
        SNIFFER_CTRL_REG_0:
          axi_rdata[0:0] <= slv_reg[SNIFFER_CTRL_REG_0][0:0];
        SNIFFER_CTRL_REG_1:
          axi_rdata[0:0] <= slv_reg[SNIFFER_CTRL_REG_1][0:0];
        SNIFFER_FILTER_REG:
          axi_rdata[63:0] <= slv_reg[SNIFFER_FILTER_REG][63:0];
        SNIFFER_STATE_REG:
          axi_rdata[1:0] <= sniffer_state;
        SNIFFER_SIZE_REG:
          axi_rdata[31:0] <= sniffer_size;
        SNIFFER_TIMER_REG:
          axi_rdata[63:0] <= sniffer_timer;
        SNIFFER_VADDR_REG:
          axi_rdata[VADDR_BITS-1:0] <= slv_reg[SNIFFER_VADDR_REG][VADDR_BITS-1:0];
        SNIFFER_LEN_REG:
          axi_rdata[LEN_BITS-1:0] <= slv_reg[SNIFFER_LEN_REG][LEN_BITS-1:0];
        SNIFFER_PID_REG:
          axi_rdata[PID_BITS-1:0] <= slv_reg[SNIFFER_PID_REG][PID_BITS-1:0];
        SNIFFER_DEST_REG:
          axi_rdata[DEST_BITS-1:0] <= slv_reg[SNIFFER_DEST_REG][DEST_BITS-1:0];
        default: ;
      endcase
    end
  end 
end

// Output
always_comb begin
  sniffer_ctrl_0       = slv_reg[SNIFFER_CTRL_REG_0][1:0];
  sniffer_ctrl_1       = slv_reg[SNIFFER_CTRL_REG_1][1:0];
  sniffer_ctrl_filter  = slv_reg[SNIFFER_FILTER_REG][63:0];
  sniffer_host_vaddr   = slv_reg[SNIFFER_VADDR_REG][VADDR_BITS-1:0];
  sniffer_host_len     = slv_reg[SNIFFER_LEN_REG][LEN_BITS-1:0];
  sniffer_host_pid     = slv_reg[SNIFFER_PID_REG][PID_BITS-1:0];
  sniffer_host_dest    = slv_reg[SNIFFER_DEST_REG][DEST_BITS-1:0];
end


// --------------------------------------------------------------------------------------
// AXI CTRL  
// -------------------------------------------------------------------------------------- 
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

// rvalid and rresp (1Del?)
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

endmodule // perf_fpga slave