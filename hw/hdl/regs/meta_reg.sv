import lynxTypes::*;

module meta_reg #(
	parameter DATA_BITS = 256
) (
	input logic 			aclk,
	input logic 			aresetn,
	
	metaIntf.s 				meta_in,
	metaIntf.m 				meta_out
);

if(DATA_BITS == 256) begin
	axis_register_slice_meta_256_0 inst_reg_slice (
		.aclk(aclk),
		.aresetn(aresetn),
		.s_axis_tvalid(meta_in.valid),
		.s_axis_tready(meta_in.ready),
		.s_axis_tdata(meta_in.data),
		.m_axis_tvalid(meta_out.valid),
		.m_axis_tready(meta_out.ready),
		.m_axis_tdata(meta_out.data)
	);
end
else if(DATA_BITS == 56) begin
	axis_register_slice_meta_56_0 inst_reg_slice (
		.aclk(aclk),
		.aresetn(aresetn),
		.s_axis_tvalid(meta_in.valid),
		.s_axis_tready(meta_in.ready),
		.s_axis_tdata(meta_in.data),
		.m_axis_tvalid(meta_out.valid),
		.m_axis_tready(meta_out.ready),
		.m_axis_tdata(meta_out.data)
	);
end
else if(DATA_BITS == 32) begin
	axis_register_slice_meta_32_0 inst_reg_slice (
		.aclk(aclk),
		.aresetn(aresetn),
		.s_axis_tvalid(meta_in.valid),
		.s_axis_tready(meta_in.ready),
		.s_axis_tdata(meta_in.data),
		.m_axis_tvalid(meta_out.valid),
		.m_axis_tready(meta_out.ready),
		.m_axis_tdata(meta_out.data)
	);
end

endmodule