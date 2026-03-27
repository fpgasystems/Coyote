/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025-2026, Systems Group, ETH Zurich
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
import lynxTypes::*;

`include "axi_macros.svh"
`include "lynx_macros.svh"

/**
  * @brief Host networking clock crossing network late 
  * The clock crossing from nclk -> aclk
  */ 
module host_networking_ccross_net_late #(
    // Configure whether an actual clock crossing is needed, otherwise it's just a buffer 
    parameter integer ENABLED = 0
) (
    // ACLK side 
    AXI4S.s s_axis_host_tx_aclk, 
    AXI4S.m m_axis_host_rx_aclk, 

    // NCLK side 
    AXI4S.m m_axis_host_tx_nclk, 
    AXI4S.s s_axis_host_rx_nclk, 

    // Clocks and resets 
    input wire aclk, 
    input wire aresetn, 
    input wire nclk,
    input wire nresetn
); 

    if(ENABLED == 1) begin 
        // TX-traffic clock crossing 
        axis_data_fifo_host_networking_ccross_data_512 inst_host_tx_traffic (
            .m_axis_aclk(nclk), 
            .s_axis_aclk(aclk), 
            .s_axis_aresetn(aresetn),
            .s_axis_tvalid(s_axis_host_tx_aclk.tvalid),
            .s_axis_tready(s_axis_host_tx_aclk.tready),
            .s_axis_tdata (s_axis_host_tx_aclk.tdata),
            .s_axis_tkeep (s_axis_host_tx_aclk.tkeep),
            .s_axis_tlast (s_axis_host_tx_aclk.tlast),
            .m_axis_tvalid(m_axis_host_tx_nclk.tvalid),
            .m_axis_tready(m_axis_host_tx_nclk.tready),
            .m_axis_tdata (m_axis_host_tx_nclk.tdata),
            .m_axis_tkeep (m_axis_host_tx_nclk.tkeep),
            .m_axis_tlast (m_axis_host_tx_nclk.tlast)
        ); 

        // RX-traffic clock crossing 
        axis_data_fifo_host_networking_ccross_data_512 inst_host_rx_traffic (
            .m_axis_aclk(aclk), 
            .s_axis_aclk(nclk), 
            .s_axis_aresetn(nresetn),
            .s_axis_tvalid(s_axis_host_rx_nclk.tvalid),
            .s_axis_tready(s_axis_host_rx_nclk.tready),
            .s_axis_tdata (s_axis_host_rx_nclk.tdata),
            .s_axis_tkeep (s_axis_host_rx_nclk.tkeep),
            .s_axis_tlast (s_axis_host_rx_nclk.tlast),
            .m_axis_tvalid(m_axis_host_rx_aclk.tvalid),
            .m_axis_tready(m_axis_host_rx_aclk.tready),
            .m_axis_tdata (m_axis_host_rx_aclk.tdata),
            .m_axis_tkeep (m_axis_host_rx_aclk.tkeep),
            .m_axis_tlast (m_axis_host_rx_aclk.tlast)
        );

    end else begin 
        // If no clock crossing is needed, just decouple the signals through a FIFO-buffer 

        // TX-traffic buffering 
        axis_data_fifo_host_networking_data_512 inst_host_tx_traffic (
            .s_axis_aclk(aclk),
            .s_axis_aresetn(aresetn),
            .s_axis_tvalid(s_axis_host_tx_aclk.tvalid),
            .s_axis_tready(s_axis_host_tx_aclk.tready),
            .s_axis_tdata (s_axis_host_tx_aclk.tdata),
            .s_axis_tkeep (s_axis_host_tx_aclk.tkeep),
            .s_axis_tlast (s_axis_host_tx_aclk.tlast),
            .m_axis_tvalid(m_axis_host_tx_nclk.tvalid),
            .m_axis_tready(m_axis_host_tx_nclk.tready),
            .m_axis_tdata (m_axis_host_tx_nclk.tdata),
            .m_axis_tkeep (m_axis_host_tx_nclk.tkeep),
            .m_axis_tlast (m_axis_host_tx_nclk.tlast)
        ); 

        // RX-traffic buffering 
        axis_data_fifo_host_networking_data_512 inst_host_rx_traffic (
            .s_axis_aclk(aclk),
            .s_axis_aresetn(aresetn),
            .s_axis_tvalid(s_axis_host_rx_nclk.tvalid),
            .s_axis_tready(s_axis_host_rx_nclk.tready),
            .s_axis_tdata (s_axis_host_rx_nclk.tdata),
            .s_axis_tkeep (s_axis_host_rx_nclk.tkeep),
            .s_axis_tlast (s_axis_host_rx_nclk.tlast),
            .m_axis_tvalid(m_axis_host_rx_aclk.tvalid),
            .m_axis_tready(m_axis_host_rx_aclk.tready),
            .m_axis_tdata (m_axis_host_rx_aclk.tdata),
            .m_axis_tkeep (m_axis_host_rx_aclk.tkeep),
            .m_axis_tlast (m_axis_host_rx_aclk.tlast)
        ); 

    end 

endmodule
