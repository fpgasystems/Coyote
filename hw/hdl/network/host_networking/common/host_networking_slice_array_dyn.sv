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
 
import lynxTypes::*;

`include "axi_macros.svh"
`include "lynx_macros.svh"

/**
 * @brief   RDMA slice array
 *
 * RDMA slicing
 *
 */
module host_networking_slice_array_dyn #(
    parameter integer       N_STAGES = 2  
) (
    // Network interfaces 
    AXI4S.m m_axis_host_tx_n, 
    AXI4S.s s_axis_host_rx_n, 
    AXI4S.s s_axis_host_tx_u, 
    AXI4S.m m_axis_host_rx_u,

    // Clock and Reset 
    input wire             aclk,
    input wire             aresetn
); 

    // Definition of all intermediate signals for the pipeline stages 
    AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_host_tx_s [N_STAGES+1]();
    AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_host_rx_s [N_STAGES+1]();

    // Slaves
    `AXIS_ASSIGN(s_axis_host_tx_u, axis_host_tx_s[0])
    `AXIS_ASSIGN(s_axis_host_rx_n, axis_host_rx_s[0])

    // Masters
    `AXIS_ASSIGN(axis_host_tx_s[N_STAGES], m_axis_host_tx_n)
    `AXIS_ASSIGN(axis_host_rx_s[N_STAGES], m_axis_host_rx_u)

    // Pipelining
    for(genvar i = 0; i < N_STAGES; i++) begin 
        // RX-path 
        axis_register_slice_host_networking_data_512 inst_host_networking_rx_nc (
            .aclk(aclk),
            .aresetn(aresetn),
            .s_axis_tvalid(axis_host_rx_s[i].tvalid),
            .s_axis_tready(axis_host_rx_s[i].tready),
            .s_axis_tdata (axis_host_rx_s[i].tdata),
            .s_axis_tkeep (axis_host_rx_s[i].tkeep),
            .s_axis_tlast (axis_host_rx_s[i].tlast),
            .m_axis_tvalid(axis_host_rx_s[i+1].tvalid),
            .m_axis_tready(axis_host_rx_s[i+1].tready),
            .m_axis_tdata (axis_host_rx_s[i+1].tdata),
            .m_axis_tkeep (axis_host_rx_s[i+1].tkeep),
            .m_axis_tlast (axis_host_rx_s[i+1].tlast)
        );

        // TX-path 
        axis_register_slice_host_networking_data_512 inst_host_networking_tx_nc (
            .aclk(aclk),
            .aresetn(aresetn),
            .s_axis_tvalid(axis_host_tx_s[i].tvalid),
            .s_axis_tready(axis_host_tx_s[i].tready),
            .s_axis_tdata (axis_host_tx_s[i].tdata),
            .s_axis_tkeep (axis_host_tx_s[i].tkeep),
            .s_axis_tlast (axis_host_tx_s[i].tlast),
            .m_axis_tvalid(axis_host_tx_s[i+1].tvalid),
            .m_axis_tready(axis_host_tx_s[i+1].tready),
            .m_axis_tdata (axis_host_tx_s[i+1].tdata),
            .m_axis_tkeep (axis_host_tx_s[i+1].tkeep),
            .m_axis_tlast (axis_host_tx_s[i+1].tlast)
        );
    end 
endmodule 