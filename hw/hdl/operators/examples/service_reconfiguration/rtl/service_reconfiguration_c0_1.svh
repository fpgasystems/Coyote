// I/O
AXI4SR axis_sink_int ();
AXI4SR axis_src_int ();
AXI4L axi_ctrl_int ();

axisr_reg_rtl inst_reg_slice_sink (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_host_0_sink), .m_axis(axis_sink_int));
axisr_reg_rtl inst_reg_slice_src (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_src_int), .m_axis(axis_host_0_src));
axil_reg_rtl inst_reg_slice_ctrl (.aclk(aclk), .aresetn(aresetn), .s_axil(axi_ctrl), .m_axil(axi_ctrl_int));

// UL
logic [15:0] mul_factor;
logic [15:0] add_factor;

// Slave
addmul_slv inst_slave (
    .aclk(aclk),
    .aresetn(aresetn),
    .axi_ctrl(axi_ctrl_int),
    .mul_factor(mul_factor), // 16
    .add_factor(add_factor) // 16
);

// Addmul
addmul #(
    .ADDMUL_DATA_BITS(AXI_DATA_BITS)
) inst_top (
    .aclk(aclk),
    .aresetn(aresetn),
    .mul_factor(mul_factor),
    .add_factor(add_factor),
    .axis_in(axis_sink_int),
    .axis_out(axis_src_int)
);