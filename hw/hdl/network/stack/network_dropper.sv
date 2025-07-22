/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2021-2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

`timescale 1ns / 1ps

import lynxTypes::*;

`include "axi_macros.svh"
`include "lynx_macros.svh"

module network_dropper (
    // Network
    AXI4S.s                             s_axis_net,
    AXI4S.m                             m_axis_net,

    // User
    AXI4S.s                             s_axis_user,
    AXI4S.m                             m_axis_user,

`ifdef NET_DROP
    // Control
    metaIntf.s                          pckt_drop_rx,
    metaIntf.s                          pckt_drop_tx,
    input  logic                        clear_drop,
`endif

    input  wire                         nclk,
    input  wire                         nresetn
);

`ifdef NET_DROP

    logic [31:0] cnt_rx_C;
    logic [31:0] cnt_tx_C;

    // Packet counter
    always @ (posedge nclk) begin
    if(~nresetn) begin
        cnt_rx_C <= 0;
        cnt_tx_C <= 0;
    end
    else begin
        cnt_rx_C <= clear_drop ? 0 : s_axis_net.tvalid & s_axis_net.tready & s_axis_net.tlast ? cnt_rx_C + 1 : cnt_rx_C;
        cnt_tx_C <= clear_drop ? 0 : s_axis_user.tvalid & s_axis_user.tready & s_axis_user.tlast ? cnt_tx_C + 1 : cnt_tx_C;
    end
    end

    // Drop FIFO RX
    metaIntf #(.STYPE(logic [31:0])) pckt_drop_rx_int ();

    axis_data_fifo_drop_32 inst_rx_fifo_drop (
        .s_axis_aclk(nclk),
        .s_axis_aresetn(nresetn && ~clear_drop),
        .s_axis_tvalid(pckt_drop_rx.valid),
        .s_axis_tready(pckt_drop_rx.ready),
        .s_axis_tdata(pckt_drop_rx.data),
        .m_axis_tvalid(pckt_drop_rx_int.valid),
        .m_axis_tready(pckt_drop_rx_int.ready),
        .m_axis_tdata(pckt_drop_rx_int.data)
    );

    // Drop FIFO TX
    metaIntf #(.STYPE(logic [31:0])) pckt_drop_tx_int ();

    axis_data_fifo_drop_32 inst_tx_fifo_drop (
        .s_axis_aclk(nclk),
        .s_axis_aresetn(nresetn && ~clear_drop),
        .s_axis_tvalid(pckt_drop_tx.valid),
        .s_axis_tready(pckt_drop_tx.ready),
        .s_axis_tdata(pckt_drop_tx.data),
        .m_axis_tvalid(pckt_drop_tx_int.valid),
        .m_axis_tready(pckt_drop_tx_int.ready),
        .m_axis_tdata(pckt_drop_tx_int.data)
    );

    // Assign RX
    always_comb begin
        m_axis_user.tdata = s_axis_net.tdata;
        m_axis_user.tkeep = s_axis_net.tkeep;
        m_axis_user.tlast = s_axis_net.tlast;

        m_axis_user.tvalid = (pckt_drop_rx_int.valid && (cnt_rx_C == pckt_drop_rx_int.data)) ? 1'b0 : s_axis_net.tvalid;
        s_axis_net.tready = (pckt_drop_rx_int.valid && (cnt_rx_C == pckt_drop_rx_int.data)) ? 1'b1 : m_axis_user.tready;

        pckt_drop_rx_int.ready = (pckt_drop_rx_int.valid && (cnt_rx_C == pckt_drop_rx_int.data)) && (s_axis_net.tvalid & s_axis_net.tready & s_axis_net.tlast);
    end

    // Assign TX
    always_comb begin
        m_axis_net.tdata = s_axis_user.tdata;
        m_axis_net.tkeep = s_axis_user.tkeep;
        m_axis_net.tlast = s_axis_user.tlast;

        m_axis_net.tvalid = (pckt_drop_tx_int.valid && (cnt_tx_C == pckt_drop_tx_int.data)) ? 1'b0 : s_axis_user.tvalid;
        s_axis_user.tready = (pckt_drop_tx_int.valid && (cnt_tx_C == pckt_drop_tx_int.data)) ? 1'b1 : m_axis_net.tready;

        pckt_drop_tx_int.ready = (pckt_drop_tx_int.valid && (cnt_tx_C == pckt_drop_tx_int.data)) && (s_axis_user.tvalid & s_axis_user.tready & s_axis_user.tlast);
    end

    /*
    ila_drop inst_ila_drop (
        .clk(nclk),
        .probe0(s_axis_user.tvalid),
        .probe1(s_axis_user.tready),
        .probe2(s_axis_user.tlast),
        .probe3(m_axis_user.tvalid),
        .probe4(m_axis_user.tready),
        .probe5(m_axis_user.tlast),
        .probe6(s_axis_net.tvalid),
        .probe7(s_axis_net.tready),
        .probe8(s_axis_net.tlast),
        .probe9(m_axis_net.tvalid),
        .probe10(m_axis_net.tready),
        .probe11(m_axis_net.tlast),
        .probe12(clear_drop),
        .probe13(pckt_drop_rx.valid),
        .probe14(pckt_drop_rx.ready),
        .probe15(pckt_drop_rx.data), // 32
        .probe16(pckt_drop_tx.valid),
        .probe17(pckt_drop_tx.ready),
        .probe18(pckt_drop_tx.data) // 32
    );
    */

`else

    `AXIS_ASSIGN(s_axis_net, m_axis_user)
    `AXIS_ASSIGN(s_axis_user, m_axis_net)

`endif

endmodule