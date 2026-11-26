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

import lynxTypes::*;

`include "axi_macros.svh"
`include "lynx_macros.svh"

/**
 * @brief   TCP slice array
 *
 * TCP slicing (user side, data path only). The TCP management interfaces (listen, open, close) are
 * not routed through here; they stay in the aclk domain between the MMU and the port/connection tables.
 *
 */
module tcp_slice_array_ul #(
    parameter integer       N_STAGES = 2  
) (
    // Network
    AXI4S.m                m_axis_tcp_tx_n, 
    AXI4SR.s               s_axis_tcp_rx_n,
    
    // User
    AXI4S.s                s_axis_tcp_tx_u,         
    AXI4SR.m               m_axis_tcp_rx_u,

    input  wire             aclk,
    input  wire             aresetn
);

AXI4SR #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_tcp_rx_s [N_STAGES+1] (.*);
AXI4SR #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_tcp_tx_s [N_STAGES+1] (.*);

// Slaves
`AXISR_ASSIGN(s_axis_tcp_rx_n, axis_tcp_rx_s[0])

`AXIS_ASSIGN(s_axis_tcp_tx_u, axis_tcp_tx_s[0])

// Masters
`AXIS_ASSIGN(axis_tcp_tx_s[N_STAGES], m_axis_tcp_tx_n)

`AXISR_ASSIGN(axis_tcp_rx_s[N_STAGES], m_axis_tcp_rx_u)

for(genvar i = 0; i < N_STAGES; i++) begin

    axis_register_slice_tcp_512 inst_slice_tx (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(axis_tcp_tx_s[i].tvalid),
        .s_axis_tready(axis_tcp_tx_s[i].tready),
        .s_axis_tdata (axis_tcp_tx_s[i].tdata),
        .s_axis_tkeep (axis_tcp_tx_s[i].tkeep),
        .s_axis_tlast (axis_tcp_tx_s[i].tlast),
        .m_axis_tvalid(axis_tcp_tx_s[i+1].tvalid),
        .m_axis_tready(axis_tcp_tx_s[i+1].tready),
        .m_axis_tdata (axis_tcp_tx_s[i+1].tdata),
        .m_axis_tkeep (axis_tcp_tx_s[i+1].tkeep),
        .m_axis_tlast (axis_tcp_tx_s[i+1].tlast)
    );

    axisr_register_slice_tcp_512 inst_slice_rx (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(axis_tcp_rx_s[i].tvalid),
        .s_axis_tready(axis_tcp_rx_s[i].tready),
        .s_axis_tdata (axis_tcp_rx_s[i].tdata),
        .s_axis_tkeep (axis_tcp_rx_s[i].tkeep),
        .s_axis_tid   (axis_tcp_rx_s[i].tid),
        .s_axis_tlast (axis_tcp_rx_s[i].tlast),
        .m_axis_tvalid(axis_tcp_rx_s[i+1].tvalid),
        .m_axis_tready(axis_tcp_rx_s[i+1].tready),
        .m_axis_tdata (axis_tcp_rx_s[i+1].tdata),
        .m_axis_tkeep (axis_tcp_rx_s[i+1].tkeep),
        .m_axis_tid   (axis_tcp_rx_s[i+1].tid),
        .m_axis_tlast (axis_tcp_rx_s[i+1].tlast)
    );

end

endmodule