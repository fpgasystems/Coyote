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
 * Simulation model of the Xilinx ILA ila_perf_fpga of example 7 (examples/07_perf_fpga/hw/src/init_ip.tcl)
 * for Verilator.
 *
 * Vivado generates the IP; without Vivado (sim/vl/configure.sh) Verilator takes this file when the module
 * is missing (-y in sim/vl/build.sh). An ILA only observes, so the model has the inputs and no logic.
 */

`timescale 1ns/1ps

module ila_perf_fpga (
    input  logic         clk,
    input  logic [1:0]   probe0,
    input  logic [31:0]  probe1,
    input  logic [63:0]  probe2,
    input  logic [47:0]  probe3,
    input  logic [27:0]  probe4,
    input  logic [5:0]   probe5,
    input  logic [31:0]  probe6,
    input  logic [63:0]  probe7,
    input  logic         probe8,
    input  logic         probe9,
    input  logic [63:0]  probe10,
    input  logic [31:0]  probe11,
    input  logic         probe12,
    input  logic         probe13,
    input  logic         probe14,
    input  logic         probe15,
    input  logic         probe16,
    input  logic         probe17,
    input  logic         probe18,
    input  logic         probe19,
    input  logic         probe20,
    input  logic         probe21,
    input  logic         probe22,
    input  logic         probe23,
    input  logic         probe24,
    input  logic         probe25
);
endmodule
