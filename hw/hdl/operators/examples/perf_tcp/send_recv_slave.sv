import lynxTypes::*;

/**
 *  PT Config Slave
 */ 
module send_recv_slave (
  input  logic                                  aclk,
  input  logic                                  aresetn,
  
  AXI4L.s                                       axi_ctrl,

  output logic 									            ap_start,
  input logic 									            ap_done,
  output logic [31:0]                   		useConn,
  output logic [31:0]                   		useIpAddr,
  output logic [31:0]                   		pkgWordCount,
  output logic [31:0]                   		basePort,
  output logic [31:0]                   		baseIpAddress,
  output logic [31:0]                  			transferSize,
  output logic [31:0]                  			isServer,
  output logic [31:0]                  			timeInSeconds,
  output logic [63:0]                  			timeInCycles,
  output logic [31:0]                       sessionID,
  input logic [63:0]                        execution_cycles,
  input logic [63:0]                        consumed_bytes,
  input logic [63:0]                        produced_bytes
);

// `define  DEBUG_CNFG_SLAVE

// -- Decl ----------------------------------------------------------
// ------------------------------------------------------------------

// Constants
localparam integer N_REGS = 16;
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

/* -- Register map ----------------------------------------------------------------------- 
/ 0 (WO)  : Control
/ 1 (RO)  : Status
/ 2 (RW)  : useConn
/ 3 (RW)  : useIpAddr
/ 4 (RW)  : pkgWordCount
/ 5 (RW)  : basePort
/ 6 (RW)  : baseIpAddr
/ 7 (RW)  : transferSize
/ 8 (RW)  : isServer
/ 9 (RW)  : timeInSeconds
/ 10 (RW) : timeInCycles
/ 11 (R)  : execution_cycles
/ 12 (R)  : consumed_bytes
/ 13 (R)  : produced_bytes
/ 15 (RW) : sessionID
*/

// Write process
assign slv_reg_wren = axi_wready && axi_ctrl.wvalid && axi_awready && axi_ctrl.awvalid;

always_ff @(posedge aclk) begin
  if ( aresetn == 1'b0 ) begin
    slv_reg <= 0;
  end
  else begin
    slv_reg[0][0] <= 0;

    if(slv_reg_wren) begin
      case (axi_awaddr[ADDR_LSB+:ADDR_MSB])
        4'h0: // Control
          for (int i = 0; i < 1; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[0][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        4'h2: // useConn
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[2][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        4'h3: // useIpAddr
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[3][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        4'h4: // pkgWordCount
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[4][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        4'h5: // basePort
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[5][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        4'h6: // baseIpAddr
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[6][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        4'h7: // transferSize
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[7][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        4'h8: // isServer
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[8][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        4'h9: // timeInSeconds
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[9][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        4'ha: // timeInCycles
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[10][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        4'hf: // sessionID
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[15][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        default : ;
      endcase
    end
  end
end    

// Output
always_comb begin
    ap_start = slv_reg[0][0];

    useConn = slv_reg[2];
    useIpAddr = slv_reg[3];
    pkgWordCount = slv_reg[4];
    basePort = slv_reg[5];
    baseIpAddress = slv_reg[6];
    transferSize = slv_reg[7];
    isServer = slv_reg[8];
    timeInSeconds = slv_reg[9];
    timeInCycles = slv_reg[10];
    sessionID = slv_reg[15];
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
        4'h1: // Status
          axi_rdata[0] <= ap_done;
        4'h2: // useConn
          axi_rdata <= slv_reg[2];
        4'h3: // useIpAddr
          axi_rdata <= slv_reg[3];
        4'h4: // pkgWordCount
          axi_rdata <= slv_reg[4];
        4'h5: // basePort
          axi_rdata <= slv_reg[5];
        4'h6: // baseIpAddr
          axi_rdata <= slv_reg[6];
        4'h7: // transferSize
          axi_rdata <= slv_reg[7];
        4'h8: // isServer
          axi_rdata <= slv_reg[8];
        4'h9: // timeInSeconds
          axi_rdata <= slv_reg[9];
        4'ha: // timeInCycles
          axi_rdata <= slv_reg[10];
        4'hb: //execution_cycles
          axi_rdata <= execution_cycles;
        4'hc: //consumed_bytes
          axi_rdata <= consumed_bytes;
        4'hd: //produced_bytes
          axi_rdata <= produced_bytes;
        4'hf: //sessionID
          axi_rdata <= sessionID;
        default: ;
      endcase
    end
  end 
end

//`define DEBUG_CNFG_SLAVE
`ifdef DEBUG_CNFG_SLAVE
ila_slave ila_slave
(
    .clk(aclk),
    .probe0(slv_reg_rden),
    .probe1(slv_reg_wren),
    .probe2(axi_ctrl.arvalid),
    .probe3(axi_ctrl.arready),
    .probe4(axi_ctrl.araddr), // 64
    .probe5(axi_ctrl.awvalid),
    .probe6(axi_ctrl.awready),
    .probe7(axi_ctrl.awaddr), // 64
    .probe8(axi_ctrl.rvalid), 
    .probe9(axi_ctrl.rready),
    .probe10(axi_ctrl.rdata), // 64
    .probe11(axi_ctrl.wvalid), 
    .probe12(axi_ctrl.wready),
    .probe13(axi_ctrl.wdata), // 64
    .probe14(axi_ctrl.wstrb), // 8
    .probe15(axi_ctrl.bvalid),
    .probe16(axi_ctrl.bready)
 ); 
`endif

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


endmodule // cnfg_slave