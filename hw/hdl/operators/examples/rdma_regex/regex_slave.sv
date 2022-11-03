import lynxTypes::*;

module regex_slave (
    input  logic                aclk,
    input  logic                aresetn,
  
    // Control bus (HOST)
    AXI4L.s                     axi_ctrl,

    metaIntf.m                  meta_config,
    metaIntf.s                  meta_found
);  

// -- Decl -------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------

// Constants
localparam integer N_REGS = 10;
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

// Slave Registers
logic [N_REGS-1:0][AXIL_DATA_BITS-1:0] slv_reg;
logic slv_reg_rden;
logic slv_reg_wren;
logic aw_en;

// -- Def --------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------

// -- Register map ----------------------------------------------------------------------- 
// 0 (W1S|W1C) : Control 
localparam integer CTRL_REG                                 = 0;
      localparam integer CLR                = 0;
      localparam integer LOAD               = 1;
// 1 (RO) : Counts the matches
localparam integer CNT_REG                                  = 1;
// 2 (RW) : Config
localparam integer CNFG_0_REG                               = 2;
localparam integer CNFG_1_REG                               = 3;
localparam integer CNFG_2_REG                               = 4;
localparam integer CNFG_3_REG                               = 5;
localparam integer CNFG_4_REG                               = 6;
localparam integer CNFG_5_REG                               = 7;
localparam integer CNFG_6_REG                               = 8;
localparam integer CNFG_7_REG                               = 9;
//

// ---------------------------------------------------------------------------------------- 
// Write process 
// ----------------------------------------------------------------------------------------
assign slv_reg_wren = axi_wready && axi_ctrl.wvalid && axi_awready && axi_ctrl.awvalid;

always_ff @(posedge aclk) begin
  if ( aresetn == 1'b0 ) begin
    slv_reg <= 'X;
    
    slv_reg[CTRL_REG] <= 1'b0;
    meta_config.valid <= 1'b0;
  end
  else begin
    slv_reg[CTRL_REG] <= 1'b0;
    
    meta_config.valid <= slv_reg[CTRL_REG][LOAD] ? 1'b1 : (meta_config.ready ? 1'b0 : meta_config.valid);

    slv_reg[CNT_REG] <= slv_reg[CTRL_REG][CLR] ? 0 : (meta_found.valid ? slv_reg[CNT_REG] + 1 : slv_reg[CNT_REG]);

    // Slave write
    if(slv_reg_wren) begin
      case (axi_awaddr[ADDR_LSB+:ADDR_MSB])
        CTRL_REG: // Control
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[CTRL_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        CNFG_0_REG:
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[CNFG_0_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        CNFG_1_REG: 
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[CNFG_1_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        CNFG_2_REG:
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[CNFG_2_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        CNFG_3_REG: 
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[CNFG_3_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        CNFG_4_REG:
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[CNFG_4_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        CNFG_5_REG:
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[CNFG_5_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        CNFG_6_REG:
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[CNFG_6_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        CNFG_7_REG:
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[CNFG_7_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
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
assign slv_reg_rden = axi_arready & axi_ctrl.arvalid & ~axi_rvalid;

always_ff @(posedge aclk) begin
  if( aresetn == 1'b0 ) begin
    axi_rdata <= 'X;
  end
  else begin
    axi_rdata <= 0;

    if(slv_reg_rden) begin
      case (axi_araddr[ADDR_LSB+:ADDR_MSB]) inside
        CNT_REG: 
          axi_rdata <= slv_reg[CNT_REG];
        CNFG_0_REG: 
          axi_rdata <= slv_reg[CNFG_0_REG];
        CNFG_1_REG: 
          axi_rdata <= slv_reg[CNFG_1_REG];
        CNFG_2_REG: 
          axi_rdata <= slv_reg[CNFG_2_REG];
        CNFG_3_REG: 
          axi_rdata <= slv_reg[CNFG_3_REG];
        CNFG_4_REG: 
          axi_rdata <= slv_reg[CNFG_4_REG];
        CNFG_5_REG: 
          axi_rdata <= slv_reg[CNFG_5_REG];
        CNFG_6_REG: 
          axi_rdata <= slv_reg[CNFG_6_REG];
        CNFG_7_REG: 
          axi_rdata <= slv_reg[CNFG_7_REG];


        default: ;
      endcase
    end
  end 
end

// ---------------------------------------------------------------------------------------- 
// I/O
// ----------------------------------------------------------------------------------------
for(genvar i = 0; i < 8; i++) begin
    assign meta_config.data[i*64+:64] = slv_reg[i+CNFG_0_REG];
end

assign meta_found.ready = 1'b1;


// ---------------------------------------------------------------------------------------- 
// AXI
// ----------------------------------------------------------------------------------------

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

endmodule
