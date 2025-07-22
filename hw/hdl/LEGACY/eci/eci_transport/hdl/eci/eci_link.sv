/*
    Copyright (c) 2022 ETH Zurich.
    All rights reserved.

    This file is distributed under the terms in the attached LICENSE file.
    If you do not find this file, copies can be found by writing to:
    ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
*/

`ifndef ECI_LINK_SV
`define ECI_LINK_SV
import block_types::*;
import eci_package::*;

module eci_link #
(
    parameter AXI_ADDR_WIDTH = 36,
    parameter AXI_DATA_WIDTH = WORD_WIDTH,
    parameter AXI_STRB_WIDTH = (AXI_DATA_WIDTH / 8)
) (
    input wire clk,  // Clock
    input wire reset,  // Actrlbtype_is_synchronous reset active high

    //------------------ I/O to/from ECI Link interfaces -------------------//
    // RX
    input wire [BLOCK_WIDTH-1:0] blk_rx_data,
    input wire                   blk_rx_valid,
    input wire                   blk_crc_match,

    // TX
    output wire [BLOCK_WIDTH-1:0] blk_tx_data,
    input  wire                   blk_tx_ready,

    output wire [WORD_WIDTH-1:0]    mib_data[6:0],
    output wire [3:0]               mib_vc_no[6:0],
    output reg [6:0]                mib_we2,
    output reg [6:0]                mib_we3,
    output reg [6:0]                mib_we4,
    output reg [6:0]                mib_we5,
    output wire                     mib_valid,
    input  wire [12:0]              mib_credit_return,

    //--------------------------- MOB VCs Inputs ----------------------------//
    // Lo bandwidth VC
    input  wire [63:0] mob_lo_data,
    input  wire        mob_lo_valid,
    input  wire [ 3:0] mob_lo_vc_no,
    output wire        mob_lo_ready,

    // Hi bandwidth VC
    input  wire [63:0] mob_hi_data  [8:0],
    input  wire        mob_hi_valid,
    input  wire [ 3:0] mob_hi_vc_no,
    input  wire [ 2:0] mob_hi_size,
    output wire        mob_hi_ready,

    output  wire [12:0] mob_credit_return,

    output reg link_up,
    output wire [5:0] link_state
);

    // declare signals
    wire rst_n;
    SyncBlock_t rx_sync_block;  // Sync Block from RLK
    wire rx_sync_block_valid;
    wire rx_blk_received;  // A valid data block received
    wire rx_blk_error;

    wire [7:0] credits;
    wire hi_credits;
    wire credits_valid;

    // Pipeline registers for timing
    (* DONT_TOUCH="true" *) logic [BLOCK_WIDTH-1:0] blk_rx_data_reg;
    (* DONT_TOUCH="true" *) logic blk_rx_valid_reg;
    (* DONT_TOUCH="true" *) logic blk_crc_match_reg;

    //*******************************************************************************//
    //*******************************************************************************//
    //*******************************************************************************//
    //*******************************************************************************//

    wire [WORD_WIDTH-1:0] vio_cmd;
    wire vio_send;
    //*******************************************************************************//
    //*******************************************************************************//
    //*******************************************************************************//
    //*******************************************************************************//

    //*******************************************************************************//
    //*******************************************************************************//
    //*******************************************************************************//
    //*******************************************************************************//

    function [6:0] get_word_enable;
        input [27:0] vcs;
        input [3:0] vc;
        begin
            get_word_enable[6] = vcs[3:0] == vc;
            get_word_enable[5] = vcs[7:4] == vc;
            get_word_enable[4] = vcs[11:8] == vc;
            get_word_enable[3] = vcs[15:12] == vc;
            get_word_enable[2] = vcs[19:16] == vc;
            get_word_enable[1] = vcs[23:20] == vc;
            get_word_enable[0] = vcs[27:24] == vc;
        end
    endfunction

    assign rst_n = ~reset;
    //////////////////////////////////////////////////////////////////////////
    //////////////////////       Link RLK Module         /////////////////////
    //////////////////////////////////////////////////////////////////////////

    //Adding a pipeline register for timing
    always @(posedge clk) begin
        mib_we2 <= get_word_enable(blk_rx_data[51:24], 4'b0010);
        mib_we3 <= get_word_enable(blk_rx_data[51:24], 4'b0011);
        mib_we4 <= get_word_enable(blk_rx_data[51:24], 4'b0100);
        mib_we5 <= get_word_enable(blk_rx_data[51:24], 4'b0101);
        blk_rx_data_reg <= blk_rx_data;
        blk_rx_valid_reg <= blk_rx_valid;
        blk_crc_match_reg <= blk_crc_match;
    end

  ///////////////////////////////////////////////////////////////////////////////////////////////////

  link_rlk rlk (
      .clk  (clk),
      .rst_n(rst_n),

      //------------------ Input Block ----------------------//
      .blk_rx_data  (blk_rx_data_reg),
      .blk_rx_valid (blk_rx_valid_reg),
      .blk_crc_match(blk_crc_match_reg),

        .mib_data           (mib_data),
        .mib_vc_no          (mib_vc_no),
        .mib_valid          (mib_valid),

      //------------------ Synch Block Detected -------------//
      .rx_sync_block      (rx_sync_block),
      .rx_sync_block_valid(rx_sync_block_valid),
      .rx_blk_received    (rx_blk_received),
      .rx_blk_error       (rx_blk_error),

      //--------- Returned Credit from Thunderx -------------//
      .credits      (credits),
      .hi_credits   (hi_credits),
      .credits_valid(credits_valid),

      //---------------- Debug Interface --------------------//
      .debug_counters(),
      .rcvd_cmds     ()
  );

  ////////////////////////////////////
  link_tlk tlk (
      .clk  (clk),
      .rst_n(rst_n),

      //------------------ Output Block to Thunderx ------------------//
      .blk_tx_data (blk_tx_data),
      .blk_tx_ready(blk_tx_ready),

      //--------------------- Received Synch Block -------------------//
      .rx_sync_block        (rx_sync_block),
      .rx_sync_block_valid  (rx_sync_block_valid),
      .rx_blk_received      (rx_blk_received),
      .rx_blk_error         (rx_blk_error),
      .rx_blk_crc_match     (blk_crc_match_reg),

      //----------------- Returned Credit from Thunderx --------------//
      .credits      (credits),
      .hi_credits   (hi_credits),
      .credits_valid(credits_valid),

      //----------------- Credit to Return to Thunderx ---------------//
      .return_cred(mib_credit_return),

      //---------------- VCs Data Words TO SEND ------------//
      .mob_lo_vc      (mob_lo_data),
      .mob_lo_vc_valid(mob_lo_valid),
      .mob_lo_vc_no   (mob_lo_vc_no),
      .mob_lo_vc_ready(mob_lo_ready),
      .mob_hi_vc      (mob_hi_data),
      .mob_hi_vc_valid(mob_hi_valid),
      .mob_hi_vc_no   (mob_hi_vc_no),
      .mob_hi_vc_size (mob_hi_size),
      .mob_hi_vc_ready(mob_hi_ready),
      //--------------- Link status to block com module --------------//
      .link_up        (link_up),
      .out_link_state (link_state),

      //---------------------- Debug Interface -----------------------//
      .debug_counters (),
      .debug_counters2(),
      .blk_trx_state  ()
  );

genvar i;
generate for (i = 0; i < 8; i=i+1) begin
    assign mob_credit_return[i] = credits[i] ? credits_valid && !hi_credits : 0;
end
endgenerate
generate for (i = 8; i < 13; i=i+1) begin
    assign mob_credit_return[i] = credits[i-8] ? credits_valid && hi_credits : 0;
end
endgenerate

endmodule
`endif
