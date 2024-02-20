import lynxTypes::*;
import kmeansTypes::*;

/**
 *  PT Config Slave
 */ 
module k_means_slave (
  input  logic                                  aclk,
  input  logic                                  aresetn,
  
  AXI4L.s                                       axi_ctrl,

  output logic                                  start_operator,
  input  logic                                  um_done,
  output logic [63:0]                           data_set_size,
  output logic [NUM_CLUSTER_BITS:0]             num_clusters,
  output logic [MAX_DEPTH_BITS:0]               data_dim,
  output logic                                  select
);

//`define  DEBUG_CNFG_SLAVE

// -- Decl ----------------------------------------------------------
// ------------------------------------------------------------------

// Constants
localparam integer N_REGS = 6;
localparam integer ADDR_LSB = (AXIL_DATA_BITS/32) + 1;
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
logic [AXIL_DATA_BITS-1:0] slv_data_out;
logic aw_en;

// -- Def -----------------------------------------------------------
// ------------------------------------------------------------------

/* -- Register map ----------------------------------------------------------------------- 
/ 0 (WO)  : Control
/ 1 (RO)  : Status
/ 2 (RW)  : Data set size
/ 3 (RW)  : Number of clusters
/ 4 (RW)  : Data dimensions
/ 5 (RW)  : Select
*/

// Write process
assign slv_reg_wren = axi_wready && axi_ctrl.wvalid && axi_awready && axi_ctrl.awvalid;

always_ff @(posedge aclk) begin
  if ( aresetn == 1'b0 ) begin
    for (int i = 0; i < N_REGS; i++) begin
      slv_reg[i] <= 0;
    end 
  end
  else begin
    slv_reg[0][0] <= 0;

    if(slv_reg_wren) begin
      case (axi_awaddr[ADDR_LSB+ADDR_MSB-1:ADDR_LSB])
        2'h0: // Control
          for (int i = 0; i < 1; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[0][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        2'h2: // Data set size
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[2][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        2'h3: // Number of clusters
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[3][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        2'h4: // Data dimensions
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[4][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        2'h5: // Select
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[5][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        default : ;
      endcase
    end
  end
end    

// Output
always_comb begin
    start_operator = slv_reg[0][0];

    data_set_size = slv_reg[2];
    num_clusters = slv_reg[3];
    data_dim = slv_reg[4];
    select = slv_reg[5][0];
end

// Read process
assign slv_reg_rden = axi_arready & axi_ctrl.arvalid & ~axi_rvalid;

always_ff @(posedge aclk) begin
  if( aresetn == 1'b0 ) begin
    axi_rdata <= 0;
  end
  else begin
    axi_rdata <= 0;
    if(slv_reg_rden) begin
      case (axi_araddr[ADDR_LSB+ADDR_MSB-1:ADDR_LSB])
        2'h1: // Status
          axi_rdata[0] <= um_done;
        2'h2: // Data set size
          axi_rdata <= slv_reg[2];
        2'h3: // Number of clusters
          axi_rdata[NUM_CLUSTER_BITS:0] <= slv_reg[3][NUM_CLUSTER_BITS:0];
        2'h4: // Data dimensions
          axi_rdata[MAX_DEPTH_BITS:0] <= slv_reg[4][MAX_DEPTH_BITS:0];
        2'h5: // Select
          axi_rdata[0] <= slv_reg[5][0];
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