`timescale 1ns / 1ps

import lynxTypes::*;

module meta_reg_rtl #(
	parameter integer 		DATA_BITS = AXI_DATA_BITS	
) (
	input logic 			aclk,
	input logic 			aresetn,
	
	metaIntf.s 				s_meta,
	metaIntf.m 				m_meta
);

// Internal registers
logic s_meta_tready_C, s_meta_tready_N;

logic [DATA_BITS-1:0] m_meta_tdata_C, m_meta_tdata_N;
logic m_meta_tvalid_C, m_meta_tvalid_N;

logic [DATA_BITS-1:0] tmp_tdata_C, tmp_tdata_N;
logic tmp_tvalid_C, tmp_tvalid_N;

// Comb
assign s_meta_tready_N  = m_meta.tready || (!tmp_tvalid_C && (!m_meta_tvalid_C || !s_meta.tvalid));

always_comb begin
	m_meta_tvalid_N = m_meta_tvalid_C;
	m_meta_tdata_N = m_meta_tdata_C;

	tmp_tvalid_N = tmp_tvalid_C;
	tmp_tdata_N = tmp_tdata_C;

	if(s_meta_tready_C) begin
		if(m_meta.tready || !m_meta_tvalid_C) begin
			m_meta_tvalid_N = s_meta.tvalid;
			m_meta_tdata_N = s_meta.tdata;
		end
		else begin
			tmp_tvalid_N = s_meta.tvalid;
			tmp_tdata_N = s_meta.tdata;		end
	end
	else if(m_meta.tready) begin
		m_meta_tvalid_N = tmp_tvalid_C;
		m_meta_tdata_N = tmp_tdata_C;

		tmp_tvalid_N = 1'b0;
	end
end

// Reg process
always_ff @(posedge aclk) begin
	if(aresetn == 1'b0) begin
		m_meta_tdata_C <= 0;
		m_meta_tvalid_C <= 0;
		tmp_tdata_C <= 0;
		tmp_tvalid_C <= 0;
		s_meta_tready_C <= 0;
	end 
	else begin 
		m_meta_tdata_C <= m_meta_tdata_N;
		m_meta_tvalid_C <= m_meta_tvalid_N;
		tmp_tdata_C <= tmp_tdata_N;
		tmp_tvalid_C <= tmp_tvalid_N;
		s_meta_tready_C <= s_meta_tready_N;
	end
end

// Outputs
assign s_meta.tready = s_meta_tready_C;

assign m_meta.tdata = m_meta_tdata_C;
assign m_meta.tvalid = m_meta_tvalid_C;

endmodule