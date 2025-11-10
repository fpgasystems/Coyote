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

module queue_meta #(
    parameter QDEPTH = 8
) (
    input  logic        aclk,
    input  logic        aresetn,

    metaIntf.s          s_meta,
    metaIntf.m          m_meta
);

logic val_rd;
logic rdy_rd;

fifo #(
    .DATA_BITS($bits(s_meta.data)),
    .FIFO_SIZE(QDEPTH)
) inst_fifo (
    .aclk       (aclk),
    .aresetn    (aresetn),
    .rd         (val_rd),
    .wr         (s_meta.valid),
    .ready_rd   (rdy_rd),
    .ready_wr   (s_meta.ready),
    .data_in    (s_meta.data),
    .data_out   (m_meta.data)
);

assign m_meta.valid = rdy_rd;
assign val_rd = m_meta.valid & m_meta.ready;

endmodule