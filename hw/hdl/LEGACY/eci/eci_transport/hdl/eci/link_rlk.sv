
/*
    This is the Receiver channel of the ECI link. It consumes incoming blocks from the lower layer
    and decode the blocks, separate their contents into different VCs, and manage credits on the
    different VCs.
*/

/*
    Copyright (c) 2022 ETH Zurich.
    All rights reserved.

    This file is distributed under the terms in the attached LICENSE file.
    If you do not find this file, copies can be found by writing to:
    ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
*/

import block_types::*;
import eci_package::*;

module link_rlk (
    input  wire clk,    // Clock
    input  wire rst_n,  // Asynchronous reset active low

     //------------------ Input Block ----------------------//
    input   wire [BLOCK_WIDTH-1:0]                      blk_rx_data,
    input   wire                                        blk_rx_valid,
    input   wire                                        blk_crc_match,

    //---------------- VCs Data Words Received ------------//
    output wire [WORD_WIDTH-1:0]    mib_data[6:0],
    output wire [3:0]               mib_vc_no[6:0],
    output wire                     mib_valid,
    input  wire                     mib_ready,

    //------------------ Synch Block Detected -------------//
    /* Output from RLK to TLK */
    output  SyncBlock_t                                 rx_sync_block,              // Sync Block from RLK
    output  wire                                        rx_sync_block_valid,
    output  wire                                        rx_blk_received,          // A valid data block received
    output  wire                                        rx_blk_error,                // CRC error detected

    //--------- Returned Credit from Thunderx -------------//
    // Returned credit from partner to FPGA: passed to TLK Arbiter
    output  wire  [7:0]                                 credits,
    output  wire                                        hi_credits,
    output  wire                                        credits_valid,             // a credits block received

    //---------------- Debug Interface --------------------//
    // Debug Counters
    output  wire  [127:0]                               debug_counters,
    output  reg   [63:0]                                rcvd_cmds[2:0]
);



////////////////////////////////////////////////////////////////////////////
//////////////////////      Signals Declaration      /////////////////////
//////////////////////////////////////////////////////////////////////////
//
DataBlock_t                         rx_data_block;
wire                                rx_data_block_valid;

//////////////////////////////////////////////////////////////////////////
//////////////////////          Block Decoder         ////////////////////
//////////////////////////////////////////////////////////////////////////

block_decoder block_decoder(
    .clk                        (clk),
    .rst_n                      (rst_n),
    .blk_rx_data                (blk_rx_data),
    .blk_rx_valid               (blk_rx_valid),
    .blk_crc_match              (blk_crc_match),
    .rx_sync_block              (rx_sync_block),
    .rx_sync_block_valid        (rx_sync_block_valid),
    .rx_blk_received            (rx_blk_received),
    .rx_blk_error               (rx_blk_error),
    .rx_data_block              (rx_data_block),
    .rx_data_block_valid        (rx_data_block_valid),
    .credits                    (credits),
    .hi_credits                 (hi_credits),
    .credits_valid              (credits_valid)
);

//////////////////////////////////////////////////////////////////////////
//////////////////////////////       VCs FIFO        /////////////////////
//////////////////////////////////////////////////////////////////////////

assign mib_data = {rx_data_block.Data[6], rx_data_block.Data[5], rx_data_block.Data[4], rx_data_block.Data[3], rx_data_block.Data[2], rx_data_block.Data[1], rx_data_block.Data[0]};
assign mib_vc_no = {rx_data_block.Vcs[6], rx_data_block.Vcs[5], rx_data_block.Vcs[4], rx_data_block.Vcs[3], rx_data_block.Vcs[2], rx_data_block.Vcs[1], rx_data_block.Vcs[0]};
assign mib_valid = rx_data_block_valid;

endmodule
