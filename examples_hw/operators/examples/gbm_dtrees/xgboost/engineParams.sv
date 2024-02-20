// This is a generated file. Use and modify at your own risk.
////////////////////////////////////////////////////////////////////////////////

// default_nettype of none prevents implicit wire declaration.
`default_nettype none
`timescale 1ns/1ps
module engineParams #(
  parameter integer C_ADDR_WIDTH = 12,
  parameter integer C_DATA_WIDTH = 32
)
(
  // AXI4-Lite slave signals
  input  wire                      aclk           ,
  input  wire                      areset         ,
  input  wire                      aclk_en        ,
  input  wire                      awvalid        ,
  output wire                      awready        ,
  input  wire [C_ADDR_WIDTH-1:0]   awaddr         ,
  input  wire                      wvalid         ,
  output wire                      wready         ,
  input  wire [C_DATA_WIDTH-1:0]   wdata          ,
  input  wire [C_DATA_WIDTH/8-1:0] wstrb          ,
  input  wire                      arvalid        ,
  output wire                      arready        ,
  input  wire [C_ADDR_WIDTH-1:0]   araddr         ,
  output wire                      rvalid         ,
  input  wire                      rready         ,
  output wire [C_DATA_WIDTH-1:0]   rdata          ,
  output wire [2-1:0]              rresp          ,
  output wire                      bvalid         ,
  input  wire                      bready         ,
  output wire [2-1:0]              bresp          ,
  output wire                      ap_start       ,
  // User defined arguments
  output wire [16-1:0]             tuple_numcls   ,
  output wire [8-1:0]              treeDepth      ,
  output wire [8-1:0]              puTrees        ,
  output wire [32-1:0]             outputNumCLs   ,
  output wire [8-1:0]              prog_schedule  ,
  output wire [8-1:0]              proc_schedule  ,
  output wire [16-1:0]             tree_weights_numcls_minus_one,
  output wire [16-1:0]             tree_feature_index_numcls_minus_one
);

///////////////////////////////////////////////////////////////////////////////
// Local Parameters
///////////////////////////////////////////////////////////////////////////////
localparam [C_ADDR_WIDTH-1:0]       LP_ADDR_AP_CTRL                = 12'h000; // 0
localparam [C_ADDR_WIDTH-1:0]       LP_ADDR_TUPLENUMCLS_0          = 12'h008; // 1
localparam [C_ADDR_WIDTH-1:0]       LP_ADDR_TREEDEPTH_0            = 12'h010; // 2
localparam [C_ADDR_WIDTH-1:0]       LP_ADDR_PUTREES_0              = 12'h018; // 3
localparam [C_ADDR_WIDTH-1:0]       LP_ADDR_OUTPUTNUMCLS_0         = 12'h020; // 4
localparam [C_ADDR_WIDTH-1:0]       LP_ADDR_TREEWNUMCLS_0          = 12'h028; // 5
localparam [C_ADDR_WIDTH-1:0]       LP_ADDR_TREEFNUMCLS_0          = 12'h030; // 6
localparam [C_ADDR_WIDTH-1:0]       LP_ADDR_PROG_SCHEDULE_0        = 12'h038; // 7
localparam [C_ADDR_WIDTH-1:0]       LP_ADDR_PROC_SCHEDULE_0        = 12'h040; // 8

localparam integer                  LP_SM_WIDTH                    = 2;
localparam [LP_SM_WIDTH-1:0]        SM_WRIDLE                      = 2'd0;
localparam [LP_SM_WIDTH-1:0]        SM_WRDATA                      = 2'd1;
localparam [LP_SM_WIDTH-1:0]        SM_WRRESP                      = 2'd2;
localparam [LP_SM_WIDTH-1:0]        SM_WRRESET                     = 2'd3;
localparam [LP_SM_WIDTH-1:0]        SM_RDIDLE                      = 2'd0;
localparam [LP_SM_WIDTH-1:0]        SM_RDDATA                      = 2'd1;
localparam [LP_SM_WIDTH-1:0]        SM_RDRESET                     = 2'd3;

///////////////////////////////////////////////////////////////////////////////
// Wires and Variables
///////////////////////////////////////////////////////////////////////////////
reg  [LP_SM_WIDTH-1:0]              wstate                         = SM_WRRESET;
reg  [LP_SM_WIDTH-1:0]              wnext                         ;
reg  [C_ADDR_WIDTH-1:0]             waddr                         ;
wire [C_DATA_WIDTH-1:0]             wmask                         ;
wire                                aw_hs                         ;
wire                                w_hs                          ;
reg  [LP_SM_WIDTH-1:0]              rstate                         = SM_RDRESET;
reg  [LP_SM_WIDTH-1:0]              rnext                         ;
reg  [C_DATA_WIDTH-1:0]             rdata_r                       ;
wire                                ar_hs                         ;
wire [C_ADDR_WIDTH-1:0]             raddr                         ;
// internal registers
reg                                 int_ap_start                   = 1'b0;

reg  [16-1:0]                       int_tuple_numcls               = 16'd0;
reg  [8-1:0]                        int_treeDepth                  = 8'd0;
reg  [8-1:0]                        int_puTrees                    = 8'd0;
reg  [8-1:0]                        int_prog_schedule              = 8'd0;
reg  [8-1:0]                        int_proc_schedule              = 8'd0;
reg  [32-1:0]                       int_outputNumCLs               = 32'd0;
reg  [16-1:0]                       int_treew_numcls               = 16'd0;
reg  [16-1:0]                       int_treef_numcls               = 16'd0;

///////////////////////////////////////////////////////////////////////////////
// Begin RTL
///////////////////////////////////////////////////////////////////////////////

//------------------------AXI write fsm------------------
assign awready = (wstate == SM_WRIDLE);
assign wready  = (wstate == SM_WRDATA);
assign bresp   = 2'b00;  // OKAY
assign bvalid  = (wstate == SM_WRRESP);

genvar i;
generate for (i = 0; i < C_DATA_WIDTH/8; i=i+1) begin: wmask_g
  assign wmask[8*i+7:8*i] = {8{wstrb[i]}};
end
endgenerate

assign aw_hs   = awvalid & awready;
assign w_hs    = wvalid & wready;

// wstate
always @(posedge aclk) begin
  if (areset)
    wstate <= SM_WRRESET;
  else if (aclk_en)
    wstate <= wnext;
end

// wnext
always @(*) begin
  case (wstate)
    SM_WRIDLE:
      if (awvalid)
        wnext = SM_WRDATA;
      else
        wnext = SM_WRIDLE;
    SM_WRDATA:
      if (wvalid)
        wnext = SM_WRRESP;
      else
        wnext = SM_WRDATA;
    SM_WRRESP:
      if (bready)
        wnext = SM_WRIDLE;
      else
        wnext = SM_WRRESP;
    // SM_WRRESET
    default:
      wnext = SM_WRIDLE;
  endcase
end

// waddr
always @(posedge aclk) begin
  if (aclk_en) begin
    if (aw_hs)
      waddr <= awaddr;
  end
end

//------------------------AXI read fsm-------------------
assign arready = (rstate == SM_RDIDLE);
assign rdata   = rdata_r;
assign rresp   = 2'b00;  // OKAY
assign rvalid  = (rstate == SM_RDDATA);
assign ar_hs   = arvalid & arready;
assign raddr   = araddr;

// rstate
always @(posedge aclk) begin
  if (areset)
    rstate <= SM_RDRESET;
  else if (aclk_en)
    rstate <= rnext;
end

// rnext
always @(*) begin
  case (rstate)
    SM_RDIDLE:
      if (arvalid)
        rnext = SM_RDDATA;
      else
        rnext = SM_RDIDLE;
    SM_RDDATA:
      if (rready & rvalid)
        rnext = SM_RDIDLE;
      else
        rnext = SM_RDDATA;
    // SM_RDRESET:
    default:
      rnext = SM_RDIDLE;
  endcase
end

// rdata_r
always @(posedge aclk) begin
  if (aclk_en) begin
    if (ar_hs) begin
      rdata_r <= {C_DATA_WIDTH{1'b0}};
      case (raddr)
        LP_ADDR_AP_CTRL: begin
          rdata_r[0] <= int_ap_start;
          rdata_r[1] <= int_ap_done;
          rdata_r[2] <= int_ap_idle;
          rdata_r[3+:C_DATA_WIDTH-3] <= {C_DATA_WIDTH-3{1'b0}};
        end
        LP_ADDR_TUPLENUMCLS_0: begin
          rdata_r <= {16'b0, int_tuple_numcls[0+:16]};
        end
        LP_ADDR_TREEDEPTH_0: begin
          rdata_r <= {24'b0, int_treeDepth[0+:8]};
        end
        LP_ADDR_PUTREES_0: begin
          rdata_r <= {24'b0, int_puTrees[0+:8]};
        end
        LP_ADDR_OUTPUTNUMCLS_0: begin
          rdata_r <= int_outputNumCLs[0+:32];
        end
        LP_ADDR_TREEWNUMCLS_0: begin
          rdata_r <= {16'b0, int_treew_numcls[0+:16]};
        end
        LP_ADDR_TREEFNUMCLS_0: begin
          rdata_r <= {16'b0, int_treef_numcls[0+:16]};
        end
        default: begin
          rdata_r <= {C_DATA_WIDTH{1'b0}};
        end
      endcase
    end
  end
end

//------------------------Register logic-----------------
assign ap_start         = int_ap_start;
assign tuple_numcls     = int_tuple_numcls;
assign treeDepth        = int_treeDepth;
assign puTrees          = int_puTrees;
assign outputNumCLs     = int_outputNumCLs;
assign proc_schedule    = int_proc_schedule;
assign prog_schedule    = int_prog_schedule;


assign tree_weights_numcls_minus_one        = int_treew_numcls;
assign tree_feature_index_numcls_minus_one  = int_treef_numcls;

// int_ap_start
always @(posedge aclk) begin
  if (areset)
    int_ap_start <= 1'b0;
  else if (aclk_en) begin
    if (w_hs && waddr[11:0] == LP_ADDR_AP_CTRL && wstrb[0] && wdata[0])
      int_ap_start <= 1'b1;
    else if (ap_done)
      int_ap_start <= 1'b0;
  end
end

// int_numFeatures[16-1:0]
always @(posedge aclk) begin
  if (areset)
    int_tuple_numcls[0+:16] <= 16'd0;
  else if (aclk_en) begin
    if (w_hs && waddr[11:0] == LP_ADDR_TUPLENUMCLS_0)
      int_tuple_numcls[0+:16] <= (wdata[0+:16] & wmask[0+:16]) | (int_tuple_numcls[0+:16] & ~wmask[0+:16]);
  end
end

// int_treeDepth[8-1:0]
always @(posedge aclk) begin
  if (areset)
    int_treeDepth[0+:8] <= 8'd0;
  else if (aclk_en) begin
    if (w_hs && waddr[11:0] == LP_ADDR_TREEDEPTH_0)
      int_treeDepth[0+:8] <= (wdata[0+:8] & wmask[0+:8]) | (int_treeDepth[0+:8] & ~wmask[0+:8]);
  end
end

// int_puTrees[8-1:0]
always @(posedge aclk) begin
  if (areset)
    int_puTrees[0+:8] <= 8'd0;
  else if (aclk_en) begin
    if (w_hs && waddr[11:0] == LP_ADDR_PUTREES_0)
      int_puTrees[0+:8] <= (wdata[0+:8] & wmask[0+:8]) | (int_puTrees[0+:8] & ~wmask[0+:8]);
  end
end

// int_outputNumCLs[32-1:0]
always @(posedge aclk) begin
  if (areset)
    int_outputNumCLs[0+:32] <= 32'd0;
  else if (aclk_en) begin
    if (w_hs && waddr[11:0] == LP_ADDR_OUTPUTNUMCLS_0)
      int_outputNumCLs[0+:32] <= (wdata[0+:32] & wmask[0+:32]) | (int_outputNumCLs[0+:32] & ~wmask[0+:32]);
  end
end

// int_treew_numcls[16-1:0]
always @(posedge aclk) begin
  if (areset)
    int_treew_numcls[0+:16] <= 16'd0;
  else if (aclk_en) begin
    if (w_hs && waddr[11:0] == LP_ADDR_TREEWNUMCLS_0)
      int_treew_numcls[0+:16] <= (wdata[0+:16] & wmask[0+:16]) | (int_treew_numcls[0+:16] & ~wmask[0+:16]);
  end
end

// int_treef_numcls[16-1:0]
always @(posedge aclk) begin
  if (areset)
    int_treef_numcls[0+:16] <= 16'd0;
  else if (aclk_en) begin
    if (w_hs && waddr[11:0] == LP_ADDR_TREEFNUMCLS_0)
      int_treef_numcls[0+:16] <= (wdata[0+:16] & wmask[0+:16]) | (int_treef_numcls[0+:16] & ~wmask[0+:16]);
  end
end

// int_prog_schedule[8-1:0]
always @(posedge aclk) begin
  if (areset)
    int_prog_schedule[0+:8] <= 8'd0;
  else if (aclk_en) begin
    if (w_hs && waddr[11:0] == LP_ADDR_PROG_SCHEDULE_0)
      int_prog_schedule[0+:8] <= (wdata[0+:8] & wmask[0+:8]) | (int_prog_schedule[0+:8] & ~wmask[0+:8]);
  end
end

// int_proc_schedule[8-1:0]
always @(posedge aclk) begin
  if (areset)
    int_proc_schedule[0+:8] <= 8'd0;
  else if (aclk_en) begin
    if (w_hs && waddr[11:0] == LP_ADDR_PROC_SCHEDULE_0)
      int_proc_schedule[0+:8] <= (wdata[0+:8] & wmask[0+:8]) | (int_proc_schedule[0+:8] & ~wmask[0+:8]);
  end
end


endmodule

`default_nettype wire

