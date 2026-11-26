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

/**
 * @brief   TCP RX demultiplexer
 *
 * Routes each beat to m_axis[tid]; the shell sets tid = dest of the sq_rd (always < N_DESTS).
 */
module axis_mux_user_tcp #(
    parameter integer N_DESTS = 1
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    AXI4SR.s                                s_axis,
    AXI4SR.m                                m_axis [N_DESTS]
);

logic [N_DESTS-1:0] m_axis_tready;

for(genvar i = 0; i < N_DESTS; i++) begin
    assign m_axis[i].tvalid = s_axis.tvalid && (s_axis.tid == i);
    assign m_axis[i].tdata  = s_axis.tdata;
    assign m_axis[i].tkeep  = s_axis.tkeep;
    assign m_axis[i].tlast  = s_axis.tlast;
    assign m_axis[i].tid    = s_axis.tid;
    assign m_axis_tready[i] = m_axis[i].tready;
end

assign s_axis.tready = (s_axis.tid < N_DESTS) && m_axis_tready[s_axis.tid];

endmodule
