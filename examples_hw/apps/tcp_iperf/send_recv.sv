`timescale 1ns / 1ps

`include "axi_macros.svh"
`include "lynx_macros.svh"

import lynxTypes::*;

/**
 * User logic
 * 
 */
module design_user_logic_0 (
    // AXI4L CONTROL
    // Slave control. Utilize this interface for any kind of CSR implementation.
    AXI4L.s                     axi_ctrl,

    // TCP/IP
    metaIntf.m		       tcp_listen_req,
    metaIntf.s 		       tcp_listen_rsp,
    metaIntf.m		       tcp_open_req,
    metaIntf.s 		       tcp_open_rsp,
    metaIntf.m		       tcp_close_req,
    metaIntf.s 		       tcp_notify,
    metaIntf.m		       tcp_rd_package,
    metaIntf.s 		       tcp_rx_meta,
    metaIntf.m		       tcp_tx_meta,
    metaIntf.s 		       tcp_tx_stat,

    // AXI4S TCP/IP data
    AXI4S.m                   axis_tcp_src,
    AXI4S.s                    axis_tcp_sink,

    // AXI4S host data
    // Host streams.
    AXI4S.m                   axis_host_src,
    AXI4S.s                    axis_host_sink,

    // Clock and reset
    input  wire                 aclk,
    input  wire[0:0]            aresetn
);

/* -- Tie-off unused interfaces and signals ----------------------------- */
// always_comb axi_ctrl.tie_off_s();
// always_comb tcp_listen_req.tie_off_m();
// always_comb tcp_listen_rsp.tie_off_s();
// always_comb tcp_open_req.tie_off_m();
// always_comb tcp_open_rsp.tie_off_s();
// always_comb tcp_close_req.tie_off_m();
// always_comb tcp_notify.tie_off_s();
// always_comb tcp_rd_package.tie_off_m();
// always_comb tcp_rx_meta.tie_off_s();
// always_comb tcp_tx_meta.tie_off_m();
// always_comb tcp_tx_stat.tie_off_s();
// always_comb axis_tcp_src.tie_off_m();
// always_comb axis_tcp_sink.tie_off_s();
always_comb axis_host_src.tie_off_m();
always_comb axis_host_sink.tie_off_s();

/* -- USER LOGIC -------------------------------------------------------- */


send_recv_role #( 
  .C_S_AXI_CONTROL_DATA_WIDTH(AXIL_DATA_BITS),  
  .C_S_AXI_CONTROL_ADDR_WIDTH(AXI_ADDR_BITS)
)user_role (
    .ap_clk(aclk),
    .ap_rst_n(aresetn),

    .axi_ctrl                          (axi_ctrl),

    .m_axis_tcp_listen_port_tvalid     (tcp_listen_req.valid),
    .m_axis_tcp_listen_port_tready     (tcp_listen_req.ready),
    .m_axis_tcp_listen_port_tdata      (tcp_listen_req.data),
    .s_axis_tcp_port_status_tvalid     (tcp_listen_rsp.valid),
    .s_axis_tcp_port_status_tready     (tcp_listen_rsp.ready),
    .s_axis_tcp_port_status_tdata      (tcp_listen_rsp.data),
    .m_axis_tcp_open_connection_tvalid (tcp_open_req.valid),
    .m_axis_tcp_open_connection_tready (tcp_open_req.ready),
    .m_axis_tcp_open_connection_tdata  (tcp_open_req.data),
    .s_axis_tcp_open_status_tvalid     (tcp_open_rsp.valid),
    .s_axis_tcp_open_status_tready     (tcp_open_rsp.ready),
    .s_axis_tcp_open_status_tdata      (tcp_open_rsp.data),
    .m_axis_tcp_close_connection_tvalid(tcp_close_req.valid),
    .m_axis_tcp_close_connection_tready(tcp_close_req.ready),
    .m_axis_tcp_close_connection_tdata (tcp_close_req.data),
    .s_axis_tcp_notification_tvalid    (tcp_notify.valid),
    .s_axis_tcp_notification_tready    (tcp_notify.ready),
    .s_axis_tcp_notification_tdata     (tcp_notify.data),
    .m_axis_tcp_read_pkg_tvalid        (tcp_rd_package.valid),
    .m_axis_tcp_read_pkg_tready        (tcp_rd_package.ready),
    .m_axis_tcp_read_pkg_tdata         (tcp_rd_package.data),
    .s_axis_tcp_rx_meta_tvalid         (tcp_rx_meta.valid),
    .s_axis_tcp_rx_meta_tready         (tcp_rx_meta.ready),
    .s_axis_tcp_rx_meta_tdata          (tcp_rx_meta.data),
    .s_axis_tcp_rx_data_tvalid         (axis_tcp_sink.tvalid),
    .s_axis_tcp_rx_data_tready         (axis_tcp_sink.tready),
    .s_axis_tcp_rx_data_tdata          (axis_tcp_sink.tdata),
    .s_axis_tcp_rx_data_tkeep          (axis_tcp_sink.tkeep),
    .s_axis_tcp_rx_data_tlast          (axis_tcp_sink.tlast),
    .m_axis_tcp_tx_meta_tvalid         (tcp_tx_meta.valid),
    .m_axis_tcp_tx_meta_tready         (tcp_tx_meta.ready),
    .m_axis_tcp_tx_meta_tdata          (tcp_tx_meta.data),
    .m_axis_tcp_tx_data_tvalid         (axis_tcp_src.tvalid),
    .m_axis_tcp_tx_data_tready         (axis_tcp_src.tready),
    .m_axis_tcp_tx_data_tdata          (axis_tcp_src.tdata),
    .m_axis_tcp_tx_data_tkeep          (axis_tcp_src.tkeep),
    .m_axis_tcp_tx_data_tlast          (axis_tcp_src.tlast),
    .s_axis_tcp_tx_status_tvalid       (tcp_tx_stat.valid),
    .s_axis_tcp_tx_status_tready       (tcp_tx_stat.ready),
    .s_axis_tcp_tx_status_tdata        (tcp_tx_stat.data)

);

endmodule

