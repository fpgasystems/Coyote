/**
 * This file is part of Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025-2026, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

/////////////////////////////////////////////////////////
//          AXI LITE PARSER - MM REGISTERS            //
////////////////////////////////////////////////////////
// Client control signals
logic           start_client;
logic [15:0]    n_sessions;
logic [31:0]    pkg_word_count;
logic [31:0]    clk_freq;
logic [31:0]    duration;
logic [3:0]     client_state;

// Session-ID injection: SW writes each openConnTcp() result to reg 3,
// producing one session ID entry consumed by the client kernel.
logic           sess_id_valid;
logic [15:0]    sess_id_data;
logic           sess_id_ready;

perf_tcp_axi_ctrl_parser inst_axi_ctrl(
    .aclk(aclk),
    .aresetn(aresetn),
    .axi_ctrl(axi_ctrl),

    .start_client(start_client),
    .n_sessions(n_sessions),
    .pkg_word_count(pkg_word_count),
    .clk_freq(clk_freq),
    .duration(duration),
    .client_state(client_state),

    .sess_id_valid(sess_id_valid),
    .sess_id_data(sess_id_data),
    .sess_id_ready(sess_id_ready)
);

/////////////////////////////////////////////////////////
//                  CLIENT LOGIC                      //
////////////////////////////////////////////////////////

tcp_perf_client_hls_ip inst_perf_client(
    // SW-injected session IDs
    .s_axis_session_ids_TVALID      (sess_id_valid),
    .s_axis_session_ids_TREADY      (sess_id_ready),
    .s_axis_session_ids_TDATA       (sess_id_data),

    .m_axis_tx_meta_TVALID          (tcp_tx_meta.valid),
    .m_axis_tx_meta_TREADY          (tcp_tx_meta.ready),
    .m_axis_tx_meta_TDATA           (tcp_tx_meta.data),

    .m_axis_tx_data_TVALID          (axis_tcp_send.tvalid),
    .m_axis_tx_data_TREADY          (axis_tcp_send.tready),
    .m_axis_tx_data_TDATA           (axis_tcp_send.tdata),
    .m_axis_tx_data_TKEEP           (axis_tcp_send.tkeep),
    .m_axis_tx_data_TLAST           (axis_tcp_send.tlast),

    .s_axis_tx_status_TVALID        (tcp_tx_stat.valid),
    .s_axis_tx_status_TREADY        (tcp_tx_stat.ready),
    .s_axis_tx_status_TDATA         (tcp_tx_stat.data),

    .start_client                   (start_client),
    .n_sessions                     (n_sessions),
    .pkg_word_count                 (pkg_word_count),
    .clk_freq                       (clk_freq),
    .duration                       (duration),
    .client_state                   (client_state),

    .ap_clk                         (aclk),
    .ap_rst_n                       (aresetn)
);

/////////////////////////////////////////////////////////
//                  SERVER LOGIC                      //
////////////////////////////////////////////////////////

// Main HLS module implementing the TCP server logic
tcp_perf_server_hls_ip inst_perf_server(
    .s_axis_notif_TVALID            (tcp_notify.valid),
    .s_axis_notif_TREADY            (tcp_notify.ready),
    .s_axis_notif_TDATA             (tcp_notify.data),

    .m_axis_read_package_TVALID     (tcp_rd_pkg.valid),
    .m_axis_read_package_TREADY     (tcp_rd_pkg.ready),
    .m_axis_read_package_TDATA      (tcp_rd_pkg.data),

    .s_axis_rx_meta_TVALID          (tcp_rx_meta.valid),
    .s_axis_rx_meta_TREADY          (tcp_rx_meta.ready),
    .s_axis_rx_meta_TDATA           (tcp_rx_meta.data),

    .s_axis_rx_data_TVALID          (axis_tcp_recv.tvalid),
    .s_axis_rx_data_TREADY          (axis_tcp_recv.tready),
    .s_axis_rx_data_TDATA           (axis_tcp_recv.tdata),
    .s_axis_rx_data_TKEEP           (axis_tcp_recv.tkeep),
    .s_axis_rx_data_TLAST           (axis_tcp_recv.tlast),
    .s_axis_rx_data_TSTRB           (0),

    .ap_clk                         (aclk),
    .ap_rst_n                       (aresetn)
);

/////////////////////////////////////////////////////////
//                TIE OFF UNUSED                      //
////////////////////////////////////////////////////////
// NOTE: Currently, it is not possible to set EN_STRM = 0 (even though
// host-facing streams aren't used in this example) ---> it leads to
// synthesis errors in the MMU
// TODO: Once MMU bug is fixed, remove these tie-offs and set EN_STRM=0
always_comb axis_host_recv[0].tie_off_s();
always_comb axis_host_send[0].tie_off_m();

// Tie-off unused signals to avoid synthesis problems
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();
always_comb notify.tie_off_m();

/////////////////////////////////////////////////////////
//                  DEBUG ILA                         //
////////////////////////////////////////////////////////
ila_perf_tcp inst_ila_perf_tcp (
    .clk(aclk),
    .probe0  (sess_id_valid),
    .probe1  (sess_id_ready),
    .probe2  (sess_id_data),              // 16

    .probe3  (client_state),              // 4

    .probe4  (tcp_tx_meta.valid),
    .probe5  (tcp_tx_meta.ready),

    .probe6  (tcp_tx_stat.valid),
    .probe7  (tcp_tx_stat.ready),
    .probe8  (tcp_tx_stat.data[63:62]),   // 2
    
    .probe9  (axis_tcp_send.tvalid),
    .probe10 (axis_tcp_send.tready),
    .probe11 (axis_tcp_send.tlast),
    
    .probe12 (tcp_notify.valid),
    .probe13 (tcp_notify.ready),
    .probe14 (tcp_rd_pkg.valid),
    .probe15 (tcp_rd_pkg.ready),
    
    .probe16 (axis_tcp_recv.tvalid),
    .probe17 (axis_tcp_recv.tready),
    .probe18 (axis_tcp_recv.tlast)
);
