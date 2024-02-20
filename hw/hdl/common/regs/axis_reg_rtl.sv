/*

Copyright (c) 2018 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`timescale 1ns / 1ps

import lynxTypes::*;

module axis_reg_rtl #(
	parameter integer 		DATA_BITS = AXI_DATA_BITS	
) (
	input logic 			aclk,
	input logic 			aresetn,
	
	AXI4S.s				s_axis,
	AXI4S.m			m_axis
);

// Internal registers
logic s_axis_tready_C, s_axis_tready_N;

logic [DATA_BITS-1:0] m_axis_tdata_C, m_axis_tdata_N;
logic [(DATA_BITS/8)-1:0] m_axis_tkeep_C, m_axis_tkeep_N;
logic m_axis_tvalid_C, m_axis_tvalid_N;
logic m_axis_tlast_C, m_axis_tlast_N;

logic [DATA_BITS-1:0] tmp_tdata_C, tmp_tdata_N;
logic [(DATA_BITS/8)-1:0] tmp_tkeep_C, tmp_tkeep_N;
logic tmp_tvalid_C, tmp_tvalid_N;
logic tmp_tlast_C, tmp_tlast_N;

// Comb
assign s_axis_tready_N  = m_axis.tready || (!tmp_tvalid_C && (!m_axis_tvalid_C || !s_axis.tvalid));

always_comb begin
	m_axis_tvalid_N = m_axis_tvalid_C;
	m_axis_tdata_N = m_axis_tdata_C;
	m_axis_tkeep_N = m_axis_tkeep_C;
	m_axis_tlast_N = m_axis_tlast_C;

	tmp_tvalid_N = tmp_tvalid_C;
	tmp_tdata_N = tmp_tdata_C;
	tmp_tkeep_N = tmp_tkeep_C;
	tmp_tlast_N = tmp_tlast_C;

	if(s_axis_tready_C) begin
		if(m_axis.tready || !m_axis_tvalid_C) begin
			m_axis_tvalid_N = s_axis.tvalid;
			m_axis_tdata_N = s_axis.tdata;
			m_axis_tkeep_N = s_axis.tkeep;
			m_axis_tlast_N = s_axis.tlast;
		end
		else begin
			tmp_tvalid_N = s_axis.tvalid;
			tmp_tdata_N = s_axis.tdata;
			tmp_tkeep_N = s_axis.tkeep;
			tmp_tlast_N = s_axis.tlast;
		end
	end
	else if(m_axis.tready) begin
		m_axis_tvalid_N = tmp_tvalid_C;
		m_axis_tdata_N = tmp_tdata_C;
		m_axis_tkeep_N = tmp_tkeep_C;
		m_axis_tlast_N = tmp_tlast_C;

		tmp_tvalid_N = 1'b0;
	end
end

// Reg process
always_ff @(posedge aclk) begin
	if(aresetn == 1'b0) begin
		m_axis_tdata_C <= 0;
		m_axis_tkeep_C <= 0;
		m_axis_tlast_C <= 0;
		m_axis_tvalid_C <= 0;
		tmp_tdata_C <= 0;
		tmp_tkeep_C <= 0;
		tmp_tlast_C <= 0;
		tmp_tvalid_C <= 0;
		s_axis_tready_C <= 0;
	end 
	else begin 
		m_axis_tdata_C <= m_axis_tdata_N;
		m_axis_tkeep_C <= m_axis_tkeep_N;
		m_axis_tlast_C <= m_axis_tlast_N;
		m_axis_tvalid_C <= m_axis_tvalid_N;
		tmp_tdata_C <= tmp_tdata_N;
		tmp_tkeep_C <= tmp_tkeep_N;
		tmp_tlast_C <= tmp_tlast_N;
		tmp_tvalid_C <= tmp_tvalid_N;
		s_axis_tready_C <= s_axis_tready_N;
	end
end

// Outputs
assign s_axis.tready = s_axis_tready_C;

assign m_axis.tdata = m_axis_tdata_C;
assign m_axis.tkeep = m_axis_tkeep_C;
assign m_axis.tlast = m_axis_tlast_C;
assign m_axis.tvalid = m_axis_tvalid_C;

endmodule