/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2021-2026, Systems Group, ETH Zurich
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

/**
 * @brief   DENIM top level
 *
 * In-path network impairment on the RX stream, between the CMAC and the IP
 * handler, and ahead of the packet sniffer tap so that captures show the
 * traffic as the RDMA stack will see it.
 *
 * This module is the only part of DENIM that knows about Coyote.
 *
 * With no rule armed the chain is transparent apart from the delay FIFO's
 * cut-through latency.
 */
module denim_top (
    /* Network stream, nclk domain */
    AXI4S.s                     s_axis_net,
    AXI4S.m                     m_axis_net,

    /* Config in and register mirror out, crossed from aclk in network_top */
    metaIntf.s                  s_denim_cnfg,
    metaIntf.m                  m_denim_stat,

    input  wire                 nclk,
    input  wire                 nresetn_r
);

// FIFO_BEATS sets how much delay the block can hold at line rate
denim_chain #(
    .DATA_BITS      (AXI_NET_BITS),
    .FIFO_BEATS     (512),
    .META_ENTRIES   (256),
    .PMTU_BYTES     (PMTU_BYTES)
) inst_chain (
    .s_axis_tdata   (s_axis_net.tdata),
    .s_axis_tkeep   (s_axis_net.tkeep),
    .s_axis_tlast   (s_axis_net.tlast),
    .s_axis_tvalid  (s_axis_net.tvalid),
    .s_axis_tready  (s_axis_net.tready),

    .m_axis_tdata   (m_axis_net.tdata),
    .m_axis_tkeep   (m_axis_net.tkeep),
    .m_axis_tlast   (m_axis_net.tlast),
    .m_axis_tvalid  (m_axis_net.tvalid),
    .m_axis_tready  (m_axis_net.tready),

    .s_cnfg_tdata   (s_denim_cnfg.data),
    .s_cnfg_tvalid  (s_denim_cnfg.valid),
    .s_cnfg_tready  (s_denim_cnfg.ready),

    .m_stat_tdata   (m_denim_stat.data),
    .m_stat_tvalid  (m_denim_stat.valid),
    .m_stat_tready  (m_denim_stat.ready),

    .nclk           (nclk),
    .nresetn        (nresetn_r)
);

endmodule
