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

/**
 * Simulation model of the Xilinx ILA ila_vadd of example 12 (examples/12_spinal_hdl/hw/src/init_ip.tcl)
 * for Verilator.
 *
 * Vivado generates the IP; without Vivado (sim/vl/configure.sh) Verilator takes this file when the module
 * is missing (-y in sim/vl/build.sh). An ILA only observes, so the model has the inputs and no logic.
 */

`timescale 1ns/1ps

module ila_vadd (
    input  logic         clk,
    input  logic         probe0,
    input  logic         probe1,
    input  logic         probe2,
    input  logic [511:0] probe3,
    input  logic         probe4,
    input  logic         probe5,
    input  logic         probe6,
    input  logic [511:0] probe7,
    input  logic         probe8,
    input  logic         probe9,
    input  logic         probe10,
    input  logic [511:0] probe11
);
endmodule
