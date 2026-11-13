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
 * Simulation model of the Xilinx AXI4-Stream Register Slice axisr_register_slice_512
 * (scripts/ip_inst/common_infrastructure.tcl: 64 data bytes, tkeep, tlast, 6-bit tid) for Verilator.
 *
 * Vivado generates the IP; without Vivado (sim/vl/configure.sh) Verilator takes this file when the module
 * is missing (-y in sim/vl/build.sh). The model is a two-entry skid buffer: registered outputs and
 * tready, full throughput, the same beats in the same order. The cycle timing is not that of the core.
 */

`timescale 1ns/1ps

module axisr_register_slice_512 (
    input  logic         aclk,
    input  logic         aresetn,

    input  logic         s_axis_tvalid,
    output logic         s_axis_tready,
    input  logic [511:0] s_axis_tdata,
    input  logic [63:0]  s_axis_tkeep,
    input  logic [5:0]   s_axis_tid,
    input  logic         s_axis_tlast,

    output logic         m_axis_tvalid,
    input  logic         m_axis_tready,
    output logic [511:0] m_axis_tdata,
    output logic [63:0]  m_axis_tkeep,
    output logic [5:0]   m_axis_tid,
    output logic         m_axis_tlast
);

typedef struct packed {
    logic [511:0] data;
    logic [63:0]  keep;
    logic [5:0]   id;
    logic         last;
} beat_t;

beat_t out_q, skid_q;
logic  skid_valid_q;

assign m_axis_tdata = out_q.data;
assign m_axis_tkeep = out_q.keep;
assign m_axis_tid   = out_q.id;
assign m_axis_tlast = out_q.last;
// Ready while the skid entry is free: a beat accepted while the output stalls waits there.
assign s_axis_tready = !skid_valid_q;

always_ff @(posedge aclk) begin
    if (!aresetn) begin
        m_axis_tvalid <= 1'b0;
        skid_valid_q  <= 1'b0;
    end else if (!m_axis_tvalid || m_axis_tready) begin
        // The output register is free in this cycle: take the skid entry first, else the input.
        if (skid_valid_q) begin
            out_q         <= skid_q;
            m_axis_tvalid <= 1'b1;
            skid_valid_q  <= 1'b0;
        end else begin
            out_q         <= '{s_axis_tdata, s_axis_tkeep, s_axis_tid, s_axis_tlast};
            m_axis_tvalid <= s_axis_tvalid;
        end
    end else if (s_axis_tvalid && s_axis_tready) begin
        skid_q       <= '{s_axis_tdata, s_axis_tkeep, s_axis_tid, s_axis_tlast};
        skid_valid_q <= 1'b1;
    end
end

endmodule
