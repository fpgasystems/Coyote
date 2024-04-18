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

module meta_reg_rtl #(
	parameter integer 		DATA_BITS = AXI_DATA_BITS	
) (
	input logic 			aclk,
	input logic 			aresetn,
	
	metaIntf.s			s_meta,
	metaIntf.m			m_meta
);

// Internal registers
logic s_meta_ready_C, s_meta_ready_N;

logic [DATA_BITS-1:0] m_meta_data_C, m_meta_data_N;
logic m_meta_valid_C, m_meta_valid_N;

logic [DATA_BITS-1:0] tmp_data_C, tmp_data_N;
logic tmp_valid_C, tmp_valid_N;

// Comb
assign s_meta_ready_N  = m_meta.ready || (!tmp_valid_C && (!m_meta_valid_C || !s_meta.valid));

always_comb begin
	m_meta_valid_N = m_meta_valid_C;
	m_meta_data_N = m_meta_data_C;

	tmp_valid_N = tmp_valid_C;
	tmp_data_N = tmp_data_C;

	if(s_meta_ready_C) begin
		if(m_meta.ready || !m_meta_valid_C) begin
			m_meta_valid_N = s_meta.valid;
			m_meta_data_N = s_meta.data;
		end
		else begin
			tmp_valid_N = s_meta.valid;
			tmp_data_N = s_meta.data;		end
	end
	else if(m_meta.ready) begin
		m_meta_valid_N = tmp_valid_C;
		m_meta_data_N = tmp_data_C;

		tmp_valid_N = 1'b0;
	end
end

// Reg process
always_ff @(posedge aclk) begin
	if(aresetn == 1'b0) begin
		m_meta_data_C <= 0;
		m_meta_valid_C <= 0;
		tmp_data_C <= 0;
		tmp_valid_C <= 0;
		s_meta_ready_C <= 0;
	end 
	else begin 
		m_meta_data_C <= m_meta_data_N;
		m_meta_valid_C <= m_meta_valid_N;
		tmp_data_C <= tmp_data_N;
		tmp_valid_C <= tmp_valid_N;
		s_meta_ready_C <= s_meta_ready_N;
	end
end

// Outputs
assign s_meta.ready = s_meta_ready_C;

assign m_meta.data = m_meta_data_C;
assign m_meta.valid = m_meta_valid_C;

endmodule