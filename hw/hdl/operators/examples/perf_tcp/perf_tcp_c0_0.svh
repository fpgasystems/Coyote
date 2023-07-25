// Tie-off
always_comb axis_host_0_sink.tie_off_s();
always_comb axis_host_0_src.tie_off_m();

// UL
send_recv_role #( 
  .C_S_AXI_CONTROL_DATA_WIDTH(AXIL_DATA_BITS),  
  .C_S_AXI_CONTROL_ADDR_WIDTH(AXI_ADDR_BITS)
)user_role (
    .ap_clk(aclk),
    .ap_rst_n(aresetn),

    .axi_ctrl                          (axi_ctrl),

    .s_axis_tcp_notification_tvalid    (tcp_0_notify.valid),
    .s_axis_tcp_notification_tready    (tcp_0_notify.ready),
    .s_axis_tcp_notification_tdata     (tcp_0_notify.data),
    .m_axis_tcp_read_pkg_tvalid        (tcp_0_rd_pkg.valid),
    .m_axis_tcp_read_pkg_tready        (tcp_0_rd_pkg.ready),
    .m_axis_tcp_read_pkg_tdata         (tcp_0_rd_pkg.data),
    .s_axis_tcp_rx_meta_tvalid         (tcp_0_rx_meta.valid),
    .s_axis_tcp_rx_meta_tready         (tcp_0_rx_meta.ready),
    .s_axis_tcp_rx_meta_tdata          (tcp_0_rx_meta.data),
    .s_axis_tcp_rx_data_tvalid         (axis_tcp_0_sink.tvalid),
    .s_axis_tcp_rx_data_tready         (axis_tcp_0_sink.tready),
    .s_axis_tcp_rx_data_tdata          (axis_tcp_0_sink.tdata),
    .s_axis_tcp_rx_data_tkeep          (axis_tcp_0_sink.tkeep),
    .s_axis_tcp_rx_data_tlast          (axis_tcp_0_sink.tlast),
    .m_axis_tcp_tx_meta_tvalid         (tcp_0_tx_meta.valid),
    .m_axis_tcp_tx_meta_tready         (tcp_0_tx_meta.ready),
    .m_axis_tcp_tx_meta_tdata          (tcp_0_tx_meta.data),
    .m_axis_tcp_tx_data_tvalid         (axis_tcp_0_src.tvalid),
    .m_axis_tcp_tx_data_tready         (axis_tcp_0_src.tready),
    .m_axis_tcp_tx_data_tdata          (axis_tcp_0_src.tdata),
    .m_axis_tcp_tx_data_tkeep          (axis_tcp_0_src.tkeep),
    .m_axis_tcp_tx_data_tlast          (axis_tcp_0_src.tlast),
    .s_axis_tcp_tx_status_tvalid       (tcp_0_tx_stat.valid),
    .s_axis_tcp_tx_status_tready       (tcp_0_tx_stat.ready),
    .s_axis_tcp_tx_status_tdata        (tcp_0_tx_stat.data)

);