/*
    The Block decoder separates synchronization blocks stream from data blocks stream, extracts returned
    credits and send them to the TLK arbiter. Synchronization blocks are passed to the TLK state machine
    to react upon them, the data blocks are passed to the VCs decoder. If a CRC error received, an error
    message is passed to the TLK state machine and the received block is discarded.
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

module block_decoder (
	input   wire 										clk,    // Clock
	input   wire 										rst_n,  // Asynchronous reset active low

     //------------------ Input Block ----------------------//
    input   wire [BLOCK_WIDTH-1:0]                      blk_rx_data,
    input   wire                                        blk_rx_valid,
    input   wire                                        blk_crc_match,

	//------------------ Synch Block Detected --------------//
    /* Output from RLK to TLK */
    output  SyncBlock_t                                 rx_sync_block,              // Sync Block from RLK
    output  reg                                         rx_sync_block_valid,
    output  reg                                         rx_blk_received,          // A valid data block received
    output  reg                                         rx_blk_error,                // CRC error detected

    //------------------ Data Block Detected --------------//
    output  DataBlock_t                         		rx_data_block,
	output  wire                                		rx_data_block_valid,

	//--------- Returned Credit from Thunderx -------------//
    // Returned credit from partner to FPGA: passed to TLK Arbiter
    output  reg   [7:0]                                 credits,
    output  reg                                         hi_credits,
    output  reg                                         credits_valid              // a credits block received
);


reg                                 rx_error_received;

//////////////////////////////////////////////////////////////////////////
//////////////////////       Detected Sync Block      ////////////////////
//////////////////////////////////////////////////////////////////////////

always@(posedge clk) begin
    if(~rst_n) begin
        rx_sync_block.Crc24  <= 0;
        rx_sync_block.RxSEQ  <= 0;
        rx_sync_block.TxSEQ  <= 0;
        rx_sync_block.Req    <= 0;
        rx_sync_block.Ack    <= 0;
        rx_sync_block.Type   <= Block_Type_t'(3'b000);
        rx_sync_block.Zeros2 <= 12'b0;
        rx_sync_block.Zeros  <= 6'b0;
        rx_sync_block_valid  <= 0;
        rx_blk_error         <= 0;
        rx_blk_received      <= 1'b0;
        rx_error_received    <= 1'b0;
    end
    else begin
        rx_sync_block.Crc24  <= blk_rx_data[23:0];
        rx_sync_block.RxSEQ  <= blk_rx_data[43:36];
        rx_sync_block.TxSEQ  <= blk_rx_data[51:44];
        rx_sync_block.Req    <= blk_rx_data[53:52];
        rx_sync_block.Ack    <= blk_rx_data[60];
        rx_sync_block.Type   <= Block_Type_t'(blk_rx_data[63:61]);
        rx_sync_block.Zeros2 <= 12'b0;
        rx_sync_block.Zeros  <= 6'b0;
        rx_sync_block_valid  <= blk_rx_valid && blk_crc_match && (blk_rx_data[63:61] == BTYPE_SYNC);
        rx_blk_error         <= blk_rx_valid && !blk_crc_match;
        rx_blk_received      <= blk_rx_valid && blk_crc_match && !blk_rx_data[62] && !rx_error_received;

        if(blk_rx_valid) begin
            if(!blk_crc_match) begin
                rx_error_received <= 1'b1;
            end
            else if(blk_rx_data[63:61] == BTYPE_SYNC) begin
                rx_error_received <= 1'b0;
            end
        end
    end
end


//////////////////////////////////////////////////////////////////////////
//////////////////////       Detected Data Block      ////////////////////
//////////////////////////////////////////////////////////////////////////

assign rx_data_block_valid   = blk_rx_valid && blk_crc_match && !blk_rx_data[62] && (blk_rx_data[51:24] != 28'hfffffff);

assign rx_data_block.Crc24   = blk_rx_data[23:0];
assign rx_data_block.Type    = Block_Type_t'(blk_rx_data[63:61]);
assign rx_data_block.Ack     = blk_rx_data[60];
assign rx_data_block.Credits = blk_rx_data[59:52];

genvar i, j;
generate for (i = 0; i < 7; i=i+1) begin
    assign rx_data_block.Data[6-i] = blk_rx_data[64*(i+1) - 1 + 64:64*i + 64];
    assign rx_data_block.Vcs[6-i]  = blk_rx_data[4*(i+1) - 1 + 24:4*i + 24];
end
endgenerate

always@(posedge clk) begin
    if(~rst_n) begin
        credits       <= 8'h00;
        credits_valid <= 1'b0;
        hi_credits    <= 1'b0;
    end
    else begin
        credits       <= blk_rx_data[59:52];
        credits_valid <= blk_rx_valid && blk_crc_match && !blk_rx_data[62];
        hi_credits    <= blk_rx_data[61];
    end
end



endmodule
