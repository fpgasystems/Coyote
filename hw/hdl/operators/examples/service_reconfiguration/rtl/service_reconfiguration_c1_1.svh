// I/O
AXI4SR axis_sink_int ();
AXI4L axi_ctrl_int ();

always_comb axis_host_0_src.tie_off_m();

axisr_reg_rtl inst_reg_slice_sink (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_host_0_sink), .m_axis(axis_sink_int));
axil_reg_rtl inst_reg_slice_ctrl (.aclk(aclk), .aresetn(aresetn), .s_axil(axi_ctrl), .m_axil(axi_ctrl_int));

// UL
logic clr;
logic done;
logic [31:0] minimum;
logic [31:0] maximum;

// Slave
minmax_slv inst_slave (
    .aclk(aclk),
    .aresetn(aresetn),
    .axi_ctrl(axi_ctrl_int),
    .clr(clr),
    .done(done),
    .minimum(minimum), // 32
    .maximum(maximum) // 32
);

// Minmaxsum
minmax inst_top (
    .aclk(aclk),
    .aresetn(aresetn),
    .clr(clr),
    .done(done),
    .min(minimum),
    .max(maximum),
    .axis_in(axis_sink_int)
);