/**
  * Copyright (c) 2021, Systems Group, ETH Zurich
  * All rights reserved.
  *
  * Redistribution and use in source and binary forms, with or without modification,
  * are permitted provided that the following conditions are met:
  *
  * 1. Redistributions of source code must retain the above copyright notice,
  * this list of conditions and the following disclaimer.
  * 2. Redistributions in binary form must reproduce the above copyright notice,
  * this list of conditions and the following disclaimer in the documentation
  * and/or other materials provided with the distribution.
  * 3. Neither the name of the copyright holder nor the names of its contributors
  * may be used to endorse or promote products derived from this software
  * without specific prior written permission.
  *
  * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
  * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
  * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
  * IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
  * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
  * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
  * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
  * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
  * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
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