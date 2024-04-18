/*
 * Systems Group, D-INFK, ETH Zurich
 *
 * Author  : A.Ramdas
 * Date    : 2021-10-22
 * Project : Enzian
 *
 */

`ifndef LINK_TLK_SV
`define LINK_TLK_SV

/*
 * Module Description:
 *  Transmit portion of the ECI link.
 *  Data from ECI FIFOs are packed into blocks based on credits available
 *  and sent via ECI.
 *  Also handles link bringup.
 *
 * Input Output Description:
 *  Input: Credits + Data to be pushed into the VCs.
 *  Output: ECI block (data frame).
 *
 * Architecture Description:
 *  link_state_machine handles ECI bringup.
 *  tlk_fifos - VC FIFOs + credit management.
 *  tlk_arb - Generate data block from VC data.
 *
 * Modifiable Parameters:
 *  None of the parameters are modifiable because of lin_packer in tlk_arb.
 *
 * Non-modifiable Parameters:
 *  All
 *
 * Notes:
 *  II = 1
 *
 */


import block_types::*;
import eci_package::*;

module link_tlk (
    input  wire                   clk,  // Clock
    input  wire                   rst_n,  // Asynchronous reset active low
    //------------------ Output to ECI Link interfaces --------------------//
    // TX
    output wire [BLOCK_WIDTH-1:0] blk_tx_data,
    input  wire                   blk_tx_ready,

    //------------------  Inputs from the Block RX Path -------------------//
    input SyncBlock_t rx_sync_block,  // Sync Block from RLK
    input wire        rx_sync_block_valid,
    input wire        rx_blk_received,  // A valid data block received
    input wire        rx_blk_error,  // CRC error detected
    input wire        rx_blk_crc_match,    // CRC valid frame received
    //----------------- Returned Credit from Thunderx ---------------------//
    // Returned credit from partner to FPGA: passed to TLK Arbiter
    input wire [7:0] credits,
    input wire       hi_credits,
    input wire       credits_valid,  // a credits block received

    //----------------- Credit to Return to Thunderx ----------------------//
    // Return credit from FPGA to partner: each set bit represents 8 credits for the corresponding vc
    input wire [12:0] return_cred,

    //--------------------------- MOB VCs Inputs --------------------------//
    // Lo VC
    input  wire [63:0] mob_lo_vc,
    input  wire        mob_lo_vc_valid,
    input  wire [ 3:0] mob_lo_vc_no,
    output wire        mob_lo_vc_ready,

    // Hi VC
    input  wire [63:0] mob_hi_vc      [8:0],
    input  wire        mob_hi_vc_valid,
    input  wire [ 3:0] mob_hi_vc_no,
    input  wire [ 2:0] mob_hi_vc_size,
    output wire        mob_hi_vc_ready,

    // Link Status
    output reg link_up,
    output  wire [5:0]  out_link_state,

    // Debug Counters
    output wire [63:0] debug_counters,
    output wire [95:0] debug_counters2,
    output wire [ 5:0] blk_trx_state
);

  // Output Block
  DataBlock_t arb_data_block;
  wire arb_data_block_valid;
  wire arb_data_block_ready;

  wire [511:0] blk_vec;

  wire [63:0] out_lo_vc;
  wire out_lo_vc_valid;
  wire [3:0] out_lo_vc_no;
  wire out_lo_vc_ready;

  // Hi VC
  wire [63:0] out_hi_vc[8:0];
  wire out_hi_vc_valid;
  wire [3:0] out_hi_vc_no;
  wire [1:0] out_hi_vc_size;
  wire out_hi_vc_ready;

  //////////////////////////////////////////////////////////////////////////
  //////////////////////    Link State Machine         /////////////////////
  //////////////////////////////////////////////////////////////////////////

  link_state_machine link_state_machine (
      .clk  (clk),
      .rst_n(rst_n),

      //--------------  Inputs from the Link RLK ---------------//
      .rx_sync_block      (rx_sync_block),
      .rx_sync_block_valid(rx_sync_block_valid),
      .rx_blk_received    (rx_blk_received),
      .rx_blk_error       (rx_blk_error),

      //--------------- Input Data from Arbiter ----------------//
      .arb_data_block      (arb_data_block),
      .arb_data_block_valid(arb_data_block_valid),
      .arb_data_block_ready(arb_data_block_ready),

      //----------------- Credits to Return --------------------//
      .rx_vc_fifo_pop(return_cred),

      .csr_init(1'b0),
      .link_up (link_up),
      .out_link_state (out_link_state),

      // Output Block
      .tx_block_out      (blk_tx_data),
      .tx_block_out_ready(blk_tx_ready),

      // Debug output
      .debug_counters (debug_counters),
      .debug_counters2(debug_counters2),
      .blk_trx_state  (blk_trx_state)

  );

  //////////////////////////////////////////////////////////////////////////
  //////////////////////          VCs Packer           /////////////////////
  //////////////////////////////////////////////////////////////////////////

  tlk_packer tlk_packer (
      .clk      (clk),
      .hi_words (mob_hi_vc),
      .hi_vc    (mob_hi_vc_no),
      .hi_size  (mob_hi_vc_size),
      .hi_valid (mob_hi_vc_valid),
      .hi_ready (mob_hi_vc_ready),
      .lo_word  (mob_lo_vc),
      .lo_vc    (mob_lo_vc_no),
      .lo_valid (mob_lo_vc_valid),
      .lo_ready (mob_lo_vc_ready),
      .out_words(arb_data_block.Data),
      .out_vc   (arb_data_block.Vcs),
      .out_valid(arb_data_block_valid),
      .out_ready(arb_data_block_ready)
  );

endmodule

`endif
