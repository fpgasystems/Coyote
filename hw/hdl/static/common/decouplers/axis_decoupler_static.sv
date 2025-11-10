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

module axis_decoupler_static #(
    parameter integer               DATA_BITS = AXI_DATA_BITS,
    parameter integer               EN_DCPL = 1
) (
    input  logic                    decouple,

    AXI4S.s                     s_axis,
    AXI4S.m                    m_axis 
);

// ----------------------------------------------------------------------------------------------------------------------- 
// Decoupling 
// -----------------------------------------------------------------------------------------------------------------------
if(EN_DCPL == 1) begin

logic                           s_axis_tvalid;
logic                           s_axis_tready;
logic [DATA_BITS-1:0]           s_axis_tdata;
logic [DATA_BITS/8-1:0]         s_axis_tkeep;
logic                           s_axis_tlast;

logic                           m_axis_tvalid;
logic                           m_axis_tready;
logic [DATA_BITS-1:0]           m_axis_tdata;
logic [DATA_BITS/8-1:0]         m_axis_tkeep;
logic                           m_axis_tlast;

// Assign
assign s_axis_tvalid = s_axis.tvalid;
assign s_axis_tdata = s_axis.tdata;
assign s_axis_tkeep = s_axis.tkeep;
assign s_axis_tlast = s_axis.tlast;
assign s_axis.tready = s_axis_tready;

assign m_axis.tvalid = m_axis_tvalid;
assign m_axis.tdata = m_axis_tdata;
assign m_axis.tkeep = m_axis_tkeep;
assign m_axis.tlast = m_axis_tlast;
assign m_axis_tready = m_axis.tready;

// Decoupler
assign m_axis_tvalid = decouple ? 1'b0 : s_axis_tvalid;
assign s_axis_tready = decouple ? 1'b0 : m_axis_tready;

assign m_axis_tdata = s_axis_tdata;
assign m_axis_tlast = s_axis_tlast;
assign m_axis_tkeep = s_axis_tkeep;

end
else begin

`AXIS_ASSIGN(s_axis, m_axis)

end

endmodule