// /*******************************************************************************
// Copyright (c) 2018, Xilinx, Inc.
// All rights reserved.
// 
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
// 
// 1. Redistributions of source code must retain the above copyright notice,
// this list of conditions and the following disclaimer.
// 
// 
// 2. Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation
// and/or other materials provided with the distribution.
// 
// 
// 3. Neither the name of the copyright holder nor the names of its contributors
// may be used to endorse or promote products derived from this software
// without specific prior written permission.
// 
// 
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,THE IMPLIED 
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
// IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, 
// INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, 
// BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, 
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY 
// OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING 
// NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
// EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// *******************************************************************************/

import lynxTypes::*;

//`define DEBUG_CDMA_WR

module axi_dma_wr (
  // AXI Interface 
  input  wire                           aclk,
  input  wire                           aresetn,

  // Control interface
  input  wire                           ctrl_valid,
  output wire                           stat_ready,
  input  wire [AXI_ADDR_BITS-1:0]       ctrl_addr,
  input  wire [LEN_BITS-1:0]            ctrl_len,
  input  wire                           ctrl_ctl,
  output wire                           stat_done,

  output wire                           awvalid,
  input  wire                           awready,
  output wire [AXI_ADDR_BITS-1:0]       awaddr,
  output wire [0:0]                     awid,
  output wire [7:0]                     awlen,
  output wire [2:0]                     awsize,
  output wire [1:0]                     awburst,
  output wire [0:0]                     awlock,
  output wire [3:0]                     awcache,
  output wire [2:0]                     awprot,
  output wire [AXI_DATA_BITS-1:0]       wdata,
  output wire [AXI_DATA_BITS/8-1:0]     wstrb,
  output wire                           wlast,
  output wire                           wvalid,
  input  wire                           wready,
  input  wire                           bid,
  input  wire [1:0]                     bresp,
  input  wire                           bvalid,
  output wire                           bready,

  // AXI4-Stream slave interface
  input  wire                           axis_in_tvalid,
  output wire                           axis_in_tready,
  input  wire [AXI_DATA_BITS-1:0]       axis_in_tdata,
  input  wire [AXI_DATA_BITS/8-1:0]     axis_in_tkeep,
  input  wire                           axis_in_tlast
);

///////////////////////////////////////////////////////////////////////////////
// Local Parameters
///////////////////////////////////////////////////////////////////////////////
localparam integer MAX_OUTSTANDING = 8;
localparam integer AXI_MAX_BURST_LEN = 64;
localparam integer AXI_DATA_BYTES = AXI_DATA_BITS / 8;
localparam integer LOG_DATA_LEN = $clog2(AXI_DATA_BYTES);
localparam integer LOG_BURST_LEN = $clog2(AXI_MAX_BURST_LEN);
localparam integer LP_MAX_OUTSTANDING_CNTR_WIDTH = $clog2(MAX_OUTSTANDING+1); 
localparam integer LP_TRANSACTION_CNTR_WIDTH = LEN_BITS-LOG_BURST_LEN-LOG_DATA_LEN;

logic [LP_TRANSACTION_CNTR_WIDTH-1:0] num_full_bursts;
logic num_partial_bursts;

logic start;
logic [LP_TRANSACTION_CNTR_WIDTH-1:0] num_transactions;
logic has_partial_burst;
logic [LOG_BURST_LEN-1:0] final_burst_len;
logic single_transaction;

// AW
logic awvalid_r;
logic [AXI_ADDR_BITS-1:0] addr_r;
logic ctl_r;
logic aw_done;
logic aw_idle;

logic awxfer;
logic aw_final_transaction;
logic [LP_TRANSACTION_CNTR_WIDTH-1:0] aw_transactions_to_go;

// W
logic wxfer;
logic [LOG_BURST_LEN-1:0] wxfers_to_go;

logic burst_load;
logic burst_active;
logic burst_ready_snk;
logic burst_ready_src;
logic [LOG_BURST_LEN-1:0] burst_len;

// B
logic bxfer;
logic b_final_transaction;

logic b_ready_snk;

/////////////////////////////////////////////////////////////////////////////
// Control logic
/////////////////////////////////////////////////////////////////////////////
assign stat_done = bxfer & b_final_transaction;
assign stat_ready = aw_idle;

// Count the number of transfers and assert done when the last bvalid is received.
assign num_full_bursts = ctrl_len[LOG_DATA_LEN+LOG_BURST_LEN+:LEN_BITS-LOG_DATA_LEN-LOG_BURST_LEN];
assign num_partial_bursts = ctrl_len[LOG_DATA_LEN+:LOG_BURST_LEN] ? 1'b1 : 1'b0; 

always_ff @(posedge aclk, negedge aresetn) begin
  if(~aresetn) begin
    start <= 0;
  end
  else begin
    start <= ctrl_valid & stat_ready;
    if(ctrl_valid & stat_ready) begin
      num_transactions <= (num_partial_bursts == 1'b0) ? num_full_bursts - 1'b1 : num_full_bursts;
      has_partial_burst <= num_partial_bursts;
      final_burst_len <=  ctrl_len[LOG_DATA_LEN+:LOG_BURST_LEN] - 1'b1;
    end
  end
end

// Special case if there is only 1 AXI transaction. 
assign single_transaction = (num_transactions == {LP_TRANSACTION_CNTR_WIDTH{1'b0}}) ? 1'b1 : 1'b0;

///////////////////////////////////////////////////////////////////////////////
// AXI Write Address Channel
///////////////////////////////////////////////////////////////////////////////
assign awvalid = awvalid_r;
assign awaddr = addr_r;
assign awlen = aw_final_transaction ? final_burst_len : AXI_MAX_BURST_LEN - 1;
assign awsize = LOG_DATA_LEN;
assign awid = 1'b0;

assign awburst = 2'b01;
assign awlock = 1'b0;
assign awcache = 4'b0011;
assign awprot = 3'b010;

assign awxfer = awvalid & awready;

// Send aw_valid
always_ff @(posedge aclk, negedge aresetn) begin
  if (~aresetn) begin 
    awvalid_r <= 1'b0;
  end
  else begin
    awvalid_r <= ~aw_idle & ~awvalid_r & b_ready_snk ? 1'b1 : 
                 awready ? 1'b0 : awvalid_r;
  end
end

// When aw_idle, there are no transactions to issue.
always_ff @(posedge aclk, negedge aresetn) begin
  if (~aresetn) begin 
    aw_idle <= 1'b1; 
  end
  else begin 
    aw_idle <= (ctrl_valid & stat_ready) ? 1'b0 :
               aw_done    ? 1'b1 : aw_idle;
  end
end

// Increment to next address after each transaction is issued. Ctl latching.
always_ff @(posedge aclk, negedge aresetn) begin
  if (~aresetn) begin
    ctl_r <= 1'b0;
  end
  else begin
    addr_r <= (ctrl_valid & stat_ready) ? ctrl_addr :
               awxfer  ? addr_r + AXI_MAX_BURST_LEN*AXI_DATA_BYTES : addr_r;
    ctl_r <= (ctrl_valid & stat_ready) ? ctrl_ctl : ctl_r;
  end
end

// Counts down the number of transactions to send.
krnl_counter #(
  .C_WIDTH ( LP_TRANSACTION_CNTR_WIDTH         ) ,
  .C_INIT  ( {LP_TRANSACTION_CNTR_WIDTH{1'b0}} ) 
)
inst_aw_transaction_cntr ( 
  .aclk       ( aclk                   ) ,
  .clken      ( 1'b1                   ) ,
  .aresetn    ( aresetn                ) ,
  .load       ( start                  ) ,
  .incr       ( 1'b0                   ) ,
  .decr       ( awxfer                 ) ,
  .load_value ( num_transactions       ) ,
  .count      ( aw_transactions_to_go  ) ,
  .is_zero    ( aw_final_transaction   ) 
);

assign aw_done = aw_final_transaction && awxfer;

/////////////////////////////////////////////////////////////////////////////
// AXI Write Data Channel
/////////////////////////////////////////////////////////////////////////////
assign wvalid = axis_in_tvalid & burst_active;
assign wdata = axis_in_tdata;
assign wstrb = axis_in_tkeep;
assign axis_in_tready = wready & burst_active;

assign wxfer = wvalid & wready;

assign burst_load = burst_ready_src && ((wlast & wxfer) || ~burst_active);

always_ff @(posedge aclk, negedge aresetn) begin
  if (~aresetn) begin 
    burst_active <= 1'b0;
  end
  else begin
    burst_active <=  burst_load ? 1'b1 : 
                        (wlast & wxfer) ? 1'b0 : burst_active;
  end
end

krnl_counter #(
  .C_WIDTH ( LOG_BURST_LEN         ) ,
  .C_INIT  ( {LOG_BURST_LEN{1'b1}} ) 
)
inst_burst_cntr ( 
  .aclk       ( aclk            ) ,
  .clken      ( 1'b1            ) ,
  .aresetn    ( aresetn         ) ,
  .load       ( burst_load      ) ,
  .incr       ( 1'b0            ) ,
  .decr       ( wxfer           ) ,
  .load_value ( burst_len       ) ,
  .count      ( wxfers_to_go    ) ,
  .is_zero    ( wlast           ) 
);

queue #(
  .QTYPE(logic[LOG_BURST_LEN-1:0]),
  .QDEPTH(MAX_OUTSTANDING)
) burst_seq (
  .aclk(aclk),
  .aresetn(aresetn),
  .val_snk(awxfer),
  .rdy_snk(burst_ready_snk),
  .data_snk(awlen[0+:LOG_BURST_LEN]),
  .val_src(burst_load),
  .rdy_src(burst_ready_src),
  .data_src(burst_len)
);

/////////////////////////////////////////////////////////////////////////////
// AXI Write Response Channel
/////////////////////////////////////////////////////////////////////////////
assign bready = 1'b1;
assign bxfer = bready & bvalid;

queue #(
  .QTYPE(logic),
  .QDEPTH(MAX_OUTSTANDING)
) b_seq (
  .aclk(aclk),
  .aresetn(aresetn),
  .val_snk(awxfer),
  .rdy_snk(b_ready_snk),
  .data_snk(ctl_r & aw_final_transaction),
  .val_src(bxfer),
  .rdy_src(),
  .data_src(b_final_transaction)
);


/////////////////////////////////////////////////////////////////////////////
// DEBUG
/////////////////////////////////////////////////////////////////////////////
`ifdef DEBUG_CDMA_WR
    ila_dma_wr inst_ila_dma_wr (
        .clk(aclk),
        .probe0(num_full_bursts),
        .probe1(num_partial_bursts),
        .probe2(start),
        .probe3(num_transactions),
        .probe4(has_partial_burst),
        .probe5(final_burst_len),
        .probe6(single_transaction),
        .probe7(awvalid_r),
        .probe8(addr_r),
        .probe9(aw_done),
        .probe10(aw_idle),
        .probe11(awxfer),
        .probe12(aw_final_transaction),
        .probe13(aw_transactions_to_go),
        .probe14(wxfer),
        .probe15(wxfers_to_go),
        .probe16(burst_load),
        .probe17(burst_active),
        .probe18(burst_ready_snk),
        .probe19(burst_ready_src),
        .probe20(burst_len),
        .probe21(bxfer),
        .probe22(b_final_transaction),
        .probe23(b_ready_snk),
        .probe24(wvalid),
        .probe25(wready),
        .probe26(wlast)
    );
`endif

endmodule

