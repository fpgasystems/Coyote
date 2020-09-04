/**
 *  PT Config Slave
 */ 
module hll_slave (
  input  logic              aclk,
  input  logic              aresetn,
  
  AXI4L.s                   axi_ctrl,

  input  logic              resultValid,
  input  logic [63:0]       result,
  output logic              resetn_hll
);

//`define  DEBUG_CNFG_SLAVE

// -- Decl ----------------------------------------------------------
// ------------------------------------------------------------------

// Constants
localparam integer N_REGS = 3;
localparam integer ADDR_LSB = (AXIL_DATA_BITS/32) + 1;
localparam integer ADDR_MSB = $clog2(N_REGS);
localparam integer SLV_ADDR_BITS = ADDR_LSB + ADDR_MSB;

// Internal registers
logic [SLV_ADDR_BITS-1:0] axi_awaddr;
logic axi_awready;
logic [SLV_ADDR_BITS-1:0] axi_araddr;
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
logic [AXIL_DATA_BITS-1:0] slv_data_out;
logic aw_en;

logic done;

// -- Def -----------------------------------------------------------
// ------------------------------------------------------------------

/* -- Register map ----------------------------------------------------------------------- 
/ 0 (RW)  : Control
/ 1 (RO)  : Status
/ 2 (RO)  : Result
*/

// Write process
assign slv_reg_wren = axi_wready && axi_ctrl.wvalid && axi_awready && axi_ctrl.awvalid;

always_ff @(posedge aclk, negedge aresetn) begin
  if ( aresetn == 1'b0 ) begin
    for (int i = 0; i < N_REGS; i++) begin
      slv_reg[i] <= 0;
    end 
  end
  else begin
    slv_reg[0][0] <= 0;

    if(resultValid) begin
        slv_reg[1][0] <= 1'b1;
        slv_reg[2] <= result;
    end
    else if(slv_reg[0][0]) begin
        slv_reg[1][0] <= 1'b0;
    end

    if(slv_reg_wren) begin
      case (axi_awaddr[ADDR_LSB+ADDR_MSB-1:ADDR_LSB])
        2'h0: begin // Control
          for (int i = 0; i < 1; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[0][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        end
        default : ;
      endcase
    end
  end
end    

assign resetn_hll = ~slv_reg[0][0];

// Read process
assign slv_reg_rden = axi_arready & axi_ctrl.arvalid & ~axi_rvalid;

always_ff @(posedge aclk, negedge aresetn) begin
  if( aresetn == 1'b0 ) begin
    axi_rdata <= 0;
  end
  else begin
    axi_rdata <= 0;
    if(slv_reg_rden) begin
      case (axi_araddr[ADDR_LSB+ADDR_MSB-1:ADDR_LSB])
        2'h1: // Status
          axi_rdata[0] <= slv_reg[1][0];
        2'h2: // Result
          axi_rdata <= slv_reg[2];
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
always_ff @(posedge aclk, negedge aresetn) begin
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
always_ff @(posedge aclk, negedge aresetn) begin
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
always_ff @(posedge aclk, negedge aresetn) begin
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
always_ff @(posedge aclk, negedge aresetn) begin
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
always_ff @(posedge aclk, negedge aresetn) begin
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