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

`include "axi_macros.svh"

module axisr_decoupler #(
    parameter integer               DATA_BITS = AXI_DATA_BITS
) (
    input  logic [N_REGIONS-1:0]    decouple,

    AXI4SR.s                s_axis [N_REGIONS],
    AXI4SR.m                   m_axis [N_REGIONS]
);

// ----------------------------------------------------------------------------------------------------------------------- 
// Decoupling
// -----------------------------------------------------------------------------------------------------------------------
`ifdef EN_PR

logic [N_REGIONS-1:0]                           s_axis_tvalid;
logic [N_REGIONS-1:0]                           s_axis_tready;
logic [N_REGIONS-1:0][DATA_BITS-1:0]            s_axis_tdata;
logic [N_REGIONS-1:0][DATA_BITS/8-1:0]          s_axis_tkeep;
logic [N_REGIONS-1:0][PID_BITS-1:0]             s_axis_tid;
logic [N_REGIONS-1:0]                           s_axis_tlast;

logic [N_REGIONS-1:0]                           m_axis_tvalid;
logic [N_REGIONS-1:0]                           m_axis_tready;
logic [N_REGIONS-1:0][DATA_BITS-1:0]            m_axis_tdata;
logic [N_REGIONS-1:0][DATA_BITS/8-1:0]          m_axis_tkeep;
logic [N_REGIONS-1:0][PID_BITS-1:0]             m_axis_tid;
logic [N_REGIONS-1:0]                           m_axis_tlast;

// Assign
for(genvar i = 0; i < N_REGIONS; i++) begin
    assign s_axis_tvalid[i] = s_axis[i].tvalid;
    assign s_axis_tdata[i] = s_axis[i].tdata;
    assign s_axis_tkeep[i] = s_axis[i].tkeep;
    assign s_axis_tid[i]   = s_axis[i].tid;
    assign s_axis_tlast[i] = s_axis[i].tlast;
    assign s_axis[i].tready = s_axis_tready[i];

    assign m_axis[i].tvalid = m_axis_tvalid[i];
    assign m_axis[i].tdata = m_axis_tdata[i];
    assign m_axis[i].tkeep = m_axis_tkeep[i];
    assign m_axis[i].tid   = m_axis_tid[i];
    assign m_axis[i].tlast = m_axis_tlast[i];
    assign m_axis_tready[i] = m_axis[i].tready;
end

// Decoupler
for(genvar i = 0; i < N_REGIONS; i++) begin
    assign m_axis_tvalid[i] = decouple[i] ? 1'b0 : s_axis_tvalid[i];
    assign s_axis_tready[i] = decouple[i] ? 1'b0 : m_axis_tready[i];

    assign m_axis_tdata[i] = s_axis_tdata[i];
    assign m_axis_tlast[i] = s_axis_tlast[i];
    assign m_axis_tkeep[i] = s_axis_tkeep[i];
    assign m_axis_tid[i]   = s_axis_tid[i];
end

`else

for(genvar i = 0; i < N_REGIONS; i++) begin
    `AXIS_ASSIGN(s_axis[i], m_axis[i])
end

`endif

endmodule