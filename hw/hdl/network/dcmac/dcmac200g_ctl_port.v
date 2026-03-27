// Copyright (C) 2025 Advanced Micro Devices, Inc. All rights reserved.
// SPDX-License-Identifier: MIT

`timescale 1ps/1ps

module dcmac200g_ctl_port (
    output wire [15:0] default_vl_length_100GE,
    output wire [15:0] default_vl_length_200GE_or_400GE,
    output wire [63:0] ctl_tx_vl_marker_id0,
    output wire [63:0] ctl_tx_vl_marker_id1,
    output wire [63:0] ctl_tx_vl_marker_id2,
    output wire [63:0] ctl_tx_vl_marker_id3,
    output wire [63:0] ctl_tx_vl_marker_id4,
    output wire [63:0] ctl_tx_vl_marker_id5,
    output wire [63:0] ctl_tx_vl_marker_id6,
    output wire [63:0] ctl_tx_vl_marker_id7,
    output wire [63:0] ctl_tx_vl_marker_id8,
    output wire [63:0] ctl_tx_vl_marker_id9,
    output wire [63:0] ctl_tx_vl_marker_id10,
    output wire [63:0] ctl_tx_vl_marker_id11,
    output wire [63:0] ctl_tx_vl_marker_id12,
    output wire [63:0] ctl_tx_vl_marker_id13,
    output wire [63:0] ctl_tx_vl_marker_id14,
    output wire [63:0] ctl_tx_vl_marker_id15,
    output wire [63:0] ctl_tx_vl_marker_id16,
    output wire [63:0] ctl_tx_vl_marker_id17,
    output wire [63:0] ctl_tx_vl_marker_id18,
    output wire [63:0] ctl_tx_vl_marker_id19
);

    assign default_vl_length_100GE = 16'd255;
    assign default_vl_length_200GE_or_400GE = 16'd256;
    assign ctl_tx_vl_marker_id0  = 64'hc16821003e97de00;
    assign ctl_tx_vl_marker_id1  = 64'h9d718e00628e7100;
    assign ctl_tx_vl_marker_id2  = 64'h594be800a6b41700;
    assign ctl_tx_vl_marker_id3  = 64'h4d957b00b26a8400;
    assign ctl_tx_vl_marker_id4  = 64'hf50709000af8f600;
    assign ctl_tx_vl_marker_id5  = 64'hdd14c20022eb3d00;
    assign ctl_tx_vl_marker_id6  = 64'h9a4a260065b5d900;
    assign ctl_tx_vl_marker_id7  = 64'h7b45660084ba9900;
    assign ctl_tx_vl_marker_id8  = 64'ha02476005fdb8900;
    assign ctl_tx_vl_marker_id9  = 64'h68c9fb0097360400;
    assign ctl_tx_vl_marker_id10 = 64'hfd6c990002936600;
    assign ctl_tx_vl_marker_id11 = 64'hb9915500466eaa00;
    assign ctl_tx_vl_marker_id12 = 64'h5cb9b200a3464d00;
    assign ctl_tx_vl_marker_id13 = 64'h1af8bd00e5074200;
    assign ctl_tx_vl_marker_id14 = 64'h83c7ca007c383500;
    assign ctl_tx_vl_marker_id15 = 64'h3536cd00cac93200;
    assign ctl_tx_vl_marker_id16 = 64'hc4314c003bceb300;
    assign ctl_tx_vl_marker_id17 = 64'hadd6b70052294800;
    assign ctl_tx_vl_marker_id18 = 64'h5f662a00a099d500;
    assign ctl_tx_vl_marker_id19 = 64'hc0f0e5003f0f1a00;

endmodule