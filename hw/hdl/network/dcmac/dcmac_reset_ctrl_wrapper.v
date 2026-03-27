
/**
 * This file is part of Coyote <https://github.com/fpgasystems/Coyote>
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

// Simple Verilog wrapper for the DCMAC reset controller, allowing it to be included in the block diagram
module dcmac_reset_ctrl_wrapper (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 sys_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET gt_reset:tx_serdes_reset:rx_serdes_reset" *)
    input  wire        sys_clk,

    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 dcmac_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET axis_resetn:tx_core_reset:rx_core_reset:tx_chan_flush:rx_chan_flush" *)
    input  wire        dcmac_clk,

    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 async_resetn RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire        async_resetn,

    input  wire        gt_reset_done_tx,
    input  wire        gt_reset_done_rx,

    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 gt_reset RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
    output wire        gt_reset,

    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 tx_core_reset RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
    output wire        tx_core_reset,

    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 tx_chan_flush RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
    output wire [5:0]  tx_chan_flush,

    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 tx_serdes_reset RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
    output wire [5:0]  tx_serdes_reset,

    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rx_core_reset RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
    output wire        rx_core_reset,

    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rx_serdes_reset RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
    output wire [5:0]  rx_serdes_reset,

    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rx_chan_flush RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
    output wire [5:0]  rx_chan_flush,

    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 axis_resetn RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    output wire        axis_resetn
);

    dcmac_reset_ctrl inst_dcmac_reset_ctrl (
        .sys_clk          (sys_clk),
        .dcmac_clk        (dcmac_clk),
        .async_resetn     (async_resetn),
        .gt_reset         (gt_reset),
        .gt_reset_done_tx (gt_reset_done_tx),
        .gt_reset_done_rx (gt_reset_done_rx),
        .tx_core_reset    (tx_core_reset),
        .tx_chan_flush    (tx_chan_flush),
        .tx_serdes_reset  (tx_serdes_reset),
        .rx_core_reset    (rx_core_reset),
        .rx_serdes_reset  (rx_serdes_reset),
        .rx_chan_flush    (rx_chan_flush),
        .axis_resetn      (axis_resetn)
    );

endmodule