import lynxTypes::*;

/**
 * perf_fpga_axi_ctrl_parser
 * @brief Reads from/wites to the AXI Lite stream containing the benchmark data
 * 
 * @param[in] aclk Clock signal
 * @param[in] aresetn Active low reset signal
 
 * @param[in/out] axi_ctrl AXI Lite Control signal, from/to the host via PCIe and XDMA

 */
module perf_tcp_axi_ctrl_parser (
  input  logic                        aclk,
  input  logic                        aresetn,
  
  AXI4L.s                             axi_ctrl,

  input  logic                        listen_rsp_ready,        
  input  logic [7:0]                  listen_rsp_data,         
  input  logic [31:0]                 listen_port_acc,  

  // CSR outputs to your FSM
  output logic [1:0]                  listen_ctrl,      // bit0 = GO (W1S)
  output logic [15:0]                 listen_port_addr, // listen port (16b)
  output logic [1:0]                  port_sts_rd       // bit0 = CLEAR/ACK (W1S)

);

/////////////////////////////////////
//          CONSTANTS             //
///////////////////////////////////
localparam integer N_REGS = 6;
localparam integer ADDR_MSB = $clog2(N_REGS);
localparam integer ADDR_LSB = $clog2(AXIL_DATA_BITS/8);
localparam integer AXI_ADDR_BITS = ADDR_LSB + ADDR_MSB;



// Registers for holding the values read from/to be written to the AXI Lite interface
// These are synchronous but the outputs are combinatorial
logic [N_REGS-1:0][AXIL_DATA_BITS-1:0] ctrl_reg;
logic ctrl_reg_rden;
logic ctrl_reg_wren;

/////////////////////////////////////
//         REGISTER MAP           //
///////////////////////////////////
// 0 (W1S)  : AP start 
localparam integer LISTEN_PORT_SIGNAL = 0;

// 1 (WR)   : Port Number
localparam integer LISTEN_PORT = 1;

// 2 (RO)   : Port Status Signal
localparam integer PORT_STATUS_SIGNAL = 2;

// 3 (RO)   : Port Status
localparam integer PORT_STATUS = 3;

// 4 (W1S)   : Port Status Read (W1S)
localparam integer PORT_STATUS_READ = 4;

// 5 (RO)   : Number of open port
localparam integer LISTEN_PORT_NUM = 5;


/////////////////////////////////////
//          REGISTERS             //
///////////////////////////////////
// Internal AXI registers
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
logic aw_en;


/////////////////////////////////////
//         WRITE PROCESS          //
///////////////////////////////////
// Data coming in from host to the vFPGA vie PCIe and XDMA
assign ctrl_reg_wren = axi_wready && axi_ctrl.wvalid && axi_awready && axi_ctrl.awvalid;

always_ff @(posedge aclk) begin
    if (aresetn == 1'b0) begin
        ctrl_reg <= 0;
    end
    else begin
      // Control
        ctrl_reg[LISTEN_PORT_SIGNAL] <= 0;
        ctrl_reg[PORT_STATUS_READ] <= 0;

        if(ctrl_reg_wren) begin
            case (axi_awaddr[ADDR_LSB+:ADDR_MSB])
                LISTEN_PORT_SIGNAL:
                for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
                    if(axi_ctrl.wstrb[i]) begin
                    ctrl_reg[LISTEN_PORT_SIGNAL][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
                    end
                end
                LISTEN_PORT:
                for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
                    if(axi_ctrl.wstrb[i]) begin
                    ctrl_reg[LISTEN_PORT][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
                    end
                end
                PORT_STATUS_READ:
                for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
                    if(axi_ctrl.wstrb[i]) begin
                    ctrl_reg[PORT_STATUS_READ][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
                    end
                end
                default: ;
            endcase                                            
        end
    end
end

/////////////////////////////////////
//         READ PROCESS           //
///////////////////////////////////
// Data going to the host from the vFPGA via XDMA and PCIe
assign ctrl_reg_rden = axi_arready & axi_ctrl.arvalid & ~axi_rvalid;

always_ff @(posedge aclk) begin
    if(aresetn == 1'b0) begin
        axi_rdata <= 0;
    end
    else begin
        if(ctrl_reg_rden) begin
        axi_rdata <= 0;

        case (axi_araddr[ADDR_LSB+:ADDR_MSB])
            PORT_STATUS_SIGNAL:   
                axi_rdata <= listen_rsp_ready;
            PORT_STATUS:  
                axi_rdata[7:0] <= listen_rsp_data;
            LISTEN_PORT_NUM:
                axi_rdata[31:0] <= listen_port_acc;
            default: ;
        endcase
        end
    end 
end

/////////////////////////////////////
//       OUTPUT ASSIGNMENT        //
///////////////////////////////////
always_comb begin
    listen_ctrl         = ctrl_reg[LISTEN_PORT_SIGNAL][1:0];
    listen_port_addr    = ctrl_reg[LISTEN_PORT][15:0];
    port_sts_rd         = ctrl_reg[PORT_STATUS_READ][1:0];
end

/////////////////////////////////////
//     STANDARD AXI CONTROL       //
///////////////////////////////////
// NOT TO BE EDITED

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