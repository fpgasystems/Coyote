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

module axis_decoupler #(
    parameter integer               DATA_BITS = AXI_DATA_BITS,
    parameter integer               N_ID = N_REGIONS
) (
    input  logic [N_ID-1:0]    decouple,

    AXI4S.s                     s_axis [N_ID],
    AXI4S.m                    m_axis [N_ID]
);

// ----------------------------------------------------------------------------------------------------------------------- 
// Decoupling
// -----------------------------------------------------------------------------------------------------------------------
`ifdef EN_PR

logic [N_ID-1:0]                           s_axis_tvalid;
logic [N_ID-1:0]                           s_axis_tready;
logic [N_ID-1:0][DATA_BITS-1:0]            s_axis_tdata;
logic [N_ID-1:0][DATA_BITS/8-1:0]          s_axis_tkeep;
logic [N_ID-1:0]                           s_axis_tlast;

logic [N_ID-1:0]                           m_axis_tvalid;
logic [N_ID-1:0]                           m_axis_tready;
logic [N_ID-1:0][DATA_BITS-1:0]            m_axis_tdata;
logic [N_ID-1:0][DATA_BITS/8-1:0]          m_axis_tkeep;
logic [N_ID-1:0]                           m_axis_tlast;

// Assign
for(genvar i = 0; i < N_ID; i++) begin
    assign s_axis_tvalid[i] = s_axis[i].tvalid;
    assign s_axis_tdata[i] = s_axis[i].tdata;
    assign s_axis_tkeep[i] = s_axis[i].tkeep;
    assign s_axis_tlast[i] = s_axis[i].tlast;
    assign s_axis[i].tready = s_axis_tready[i];

    assign m_axis[i].tvalid = m_axis_tvalid[i];
    assign m_axis[i].tdata = m_axis_tdata[i];
    assign m_axis[i].tkeep = m_axis_tkeep[i];
    assign m_axis[i].tlast = m_axis_tlast[i];
    assign m_axis_tready[i] = m_axis[i].tready;
end

// Decoupler
for(genvar i = 0; i < N_ID; i++) begin
    assign m_axis_tvalid[i] = decouple[i] ? 1'b0 : s_axis_tvalid[i];
    assign s_axis_tready[i] = decouple[i] ? 1'b0 : m_axis_tready[i];

    assign m_axis_tdata[i] = s_axis_tdata[i];
    assign m_axis_tlast[i] = s_axis_tlast[i];
    assign m_axis_tkeep[i] = s_axis_tkeep[i];
end

`else

for(genvar i = 0; i < N_ID; i++) begin
    `AXIS_ASSIGN(s_axis[i], m_axis[i])
end

`endif

endmodule