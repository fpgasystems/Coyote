/**
 *  GBM slave
 */ 
import lynxTypes::*;

module gbm_slave #(
  parameter integer NFEAUTRES_BITS = 16,
  parameter integer TREEDEPTH_BITS = 8,
  parameter integer PUTREES_BITS = 8,
  parameter integer OUTNUMCLS_BITS = 32,
  parameter integer LSTOUTMASK_BITS = 16
) (
  input  logic                        aclk,
  input  logic                        aresetn,
  
  AXI4L.s                             axi_ctrl,

  // User defined arguments
  output logic                        ap_start,
  output logic [NFEAUTRES_BITS-1:0]   numFeatures,
  output logic [TREEDEPTH_BITS-1:0]   treeDepth,
  output logic [PUTREES_BITS-1:0]     puTrees,
  output logic [OUTNUMCLS_BITS-1:0]   outputNumCLs,
  output logic [LSTOUTMASK_BITS-1:0]  lastOutLineMask
);

// -- Decl ----------------------------------------------------------
// ------------------------------------------------------------------
// Constants
localparam integer N_REGS = 6;
localparam integer ADDR_LSB = $clog2(AXIL_DATA_BITS/8);
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
// 0 (W1S)  : AP start (
localparam integer AP_CTRL_REG = 0;
//                0 - start 
// 1 (WR)   : Number of features
localparam integer NFEAUTERS_REG = 1;
// 2 (WR)   : Treedepth
localparam integer TREEDEPTH_REG = 2;
// 3 (WR)   : Putrees
localparam integer PUTREES_REG = 3;
// 4 (WR)   : OutputNumCLs
localparam integer OUTNUMCLS_REG = 4;
// 5 (WR)   : LastOutLineMask
localparam integer LSTOUTMASK_REG = 5;

// Write process
assign slv_reg_wren = axi_wready && axi_ctrl.wvalid && axi_awready && axi_ctrl.awvalid;

always_ff @(posedge aclk) begin
  if ( aresetn == 1'b0 ) begin
    slv_reg <= 0;
  end
  else begin
    // Control
    slv_reg[AP_CTRL_REG] <= 0;

    if(slv_reg_wren) begin
      case (axi_awaddr[ADDR_LSB+:ADDR_MSB])
        AP_CTRL_REG:  // Control
          for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[AP_CTRL_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        NFEAUTERS_REG: // Number of features
          for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[NFEAUTERS_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        TREEDEPTH_REG: // Treedepth
          for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[TREEDEPTH_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        PUTREES_REG: // Putrees
          for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[PUTREES_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        OUTNUMCLS_REG: // Output number of CLs
          for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[OUTNUMCLS_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        LSTOUTMASK_REG: // Last out line mask
          for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[LSTOUTMASK_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
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
        NFEAUTERS_REG: // Key low
          axi_rdata[NFEAUTRES_BITS-1:0] <= slv_reg[NFEAUTERS_REG][NFEAUTRES_BITS-1:0];
        TREEDEPTH_REG: // Key high
          axi_rdata[TREEDEPTH_BITS-1:0] <= slv_reg[TREEDEPTH_REG][TREEDEPTH_BITS-1:0];
        PUTREES_REG: // Key high
          axi_rdata[PUTREES_BITS-1:0] <= slv_reg[PUTREES_REG][PUTREES_BITS-1:0];
        OUTNUMCLS_REG: // Key high
          axi_rdata[OUTNUMCLS_BITS-1:0] <= slv_reg[OUTNUMCLS_REG][OUTNUMCLS_BITS-1:0];
        LSTOUTMASK_REG: // Key high
          axi_rdata[LSTOUTMASK_BITS-1:0] <= slv_reg[LSTOUTMASK_REG][LSTOUTMASK_BITS-1:0];
        default: ;
      endcase
    end
  end 
end

// Output
always_comb begin
  ap_start        = slv_reg[AP_CTRL_REG][0];
  numFeatures     = slv_reg[NFEAUTERS_REG][15:0];
  treeDepth       = slv_reg[TREEDEPTH_REG][7:0];
  puTrees         = slv_reg[PUTREES_REG][7:0];
  outputNumCLs    = slv_reg[OUTNUMCLS_REG][31:0];
  lastOutLineMask = slv_reg[LSTOUTMASK_REG][15:0];
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

endmodule // gbm slave