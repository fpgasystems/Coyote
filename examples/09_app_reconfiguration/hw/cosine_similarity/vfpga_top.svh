// HLS kernel for cosine similarity calculation
// Note, the suffix _hls_ip to identify HLS kernels, as explained in Example 2
`ifdef EN_STRM
cosine_similarity_hls_ip inst_similarity_calc(
    .s_axi_in1_TDATA        (axis_host_recv[0].tdata),
    .s_axi_in1_TKEEP        (axis_host_recv[0].tkeep),
    .s_axi_in1_TLAST        (axis_host_recv[0].tlast),
    .s_axi_in1_TSTRB        (0),
    .s_axi_in1_TVALID       (axis_host_recv[0].tvalid),
    .s_axi_in1_TREADY       (axis_host_recv[0].tready),

    .s_axi_in2_TDATA        (axis_host_recv[1].tdata),
    .s_axi_in2_TKEEP        (axis_host_recv[1].tkeep),
    .s_axi_in2_TLAST        (axis_host_recv[1].tlast),
    .s_axi_in2_TSTRB        (0),
    .s_axi_in2_TVALID       (axis_host_recv[1].tvalid),
    .s_axi_in2_TREADY       (axis_host_recv[1].tready),

    .m_axi_out_TDATA        (axis_host_send[0].tdata),
    .m_axi_out_TKEEP        (axis_host_send[0].tkeep),
    .m_axi_out_TLAST        (axis_host_send[0].tlast),
    .m_axi_out_TSTRB        (),
    .m_axi_out_TVALID       (axis_host_send[0].tvalid),
    .m_axi_out_TREADY       (axis_host_send[0].tready),

    .ap_clk                 (aclk),
    .ap_rst_n               (aresetn)
);

// There are two host streams, for both incoming and outgoing signals
// The second outgoing is unused in this example, so tie it off
always_comb axis_host_send[1].tie_off_m();
`endif

// Tie-off unused signals to avoid synthesis problems
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();
always_comb notify.tie_off_m();
always_comb axi_ctrl.tie_off_s();

// Debug ILA
`ifdef EN_STRM
ila_similarity inst_ila_similarity (
    .clk(aclk),                             // clock   
 
    .probe0(axis_host_recv[0].tvalid),      // 1
    .probe1(axis_host_recv[0].tready),      // 1
    .probe2(axis_host_recv[0].tlast),       // 1
    .probe3(axis_host_recv[0].tdata),       // 512

    .probe4(axis_host_recv[1].tvalid),      // 1
    .probe5(axis_host_recv[1].tready),      // 1
    .probe6(axis_host_recv[1].tlast),       // 1
    .probe7(axis_host_send[1].tdata),       // 512

    .probe8(axis_host_send[0].tvalid),      // 1
    .probe9(axis_host_send[0].tready),      // 1
    .probe10(axis_host_send[0].tlast),      // 1
    .probe11(axis_host_send[0].tdata)       // 512
);
`endif