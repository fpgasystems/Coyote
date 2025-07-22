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