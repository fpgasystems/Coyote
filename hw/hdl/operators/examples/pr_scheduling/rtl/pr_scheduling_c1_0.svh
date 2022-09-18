// I/O
AXI4SR axis_sink_int ();
AXI4L axi_ctrl_int ();

always_comb axis_host_src.tie_off_m();

axisr_reg_rtl inst_reg_slice_sink (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_host_sink), .m_axis(axis_sink_int));
axil_reg_rtl inst_reg_slice_ctrl (.aclk(aclk), .aresetn(aresetn), .s_axil(axi_ctrl), .m_axil(axi_ctrl_int));

// UL
logic clr;
logic done;
logic [31:0] minimum;
logic [31:0] maximum;
logic [31:0] summation;

// Slave
minmaxsum_slave inst_slave (
    .aclk(aclk),
    .aresetn(aresetn),
    .axi_ctrl(axi_ctrl_int),
    .clr(clr),
    .done(done),
    .minimum(minimum), // 32
    .maximum(maximum), // 32
    .summation(summation) // 32
);

// Minmaxsum
minmaxsum inst_top (
    .clk(aclk),
    .rst_n(aresetn),
    .clr(clr),
    .done(done),
    .min_out(minimum),
    .max_out(maximum),
    .sum_out(summation),
    .axis_in_tvalid(axis_sink_int.tvalid),
    .axis_in_tdata(axis_sink_int.tdata),
    .axis_in_tlast(axis_sink_int.tlast)
);

assign axis_sink_int.tready = 1'b1;