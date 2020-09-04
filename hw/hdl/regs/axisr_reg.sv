import lynxTypes::*;

module axisr_reg #(
	parameter integer DATA_BITS		= AXI_DATA_BITS
) (
	input logic 			aclk,
	input logic 			aresetn,
	
	AXI4SR.s 				axis_in,
	AXI4SR.m 				axis_out
);

if(DATA_BITS == 512) begin
	axisr_register_slice_512_0 inst_reg_slice (
		.aclk(aclk),
		.aresetn(aresetn),
		.s_axis_tvalid(axis_in.tvalid),
		.s_axis_tready(axis_in.tready),
		.s_axis_tdata(axis_in.tdata),
		.s_axis_tkeep(axis_in.tkeep),
		.s_axis_tlast(axis_in.tlast),
		.s_axis_tdest(axis_in.tdest),
		.m_axis_tvalid(axis_out.tvalid),
		.m_axis_tready(axis_out.tready),
		.m_axis_tdata(axis_out.tdata),
		.m_axis_tkeep(axis_out.tkeep),
		.m_axis_tlast(axis_out.tlast),
		.m_axis_tdest(axis_out.tdest)
	);
end
else if(DATA_BITS == 1024) begin
	axisr_register_slice_1k_0 inst_reg_slice (
		.aclk(aclk),
		.aresetn(aresetn),
		.s_axis_tvalid(axis_in.tvalid),
		.s_axis_tready(axis_in.tready),
		.s_axis_tdata(axis_in.tdata),
		.s_axis_tkeep(axis_in.tkeep),
		.s_axis_tlast(axis_in.tlast),
		.s_axis_tdest(axis_in.tdest),
		.m_axis_tvalid(axis_out.tvalid),
		.m_axis_tready(axis_out.tready),
		.m_axis_tdata(axis_out.tdata),
		.m_axis_tkeep(axis_out.tkeep),
		.m_axis_tlast(axis_out.tlast),
		.m_axis_tdest(axis_out.tdest)
	);
end
else if(DATA_BITS == 2048) begin
	axisr_register_slice_2k_0 inst_reg_slice (
		.aclk(aclk),
		.aresetn(aresetn),
		.s_axis_tvalid(axis_in.tvalid),
		.s_axis_tready(axis_in.tready),
		.s_axis_tdata(axis_in.tdata),
		.s_axis_tkeep(axis_in.tkeep),
		.s_axis_tlast(axis_in.tlast),
		.s_axis_tdest(axis_in.tdest),
		.m_axis_tvalid(axis_out.tvalid),
		.m_axis_tready(axis_out.tready),
		.m_axis_tdata(axis_out.tdata),
		.m_axis_tkeep(axis_out.tkeep),
		.m_axis_tlast(axis_out.tlast),
		.m_axis_tdest(axis_out.tdest)
	);
end

endmodule