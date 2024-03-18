import lynxTypes::*;
import kmeansTypes::*;

/**
 *  PT Config Slave
 */ 
module k_means_slave (
  input  logic                                  aclk,
  input  logic                                  aresetn,
  
  AXI4L.s                                       axi_ctrl,

  // Params
  output logic [NUM_CLUSTER_BITS:0]             num_clusters,
  output logic [MAX_DEPTH_BITS:0]               data_dim,
  output logic [63:0]                           data_set_size,
  output logic [7:0]                            precision,

  // Control
  output logic                                  start_operator,
  input  logic                                  um_done,
  // Mux
  output logic                                  select
);

//`define  DEBUG_CNFG_SLAVE

// -- Decl ----------------------------------------------------------
// ------------------------------------------------------------------

// Constants
localparam integer N_REGS = 8;
localparam integer ADDR_LSB = $clog2(AXIL_DATA_BITS/8);
localparam integer ADDR_MSB = $clog2(N_REGS);
localparam integer AXIL_ADDR_BITS = ADDR_LSB + ADDR_MSB;

localparam integer N_ID = 2 * N_REGIONS;
localparam integer N_ID_BITS = $clog2(N_ID);
localparam integer BEAT_LOG_BITS = $clog2(AXI_DATA_BITS/8);
localparam integer BLEN_BITS = LEN_BITS - BEAT_LOG_BITS;

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

logic done;

// -- Register map ----------------------------------------------------------------------- 
// CONFIG
localparam integer CTRL_REG                 = 0;
localparam integer STAT_REG                 = 1;
localparam integer SELECT_REG               = 2;
localparam integer NUM_CLUSTERS_REG         = 3;
localparam integer DATA_DIM_REG             = 4;
localparam integer PRECISION_REG            = 5;
localparam integer DATA_SET_SIZE_REG        = 6;


// Write process
assign slv_reg_wren = axi_wready && axi_ctrl.wvalid && axi_awready && axi_ctrl.awvalid;

always_ff @(posedge aclk) begin
  if ( aresetn == 1'b0 ) begin
    slv_reg <= 'X;
    slv_reg[CTRL_REG] <= 0;

    done <= 1'b0;
  end
  else begin
    slv_reg[CTRL_REG] = 0;

    done <= slv_reg[CTRL_REG][0] ? 1'b0 : (um_done ? 1'b1 : done);

    if(slv_reg_wren) begin
      case (axi_awaddr[ADDR_LSB+:ADDR_MSB])
        
        CTRL_REG: // 
          for (int i = 0; i < 1; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[CTRL_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end

        SELECT_REG: // 
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[SELECT_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end

        NUM_CLUSTERS_REG: // 
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[NUM_CLUSTERS_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        
        DATA_DIM_REG: // 
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[DATA_DIM_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        
        PRECISION_REG: // 
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[PRECISION_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end

        DATA_SET_SIZE_REG: // 
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[DATA_SET_SIZE_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
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
        STAT_REG:
          axi_rdata[0] <= done;
        SELECT_REG:
          axi_rdata[0] <= slv_reg[SELECT_REG];
        NUM_CLUSTERS_REG:
          axi_rdata <= slv_reg[NUM_CLUSTERS_REG];
        DATA_DIM_REG:
          axi_rdata <= slv_reg[DATA_DIM_REG];
        PRECISION_REG:
          axi_rdata <= slv_reg[PRECISION_REG];
        DATA_SET_SIZE_REG:
          axi_rdata <= slv_reg[DATA_SET_SIZE_REG];
        
        default: ;
      endcase
    end
  end 
end

// Output
always_comb begin
    start_operator = slv_reg[CTRL_REG][0];

    select = slv_reg[SELECT_REG][0];

    num_clusters = slv_reg[NUM_CLUSTERS_REG][NUM_CLUSTER_BITS:0];
    data_dim = slv_reg[DATA_DIM_REG][MAX_DEPTH_BITS:0];
    precision = slv_reg[PRECISION_REG][7:0];
    data_set_size = slv_reg[DATA_SET_SIZE_REG];
end

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

endmodule // cnfg_slave