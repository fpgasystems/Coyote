
/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2026, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

/// State machine for driving resets of the DCMAC, GT transceivers, and AXIS segmenters.
///
/// Clock domains:
///   sys_clk        - Free-running clock; also drives gtwiz_freerunning_clk
///   dcmac_core_clk - DCMAC Core Clock (780 MHz)
///   dcmac_axis_clk - DCMAC AXIS Clock (391 MHz)
///
/// Input reset:
///   async_resetn   - Active-low reset from the shell, needs to be synchronized to sys_clk
///
module dcmac_reset_ctrl (
    // Input clocks, reset
    input  logic        sys_clk,
    input  logic        dcmac_core_clk,
    input  logic        dcmac_axis_clk,
    input  logic        async_resetn,

    // GT transceiver reset — active-high, sys_clk domain, no CDC required
    output logic        gt_reset,
    input  logic        gt_reset_done_tx,
    input  logic        gt_reset_done_rx,

    // DCMAC TX resets, active-high
    output logic        tx_core_reset,
    output logic [5:0]  tx_chan_flush,
    output logic [5:0]  tx_serdes_reset,

    // DCMAC RX resets, active-high
    output logic        rx_core_reset,  
    output logic [5:0]  rx_serdes_reset,
    output logic [5:0]  rx_chan_flush, 

    // AXIS FIFOs & segmenters reset, active-low
    output logic        axis_resetn
);

localparam integer LONG_WAIT_CYCLES = 6_000_000;

// FSM
typedef enum logic [4:0] {
    ST_INIT,
    ST_RESET_GT_AND_AXIS,
    ST_WAIT_GT_RST,
    ST_WAIT_INT_1,
    ST_RST_DCMAC_TX,
    ST_RST_DCMAC_TX_WAIT_1,
    ST_RST_DCMAC_TX_WAIT_2,
    ST_RST_DCMAC_TX_WAIT_3,
    ST_WAIT_INT_2,
    ST_RST_DCMAC_RX,
    ST_RST_DCMAC_RX_WAIT_1,
    ST_RST_DCMAC_RX_WAIT_2,
    ST_RST_DCMAC_RX_WAIT_3,
    ST_DONE
} state_t;

state_t      rst_state;
logic [31:0] clk_cnt;

// Pre-CDC signals; in sys_clk domain
logic        gt_reset_src;
logic [5:0]  tx_serdes_reset_src;
logic [5:0]  rx_serdes_reset_src;
logic        tx_core_reset_src;
logic [5:0]  tx_chan_flush_src;
logic        rx_core_reset_src;
logic [5:0]  rx_chan_flush_src;
logic        axis_resetn_src;

// Register GT reset done signals, in case they are not aligned in the same clock cycle
logic gt_reset_done_tx_r;
logic gt_reset_done_rx_r;

// Synchronize async_resetn to sys_clk domain
logic sys_resetn;
xpm_cdc_async_rst #(
    .DEST_SYNC_FF    (4),
    .INIT_SYNC_FF    (0),
    .RST_ACTIVE_HIGH (0)
) u_cdc_sys_resetn (
    .src_arst  (async_resetn),
    .dest_clk  (sys_clk),
    .dest_arst (sys_resetn)
);

always_ff @(posedge sys_clk) begin
    if (sys_resetn == 1'b0) begin
        gt_reset_done_tx_r <= 1'b0;
        gt_reset_done_rx_r <= 1'b0;
    end else begin
        if (gt_reset_done_tx) gt_reset_done_tx_r <= 1'b1;
        if (gt_reset_done_rx) gt_reset_done_rx_r <= 1'b1;
    end
end

// Reset FSM
// AXIS reset is kept in reset until entire reset sequence is complete preventing any packets in either direction
always_ff @(posedge sys_clk) begin
    if (sys_resetn == 1'b0) begin
        rst_state <= ST_INIT;

        gt_reset_src <= 1'b0;
        tx_core_reset_src <= 1'b0;
        tx_chan_flush_src <= 6'b0;
        tx_serdes_reset_src <= 6'b0;
        rx_core_reset_src <= 1'b0;
        rx_serdes_reset_src <= 6'b0;
        rx_chan_flush_src <= 6'b0;
        axis_resetn_src <= 1'b0;   
        
        clk_cnt <= 32'b0;
    end else begin
        case (rst_state)
            // Short wait before kicking off reset sequence
            ST_INIT: begin
                if (clk_cnt == 32'd127) begin
                    clk_cnt <= 32'b0;
                    gt_reset_src <= 1'b1;
                    axis_resetn_src <= 1'b0;
                    rst_state <= ST_RESET_GT_AND_AXIS;
                end else begin
                    clk_cnt <= clk_cnt + 1;
                end
            end

            // Hold GT reset for 8 cycles (though 1 cc should be sufficient)
            ST_RESET_GT_AND_AXIS: begin
                if (clk_cnt == 32'd7) begin
                    clk_cnt <= 32'b0;
                    gt_reset_src <= 1'b0;
                    rst_state <= ST_WAIT_GT_RST;
                end else begin
                    clk_cnt <= clk_cnt + 1;
                end
            end

            // Wait for GT internal reset handshake to complete
            ST_WAIT_GT_RST: begin
                if (gt_reset_done_tx_r && gt_reset_done_rx_r) begin
                    clk_cnt <= 32'b0;
                    rst_state <= ST_WAIT_INT_1;
                end
            end

            // Brief wait before reseting DCMAC
            ST_WAIT_INT_1: begin
                if (clk_cnt == 32'd127) begin
                    clk_cnt <= 32'b0;
                    rst_state <= ST_RST_DCMAC_TX;
                end else begin
                    clk_cnt <= clk_cnt + 1;
                end
            end

            // Assert all DCMAC TX resets simultaneously
            ST_RST_DCMAC_TX: begin
                tx_core_reset_src <= 1'b1;
                tx_chan_flush_src <= 6'b111111;
                tx_serdes_reset_src <= 6'b111111;
                clk_cnt <= 32'b0;
                rst_state <= ST_RST_DCMAC_TX_WAIT_1;
            end

            // Per DCMAC specification, wait before releasing TX serdes reset first
            ST_RST_DCMAC_TX_WAIT_1: begin
                if (clk_cnt == 32'd63) begin
                    clk_cnt <= 32'b0;
                    tx_serdes_reset_src <= 6'b111100;
                    rst_state <= ST_RST_DCMAC_TX_WAIT_2;
                end else begin
                    clk_cnt <= clk_cnt + 1;
                end
            end

            // Per DCMAC specification, release core reset after
            ST_RST_DCMAC_TX_WAIT_2: begin
                if (clk_cnt == 32'd63) begin
                    clk_cnt <= 32'b0;
                    tx_core_reset_src <= 1'b0;
                    rst_state <= ST_RST_DCMAC_TX_WAIT_3;
                end else begin
                    clk_cnt <= clk_cnt + 1;
                end
            end

            // No stat_tx_local_fault port (only register), but we add a longer wait for reset to complete correctly before de-asserting
            ST_RST_DCMAC_TX_WAIT_3: begin
                if (clk_cnt == LONG_WAIT_CYCLES) begin
                    clk_cnt <= 32'b0;
                    tx_chan_flush_src <= 6'b111100;
                    rst_state <= ST_WAIT_INT_2;
                end else begin
                    clk_cnt <= clk_cnt + 1;
                end
            end

            // Short wait before asserting DCMAC reset
            ST_WAIT_INT_2: begin
                if (clk_cnt == 32'd63) begin
                    clk_cnt <= 32'b0;
                    rst_state <= ST_RST_DCMAC_RX;
                end else begin
                    clk_cnt <= clk_cnt + 1;
                end
            end

            // Assert all DCMAC RX resets simultaneously
            ST_RST_DCMAC_RX: begin
                rx_core_reset_src <= 1'b1;
                rx_chan_flush_src <= 6'b111111;
                rx_serdes_reset_src <= 6'b111111;
                clk_cnt <= 32'b0;
                rst_state <= ST_RST_DCMAC_RX_WAIT_1;
            end

            // Wait 64cc before releasing RX core reset first (per DCMAC specification)
            ST_RST_DCMAC_RX_WAIT_1: begin
                if (clk_cnt == 32'd63) begin
                    clk_cnt <= 32'b0;
                    rx_core_reset_src <= 1'b0;
                    rst_state <= ST_RST_DCMAC_RX_WAIT_2;
                end else begin
                    clk_cnt <= clk_cnt + 1;
                end
            end

            // Wait 64cc before releasing RX chan flush for active ports only
            ST_RST_DCMAC_RX_WAIT_2: begin
                if (clk_cnt == 32'd63) begin
                    clk_cnt <= 32'b0;
                    rx_chan_flush_src <= 6'b111100;
                    rst_state <= ST_RST_DCMAC_RX_WAIT_3;
                end else begin
                    clk_cnt <= clk_cnt + 1;
                end
            end

            // Finally, release RX serdes for active ports only
            // Also, deassert AXIS reset
            ST_RST_DCMAC_RX_WAIT_3: begin
                if (clk_cnt == 32'd63) begin
                    clk_cnt <= 32'b0;
                    rx_serdes_reset_src <= 6'b111100;
                    axis_resetn_src <= 1'b1;
                    rst_state <= ST_DONE;
                end else begin
                    clk_cnt <= clk_cnt + 1;
                end
            end

            ST_DONE: begin
                // Steady-state, stay here
            end

            default: begin
                gt_reset_src  <= 1'b0;
                tx_core_reset_src <= 1'b0;
                tx_chan_flush_src <= 6'b111100;
                tx_serdes_reset_src <= 6'b111100;
                rx_core_reset_src <= 1'b0;
                rx_chan_flush_src <= 6'b111100;
                rx_serdes_reset_src <= 6'b111100;
                axis_resetn_src <= 1'b1;
                clk_cnt <= 32'b0;
                rst_state <= ST_DONE;
            end
        endcase
    end
end

// No clock synchronization required for these signals
assign gt_reset        = gt_reset_src;
assign tx_serdes_reset = tx_serdes_reset_src;
assign rx_serdes_reset = rx_serdes_reset_src;

// Signals requiring synchronization
xpm_cdc_async_rst #(
    .DEST_SYNC_FF    (4),
    .INIT_SYNC_FF    (0),
    .RST_ACTIVE_HIGH (1)
) u_cdc_tx_core_reset (
    .src_arst  (tx_core_reset_src),
    .dest_clk  (dcmac_core_clk),
    .dest_arst (tx_core_reset)
);

xpm_cdc_async_rst #(
    .DEST_SYNC_FF    (4),
    .INIT_SYNC_FF    (0),
    .RST_ACTIVE_HIGH (1)
) u_cdc_rx_core_reset (
    .src_arst  (rx_core_reset_src),
    .dest_clk  (dcmac_core_clk),
    .dest_arst (rx_core_reset)
);

xpm_cdc_array_single #(
    .DEST_SYNC_FF   (4),
    .INIT_SYNC_FF   (0),
    .SIM_ASSERT_CHK (1),
    .SRC_INPUT_REG  (1),
    .WIDTH          (6)
) u_cdc_tx_chan_flush (
    .src_clk  (sys_clk),
    .src_in   (tx_chan_flush_src),
    .dest_clk (dcmac_axis_clk),
    .dest_out (tx_chan_flush)
);

xpm_cdc_array_single #(
    .DEST_SYNC_FF   (4),
    .INIT_SYNC_FF   (0),
    .SIM_ASSERT_CHK (1),
    .SRC_INPUT_REG  (1),
    .WIDTH          (6)
) u_cdc_rx_chan_flush (
    .src_clk  (sys_clk),
    .src_in   (rx_chan_flush_src),
    .dest_clk (dcmac_axis_clk),
    .dest_out (rx_chan_flush)
);

xpm_cdc_async_rst #(
    .DEST_SYNC_FF    (4),
    .INIT_SYNC_FF    (0),
    .RST_ACTIVE_HIGH (0) 
) u_cdc_axis_resetn (
    .src_arst  (axis_resetn_src),
    .dest_clk  (dcmac_axis_clk),
    .dest_arst (axis_resetn)
);

endmodule