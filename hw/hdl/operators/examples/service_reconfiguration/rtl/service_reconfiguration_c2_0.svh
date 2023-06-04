// I/O
AXI4SR axis_sink_int ();
AXI4SR axis_src_int ();

always_comb axi_ctrl.tie_off_s();

axisr_reg_rtl inst_reg_slice_sink (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_host_0_sink), .m_axis(axis_sink_int));
axisr_reg_rtl inst_reg_slice_src (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_src_int), .m_axis(axis_host_0_src));

// Rotate bytes
rotate inst_top (
    .aclk(aclk),
    .aresetn(aresetn),
    .axis_in(axis_sink_int),
    .axis_out(axis_src_int)
);