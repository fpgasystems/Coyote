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

/**
 * @brief   TCP clock crossing (network/aclk <-> user/uclk), data path only
 *
 * The TCP management interfaces (listen, open, close) are NOT part of this crossing: they are driven by the MMU
 * (cnfg_slave) and stay in the aclk domain. RX data comes from tcp_rx with tid = dest; the descriptors
 * (rq_wr, sq_rd, cq_rd, sq_wr, cq_wr) use the generic meta crossings.
 *
 */
module tcp_ccross_ul (
    // Network
    AXI4S.m                m_axis_tcp_tx_nclk, 
    AXI4SR.s               s_axis_tcp_rx_nclk,
    
    // User        
    AXI4S.s                s_axis_tcp_tx_aclk,      
    AXI4SR.m               m_axis_tcp_rx_aclk,

    input  wire             nclk,
    input  wire             nresetn,
    input  wire             aclk,
    input  wire             aresetn
);

// ---------------------------------------------------------------------------------------------------
// Crossings
// ---------------------------------------------------------------------------------------------------

    // TX data
    axis_clock_converter_tcp_512 inst_tcp_tx_data (
        .m_axis_aclk(nclk),
        .s_axis_aclk(aclk),
        .s_axis_aresetn(aresetn),
        .m_axis_aresetn(nresetn),
        .s_axis_tvalid(s_axis_tcp_tx_aclk.tvalid),
        .s_axis_tready(s_axis_tcp_tx_aclk.tready),
        .s_axis_tdata (s_axis_tcp_tx_aclk.tdata),
        .s_axis_tkeep (s_axis_tcp_tx_aclk.tkeep),
        .s_axis_tlast (s_axis_tcp_tx_aclk.tlast),
        .m_axis_tvalid(m_axis_tcp_tx_nclk.tvalid),
        .m_axis_tready(m_axis_tcp_tx_nclk.tready),
        .m_axis_tdata (m_axis_tcp_tx_nclk.tdata),
        .m_axis_tkeep (m_axis_tcp_tx_nclk.tkeep),
        .m_axis_tlast (m_axis_tcp_tx_nclk.tlast)
    );

    axisr_clock_converter_tcp_512 inst_rx_data (
        .m_axis_aclk(aclk),
        .s_axis_aclk(nclk),
        .s_axis_aresetn(nresetn),
        .m_axis_aresetn(aresetn),
        .s_axis_tvalid(s_axis_tcp_rx_nclk.tvalid),
        .s_axis_tready(s_axis_tcp_rx_nclk.tready),
        .s_axis_tdata (s_axis_tcp_rx_nclk.tdata),
        .s_axis_tkeep (s_axis_tcp_rx_nclk.tkeep),
        .s_axis_tid   (s_axis_tcp_rx_nclk.tid),
        .s_axis_tlast (s_axis_tcp_rx_nclk.tlast),
        .m_axis_tvalid(m_axis_tcp_rx_aclk.tvalid),
        .m_axis_tready(m_axis_tcp_rx_aclk.tready),
        .m_axis_tdata (m_axis_tcp_rx_aclk.tdata),
        .m_axis_tkeep (m_axis_tcp_rx_aclk.tkeep),
        .m_axis_tid   (m_axis_tcp_rx_aclk.tid),
        .m_axis_tlast (m_axis_tcp_rx_aclk.tlast)
    );

endmodule