import lynxTypes::*;

/**
 * perf_tcp_axi_ctrl_parser
 * @brief Reads from/wites to the AXI Lite stream containing the benchmark data
 * 
 * @param[in] aclk Clock signal
 * @param[in] aresetn Active low reset signal
 
 * @param[in/out] axi_ctrl AXI Lite Control signal, from/to the host via PCIe and XDMA

 * @param[out] bench_ctrl Benchmark trigger to start reads/writes
 * @param[in] bench_done Number of completed reps
 * @param[in] bench_timer Benchmark timer
 * @param[out] bench_vaddr Buffer virtual address for reading/writing
 * @param[out] bench_len Buffer length (size in bytes) for reading/writing
 * @param[out] bench_pid Coyote thread ID
 * @param[out] bench_n_reps Requested number (from the user software) of read/write reps
 * @param[out] bench_n_beats Number of AXI data beats (check vfpga_top.svh and README for description)
 */
module perf_tcp_axi_ctrl_parser (
  input  logic                        aclk,
  input  logic                        aresetn,
  AXI4L.s                             axi_ctrl,

  output logic                        runTx,
  output logic [15:0]                 numSessions,
  output logic [31:0]                 pkgWordCount,
  output logic [31:0]                 serverIpAddress,
  output logic [31:0]                 userFrequency,
  output logic [31:0]                 timeInSeconds,
  input  logic [3:0]                  state,
  input  logic [31:0]                 totalWord
);

/////////////////////////////////////
//          CONSTANTS             //
///////////////////////////////////
localparam integer N_REGS = 8;
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
// 0 (WR) : client start signal
localparam int START_CLIENT = 0;

// 1 (WR)  : number of connections
localparam int NUMCONNECT   = 1;

// 2 (WR)  : word count per tcp payload (tcp payload : wordcount * 64byte )
localparam int WORDCOUNT    = 2;

// 3 (WR)  : server ip address
localparam int SERVERIP     = 3;

// 4 (WR) : userFrequency
localparam int FREQUENCY    = 4;

// 5 (WR) : timeInSeconds
localparam int TIMEINSECOND = 5;

// 6 (RO) : totalWord
localparam int TOTALWORD    = 6;

// 7 (RO) : State
localparam int CLIENT_STATE    = 7;

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
        if(state != 0) ctrl_reg[START_CLIENT] <= '0;

        if(ctrl_reg_wren) begin
            case (axi_awaddr[ADDR_LSB+:ADDR_MSB])
                START_CLIENT:
                for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
                    if (axi_ctrl.wstrb[i]) begin
                    ctrl_reg[START_CLIENT][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
                    end
                end
                NUMCONNECT:
                for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
                    if(axi_ctrl.wstrb[i]) begin
                    ctrl_reg[NUMCONNECT][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
                    end
                end
                WORDCOUNT:
                for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
                    if(axi_ctrl.wstrb[i]) begin
                    ctrl_reg[WORDCOUNT][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
                    end
                end
                SERVERIP:
                for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
                    if(axi_ctrl.wstrb[i]) begin
                    ctrl_reg[SERVERIP][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
                    end
                end
                FREQUENCY:
                for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
                    if(axi_ctrl.wstrb[i]) begin
                    ctrl_reg[FREQUENCY][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
                    end
                end   
                TIMEINSECOND:
                for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
                    if(axi_ctrl.wstrb[i]) begin
                    ctrl_reg[TIMEINSECOND][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
                    end
                end                   
                default: ;
            endcase                                            
        end
    end
end

assign ctrl_reg_rden = axi_arready & axi_ctrl.arvalid & ~axi_rvalid;



/////////////////////////////////////
//         READ PROCESS           //
///////////////////////////////////
always_ff @(posedge aclk) begin
    if(aresetn == 1'b0) begin
        axi_rdata <= 0;
    end
    else begin
        if(ctrl_reg_rden) begin
        axi_rdata <= 0;
        case (axi_araddr[ADDR_LSB+:ADDR_MSB])
            TOTALWORD:   
                axi_rdata[31:0] <= totalWord;
            CLIENT_STATE:   
                axi_rdata[31:0] <= state;
            default: ;            
        endcase
        end
    end 
end


/////////////////////////////////////
//       OUTPUT ASSIGNMENT        //
///////////////////////////////////
always_comb begin
    runTx               = ctrl_reg[START_CLIENT][0];
    numSessions         = ctrl_reg[NUMCONNECT][15:0];
    pkgWordCount        = ctrl_reg[WORDCOUNT][31:0];
    serverIpAddress     = ctrl_reg[SERVERIP][31:0];
    userFrequency       = ctrl_reg[FREQUENCY][31:0];
    timeInSeconds       = ctrl_reg[TIMEINSECOND][31:0];
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
  if (aresetn == 1'b0 )
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