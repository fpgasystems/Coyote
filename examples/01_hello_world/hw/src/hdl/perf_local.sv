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

`include "axi_macros.svh"

/**
 * perf_local example
 * @brief Reads the incoming stream and adds 1 to every integer
 * 
 * @param[in] axis_in Incoming AXI stream
 * @param[out] axis_out Outgoing AXI stream
 * @param[in] aclk Clock signal
 * @param[in] aresetn Active low reset signal
 */
module perf_local (
    AXI4SR.s        axis_in,
    AXI4SR.m        axis_out,

    input  logic    aclk,
    input  logic    aresetn
);

// Simple pipeline stages, buffering the input/output signals (not really needed, but nice to have for easier timing closure)
AXI4SR axis_in_int();
axisr_reg inst_reg_sink (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_in), .m_axis(axis_in_int));

AXI4SR axis_out_int();
axisr_reg inst_reg_src  (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_out_int), .m_axis(axis_out));

// User logic; adding 1 to the input stream and writing it to the output stream
// The other signals (valid, ready etc.) are simply propagated
always_comb begin
    for(int i = 0; i < 16; i++) begin
        axis_out_int.tdata[i*32+:32] = axis_in_int.tdata[i*32+:32] + 1; 
    end
    
    axis_out_int.tvalid  = axis_in_int.tvalid;
    axis_in_int.tready   = axis_out_int.tready;
    axis_out_int.tkeep   = axis_in_int.tkeep;
    axis_out_int.tid     = axis_in_int.tid;
    axis_out_int.tlast   = axis_in_int.tlast;
end

endmodule
