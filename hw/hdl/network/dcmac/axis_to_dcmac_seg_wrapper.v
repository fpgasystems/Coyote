
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

`timescale 1ns / 1ps

// Simple Verilog wrapper for the AXIS to DCMAC segment converter, allowing it to be included in the block diagram
module axis_to_dcmac_seg_wrapper (
    // Clock and Reset
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axis, ASSOCIATED_RESET aresetn" *)
    input wire aclk,

    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input wire aresetn,

    // AXI Stream Input
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TDATA" *)  input  wire [511:0] s_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TKEEP" *)  input  wire [63:0]  s_axis_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TLAST" *)  input  wire         s_axis_tlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TVALID" *) input  wire         s_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TREADY" *) output wire         s_axis_tready,

    // Segmented AXI stream outputs
    // Segment 0
    output wire [127:0] tx_data_0,
    output wire         tx_ena_0,
    output wire         tx_sop_0,
    output wire         tx_eop_0,
    output wire [3:0]   tx_mty_0,
    output wire         tx_err_0,

    // Segment 1
    output wire [127:0] tx_data_1,
    output wire         tx_ena_1,
    output wire         tx_sop_1,
    output wire         tx_eop_1,
    output wire [3:0]   tx_mty_1,
    output wire         tx_err_1,

    // Segment 2
    output wire [127:0] tx_data_2,
    output wire         tx_ena_2,
    output wire         tx_sop_2,
    output wire         tx_eop_2,
    output wire [3:0]   tx_mty_2,
    output wire         tx_err_2,

    // Segment 3
    output wire [127:0] tx_data_3,
    output wire         tx_ena_3,
    output wire         tx_sop_3,
    output wire         tx_eop_3,
    output wire [3:0]   tx_mty_3,
    output wire         tx_err_3,

    // Flow control
    output wire         tx_valid,
    input  wire         tx_ready
);

    axis_to_dcmac_seg inst_axis_to_dcmac_seg (
        .aclk           (aclk),
        .aresetn        (aresetn),

        .s_axis_tdata   (s_axis_tdata),
        .s_axis_tkeep   (s_axis_tkeep),
        .s_axis_tlast   (s_axis_tlast),
        .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tready  (s_axis_tready),

        .tx_data_0      (tx_data_0),
        .tx_ena_0       (tx_ena_0),
        .tx_sop_0       (tx_sop_0),
        .tx_eop_0       (tx_eop_0),
        .tx_mty_0       (tx_mty_0),
        .tx_err_0       (tx_err_0),

        .tx_data_1      (tx_data_1),
        .tx_ena_1       (tx_ena_1),
        .tx_sop_1       (tx_sop_1),
        .tx_eop_1       (tx_eop_1),
        .tx_mty_1       (tx_mty_1),
        .tx_err_1       (tx_err_1),

        .tx_data_2      (tx_data_2),
        .tx_ena_2       (tx_ena_2),
        .tx_sop_2       (tx_sop_2),
        .tx_eop_2       (tx_eop_2),
        .tx_mty_2       (tx_mty_2),
        .tx_err_2       (tx_err_2),

        .tx_data_3      (tx_data_3),
        .tx_ena_3       (tx_ena_3),
        .tx_sop_3       (tx_sop_3),
        .tx_eop_3       (tx_eop_3),
        .tx_mty_3       (tx_mty_3),
        .tx_err_3       (tx_err_3),

        .tx_valid       (tx_valid),
        .tx_ready       (tx_ready)
    );

endmodule