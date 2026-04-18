/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025, Systems Group, ETH Zurich
 * All rights reserved.
 */

cnn_medium_infer_hls_ip inst_cnn_medium_infer(
    .s_axi_in_TDATA         (axis_host_recv[0].tdata),
    .s_axi_in_TKEEP         (axis_host_recv[0].tkeep),
    .s_axi_in_TLAST         (axis_host_recv[0].tlast),
    .s_axi_in_TSTRB         (0),
    .s_axi_in_TVALID        (axis_host_recv[0].tvalid),
    .s_axi_in_TREADY        (axis_host_recv[0].tready),

    .m_axi_out_TDATA        (axis_host_send[0].tdata),
    .m_axi_out_TKEEP        (axis_host_send[0].tkeep),
    .m_axi_out_TLAST        (axis_host_send[0].tlast),
    .m_axi_out_TSTRB        (),
    .m_axi_out_TVALID       (axis_host_send[0].tvalid),
    .m_axi_out_TREADY       (axis_host_send[0].tready),

    .ap_clk                 (aclk),
    .ap_rst_n               (aresetn)
);

always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();
always_comb notify.tie_off_m();
always_comb axi_ctrl.tie_off_s();
