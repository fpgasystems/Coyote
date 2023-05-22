/**
 *  Benchmark slave
 */ 
import lynxTypes::*;

module perf_fpga_slv (
  input  logic                        aclk,
  input  logic                        aresetn,
  
  AXI4L.s                             axi_ctrl,

  output logic [1:0]                  bench_ctrl,
  input  logic [31:0]                 bench_done,
  input  logic [63:0]                 bench_timer,
  output logic [VADDR_BITS-1:0]       bench_vaddr,
  output logic [LEN_BITS-1:0]         bench_len,
  output logic [PID_BITS-1:0]         bench_pid,
  output logic [31:0]                 bench_n_reps,
  output logic [63:0]                 bench_n_beats,
  output logic [DEST_BITS-1:0]        bench_dest
);

// -- Decl ----------------------------------------------------------
// ------------------------------------------------------------------
// Constants
localparam integer N_REGS = 9;
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
// 0 (W1S)  : AP start (
localparam integer BENCH_CTRL_REG = 0;
//                0 - read
//                1 - write 
// 1 (RO)   : Number of completed requests
localparam integer BENCH_DONE_REG = 1;
// 2 (RO)   : Timer
localparam integer BENCH_TIMER_REG = 2;
// 3 (WR)   : Vaddr
localparam integer BENCH_VADDR_REG = 3;
// 4 (WR)   : Length
localparam integer BENCH_LEN_REG = 4;
// 5 (WR)   : Pid
localparam integer BENCH_PID_REG = 5;
// 6 (WR)   : Number of repetitions
localparam integer BENCH_N_REPS_REG = 6;
// 7 (WR)   : Number of beats expected
localparam integer BENCH_N_BEATS_REG = 7;
// 8 (WR)   : Dest
localparam integer BENCH_DEST_REG = 8;

// Write process
assign slv_reg_wren = axi_wready && axi_ctrl.wvalid && axi_awready && axi_ctrl.awvalid;

always_ff @(posedge aclk) begin
  if ( aresetn == 1'b0 ) begin
    slv_reg <= 0;
  end
  else begin
    // Control
    slv_reg[BENCH_CTRL_REG] <= 0;

    if(slv_reg_wren) begin
      case (axi_awaddr[ADDR_LSB+:ADDR_MSB])
        BENCH_CTRL_REG:  // Control
          for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[BENCH_CTRL_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        BENCH_VADDR_REG: // Vaddr
          for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[BENCH_VADDR_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        BENCH_LEN_REG: // Length
          for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[BENCH_LEN_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        BENCH_PID_REG: // PID
          for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[BENCH_PID_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        BENCH_N_REPS_REG: // Number of reps
          for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[BENCH_N_REPS_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        BENCH_N_BEATS_REG: // Number of beats
          for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[BENCH_N_BEATS_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        BENCH_DEST_REG: // DEST 
          for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[BENCH_DEST_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
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
        BENCH_DONE_REG: // Number of completions
          axi_rdata[31:0] <= bench_done;
        BENCH_TIMER_REG: // Timer
          axi_rdata <= bench_timer;
        BENCH_VADDR_REG: // Vaddr
          axi_rdata[VADDR_BITS-1:0] <= slv_reg[BENCH_VADDR_REG][VADDR_BITS-1:0];
        BENCH_LEN_REG: // Length
          axi_rdata[LEN_BITS-1:0] <= slv_reg[BENCH_LEN_REG][LEN_BITS-1:0];
        BENCH_PID_REG: // PID
          axi_rdata[PID_BITS-1:0] <= slv_reg[BENCH_PID_REG][PID_BITS-1:0];
        BENCH_N_REPS_REG: // Number of reps
          axi_rdata[31:0] <= slv_reg[BENCH_N_REPS_REG][31:0];
        BENCH_N_BEATS_REG: // Number of beats
          axi_rdata <= slv_reg[BENCH_N_BEATS_REG];
        BENCH_DEST_REG: // DEST
          axi_rdata[DEST_BITS-1:0] <= slv_reg[BENCH_DEST_REG][DEST_BITS-1:0];
        default: ;
      endcase
    end
  end 
end

// Output
always_comb begin
  bench_ctrl      = slv_reg[BENCH_CTRL_REG][1:0];
  bench_vaddr     = slv_reg[BENCH_VADDR_REG][VADDR_BITS-1:0];
  bench_len       = slv_reg[BENCH_LEN_REG][LEN_BITS-1:0];
  bench_pid       = slv_reg[BENCH_PID_REG][PID_BITS-1:0];
  bench_n_reps    = slv_reg[BENCH_N_REPS_REG][31:0];
  bench_n_beats   = slv_reg[BENCH_N_BEATS_REG];
  bench_dest      = slv_reg[BENCH_DEST_REG][DEST_BITS-1:0];
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