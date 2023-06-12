// I/O
AXI4SR axis_sink_int ();
AXI4L axi_ctrl_int ();

always_comb axis_host_0_src.tie_off_m();

axisr_reg_rtl inst_reg_slice_sink (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_host_0_sink), .m_axis(axis_sink_int));
axil_reg_rtl inst_reg_slice_ctrl (.aclk(aclk), .aresetn(aresetn), .s_axil(axi_ctrl), .m_axil(axi_ctrl_int));

// UL
logic clr;
logic done;
logic [3:0] test_type;
logic [31:0] test_condition;
logic [31:0] result_count;

// Slave
testcount_slv inst_slave (
    .aclk(aclk),
    .aresetn(aresetn),
    .axi_ctrl(axi_ctrl_int),
    .clr(clr),
    .done(done),
    .test_type(test_type), // 4
    .test_condition(test_condition), // 32
    .result_count(result_count) // 32
);

// Testcount
testcount inst_top (
    .clk(aclk),
    .rst_n(aresetn),
    .clr(clr),
    .done(done),
    .test_type(test_type),
    .test_condition(test_condition),
    .result_count(result_count),
    .axis_in(axis_sink_int)
);