/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025, Systems Group, ETH Zurich
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
 * @brief AXI stream last rewriter
 *
 * Rewrites the last signal of the AXI stream based on the forwarded last signal that is taken from 
 * the original request.
 */
module axis_last_rewriter (
    metaIntf.s s_fwd_last,

    AXI4S.s s_axis,
    AXI4S.m m_axis
);

assign s_fwd_last.ready = m_axis.tready && s_axis.tvalid && s_axis.tlast;

assign m_axis.tdata  = s_axis.tdata;
assign m_axis.tkeep  = s_axis.tkeep;
assign m_axis.tlast  = s_axis.tlast && s_fwd_last.data;
assign m_axis.tvalid = s_axis.tvalid && s_fwd_last.valid;

assign s_axis.tready = m_axis.tready && s_fwd_last.valid;

endmodule