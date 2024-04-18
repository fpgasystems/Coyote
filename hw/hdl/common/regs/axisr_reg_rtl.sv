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
  * EVEN IF ADVISED OF THE POSSIBILITY OF    SUCH DAMAGE.
  */

`timescale 1ns / 1ps

import lynxTypes::*;

module axisr_reg_rtl #(
	parameter integer 		DATA_BITS = AXI_DATA_BITS	
) (
	input logic 			aclk,
	input logic 			aresetn,
	
	AXI4SR.s			s_axis,
	AXI4SR.m			m_axis
);

// Internal registers
logic s_axis_tready_C, s_axis_tready_N;

logic [DATA_BITS-1:0] m_axis_tdata_C, m_axis_tdata_N;
logic [(DATA_BITS/8)-1:0] m_axis_tkeep_C, m_axis_tkeep_N;
logic [PID_BITS-1:0] m_axis_tid_C, m_axis_tid_N;
logic m_axis_tvalid_C, m_axis_tvalid_N;
logic m_axis_tlast_C, m_axis_tlast_N;

logic [DATA_BITS-1:0] tmp_tdata_C, tmp_tdata_N;
logic [(DATA_BITS/8)-1:0] tmp_tkeep_C, tmp_tkeep_N;
logic [PID_BITS-1:0] tmp_tid_C, tmp_tid_N;
logic tmp_tvalid_C, tmp_tvalid_N;
logic tmp_tlast_C, tmp_tlast_N;

// Comb
assign s_axis_tready_N  = m_axis.tready || (!tmp_tvalid_C && (!m_axis_tvalid_C || !s_axis.tvalid));

always_comb begin
	m_axis_tvalid_N = m_axis_tvalid_C;
	m_axis_tdata_N = m_axis_tdata_C;
	m_axis_tkeep_N = m_axis_tkeep_C;
	m_axis_tid_N   = m_axis_tid_C;
	m_axis_tlast_N = m_axis_tlast_C;

	tmp_tvalid_N = tmp_tvalid_C;
	tmp_tdata_N = tmp_tdata_C;
	tmp_tkeep_N = tmp_tkeep_C;
	tmp_tid_N   = tmp_tid_C;
	tmp_tlast_N = tmp_tlast_C;

	if(s_axis_tready_C) begin
		if(m_axis.tready || !m_axis_tvalid_C) begin
			m_axis_tvalid_N = s_axis.tvalid;
			m_axis_tdata_N = s_axis.tdata;
			m_axis_tkeep_N = s_axis.tkeep;
			m_axis_tid_N   = s_axis.tid;
			m_axis_tlast_N = s_axis.tlast;
		end
		else begin
			tmp_tvalid_N = s_axis.tvalid;
			tmp_tdata_N = s_axis.tdata;
			tmp_tkeep_N = s_axis.tkeep;
			tmp_tid_N   = s_axis.tid;
			tmp_tlast_N = s_axis.tlast;
		end
	end
	else if(m_axis.tready) begin
		m_axis_tvalid_N = tmp_tvalid_C;
		m_axis_tdata_N = tmp_tdata_C;
		m_axis_tkeep_N = tmp_tkeep_C;
		m_axis_tid_N   = tmp_tid_C;
		m_axis_tlast_N = tmp_tlast_C;

		tmp_tvalid_N = 1'b0;
	end
end

// Reg process
always_ff @(posedge aclk) begin
	if(aresetn == 1'b0) begin
		m_axis_tdata_C <= 0;
		m_axis_tkeep_C <= 0;
		m_axis_tid_C <= 0;
		m_axis_tlast_C <= 0;
		m_axis_tvalid_C <= 0;
		tmp_tdata_C <= 0;
		tmp_tkeep_C <= 0;
		tmp_tid_C <= 0;
		tmp_tlast_C <= 0;
		tmp_tvalid_C <= 0;
		s_axis_tready_C <= 0;
	end 
	else begin 
		m_axis_tdata_C <= m_axis_tdata_N;
		m_axis_tkeep_C <= m_axis_tkeep_N;
		m_axis_tid_C <= m_axis_tid_N;
		m_axis_tlast_C <= m_axis_tlast_N;
		m_axis_tvalid_C <= m_axis_tvalid_N;
		tmp_tdata_C <= tmp_tdata_N;
		tmp_tkeep_C <= tmp_tkeep_N;
		tmp_tid_C <= tmp_tid_N;
		tmp_tlast_C <= tmp_tlast_N;
		tmp_tvalid_C <= tmp_tvalid_N;
		s_axis_tready_C <= s_axis_tready_N;
	end
end

// Outputs
assign s_axis.tready = s_axis_tready_C;

assign m_axis.tdata = m_axis_tdata_C;
assign m_axis.tkeep = m_axis_tkeep_C;
assign m_axis.tid   = m_axis_tid_C;
assign m_axis.tlast = m_axis_tlast_C;
assign m_axis.tvalid = m_axis_tvalid_C;

endmodule