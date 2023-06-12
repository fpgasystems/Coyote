AXI4SR axis_sink_int ();
AXI4SR axis_src_int ();

`ifdef EN_STRM
axisr_reg inst_reg_sink (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_host_0_sink), .m_axis(axis_sink_int));
axisr_reg inst_reg_src (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_src_int), .m_axis(axis_host_0_src));
`else
axisr_reg inst_reg_sink (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_card_0_sink), .m_axis(axis_sink_int));
axisr_reg inst_reg_src (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_src_int), .m_axis(axis_card_0_src));
`endif

localparam integer N_AES_PIPELINES = 4;

logic [127:0] key;
logic key_start;
logic key_done;

// Slave
aes_slave inst_slave (
    .aclk(aclk),
    .aresetn(aresetn),
    .axi_ctrl(axi_ctrl),
    .key_out(key),
    .keyStart(key_start)
);

// AES pipelines
aes_top #(
    .NPAR(N_AES_PIPELINES)
) inst_aes_top (
    .clk(aclk),
    .reset_n(aresetn),
    .stall(~axis_src_int.tready),
    .key_in(key),
    .keyVal_in(key_start),
    .keyVal_out(key_done),
    .last_in(axis_sink_int.tlast),
    .last_out(axis_src_int.tlast),
    .keep_in(axis_sink_int.tkeep),
    .keep_out(axis_src_int.tkeep),
    .dVal_in(axis_sink_int.tvalid),
    .dVal_out(axis_src_int.tvalid),
    .data_in(axis_sink_int.tdata),
    .data_out(axis_src_int.tdata)
);

assign axis_sink_int.tready = axis_src_int.tready;
assign axis_src_int.tid = 0;