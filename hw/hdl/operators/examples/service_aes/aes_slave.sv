import lynxTypes::*;

module aes_slave (
  input  logic              aclk,
  input  logic              aresetn,
  
  AXI4L.s                   axi_ctrl,

  output logic [127:0]      key_out,
  output logic              keyStart
);

//`define  DEBUG_CNFG_SLAVE

// -- Decl ----------------------------------------------------------
// ------------------------------------------------------------------

// Constants
localparam integer N_REGS = 3;

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
localparam integer KEY_LOW_REG = 0;
// 0 (WR)  : Key low
localparam integer KEY_HIGH_REG = 1;
// 1 (WR)  : Key high

// Write process
assign slv_reg_wren = axi_wready && axi_ctrl.wvalid && axi_awready && axi_ctrl.awvalid;

always_ff @(posedge aclk) begin
  if ( aresetn == 1'b0 ) begin
    slv_reg <= 0;

    keyStart <= 1'b0;
  end
  else begin
    keyStart <= 1'b0;

    if(slv_reg_wren) begin
      case (axi_awaddr[ADDR_LSB+:ADDR_MSB])
        KEY_LOW_REG: // Key low
          for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[KEY_LOW_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        KEY_HIGH_REG: // Key high
          for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[KEY_HIGH_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
              keyStart <= 1'b1;
            end
          end
        default : ;
      endcase
    end
  end
end    

assign key_out[63:0] = slv_reg[KEY_LOW_REG];
assign key_out[127:64] = slv_reg[KEY_HIGH_REG];

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
        KEY_LOW_REG: // Key low
          axi_rdata <= slv_reg[KEY_LOW_REG];
        KEY_HIGH_REG: // Key high
          axi_rdata <= slv_reg[KEY_HIGH_REG];
        default: ;
      endcase
    end
  end 
end

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

endmodule // cnfg_slave