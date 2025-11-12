/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2021-2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

import lynxTypes::*;

`include "axi_macros.svh"
`include "lynx_macros.svh"

/**
 * @brief   TCP slice
 *
 * TCP slicing (auto-pipelined slices)
 *
 */
module tcp_slice (
    // Network
    metaIntf.m              m_tcp_listen_req_n,
    metaIntf.s              s_tcp_listen_rsp_n,
    metaIntf.m              m_tcp_open_req_n,
    metaIntf.s              s_tcp_open_rsp_n,
    metaIntf.m              m_tcp_close_req_n,
    metaIntf.s              s_tcp_notify_n,
    metaIntf.m              m_tcp_rd_pkg_n,
    metaIntf.s              s_tcp_rx_meta_n,
    metaIntf.m              m_tcp_tx_meta_n,
    metaIntf.s              s_tcp_tx_stat_n,
    AXI4S.m                 m_axis_tcp_tx_n, 
    AXI4S.s                 s_axis_tcp_rx_n,
    
    // Source
    metaIntf.s              s_tcp_listen_req_u,
    metaIntf.m              m_tcp_listen_rsp_u,
    metaIntf.s              s_tcp_open_req_u,
    metaIntf.m              m_tcp_open_rsp_u,
    metaIntf.s              s_tcp_close_req_u,
    metaIntf.m              m_tcp_notify_u,
    metaIntf.s              s_tcp_rd_pkg_u,
    metaIntf.m              m_tcp_rx_meta_u,
    metaIntf.s              s_tcp_tx_meta_u,
    metaIntf.m              m_tcp_tx_stat_u,
    AXI4S.s                 s_axis_tcp_tx_u,         
    AXI4S.m                 m_axis_tcp_rx_u,

    input  wire             aclk,
    input  wire             aresetn
);

    axis_register_slice_tcp_16 inst_reg_tcp_listen_req (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_tcp_listen_req_u.valid),
        .s_axis_tready(s_tcp_listen_req_u.ready),
        .s_axis_tdata (s_tcp_listen_req_u.data),  
        .m_axis_tvalid(m_tcp_listen_req_n.valid),
        .m_axis_tready(m_tcp_listen_req_n.ready),
        .m_axis_tdata (m_tcp_listen_req_n.data)
    );

    axis_register_slice_tcp_8 inst_reg_tcp_listen_rsp (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_tcp_listen_rsp_n.valid),
        .s_axis_tready(s_tcp_listen_rsp_n.ready),
        .s_axis_tdata (s_tcp_listen_rsp_n.data),  
        .m_axis_tvalid(m_tcp_listen_rsp_u.valid),
        .m_axis_tready(m_tcp_listen_rsp_u.ready),
        .m_axis_tdata (m_tcp_listen_rsp_u.data)
    );

    axis_register_slice_tcp_48 inst_reg_tcp_open_req (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_tcp_open_req_u.valid),
        .s_axis_tready(s_tcp_open_req_u.ready),
        .s_axis_tdata (s_tcp_open_req_u.data),  
        .m_axis_tvalid(m_tcp_open_req_n.valid),
        .m_axis_tready(m_tcp_open_req_n.ready),
        .m_axis_tdata (m_tcp_open_req_n.data)
    );

    axis_register_slice_tcp_72 inst_reg_tcp_open_rsp (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_tcp_open_rsp_n.valid),
        .s_axis_tready(s_tcp_open_rsp_n.ready),
        .s_axis_tdata (s_tcp_open_rsp_n.data),  
        .m_axis_tvalid(m_tcp_open_rsp_u.valid),
        .m_axis_tready(m_tcp_open_rsp_u.ready),
        .m_axis_tdata (m_tcp_open_rsp_u.data)
    );

    axis_register_slice_tcp_16 inst_reg_tcp_close_req (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_tcp_close_req_u.valid),
        .s_axis_tready(s_tcp_close_req_u.ready),
        .s_axis_tdata (s_tcp_close_req_u.data),  
        .m_axis_tvalid(m_tcp_close_req_n.valid),
        .m_axis_tready(m_tcp_close_req_n.ready),
        .m_axis_tdata (m_tcp_close_req_n.data)
    );

    axis_register_slice_tcp_88 inst_reg_tcp_notify (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_tcp_notify_n.valid),
        .s_axis_tready(s_tcp_notify_n.ready),
        .s_axis_tdata (s_tcp_notify_n.data),  
        .m_axis_tvalid(m_tcp_notify_u.valid),
        .m_axis_tready(m_tcp_notify_u.ready),
        .m_axis_tdata (m_tcp_notify_u.data)
    );

    axis_register_slice_tcp_40 inst_reg_tcp_rd_pkg (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_tcp_rd_pkg_u.valid),
        .s_axis_tready(s_tcp_rd_pkg_u.ready),
        .s_axis_tdata (s_tcp_rd_pkg_u.data),  
        .m_axis_tvalid(m_tcp_rd_pkg_n.valid),
        .m_axis_tready(m_tcp_rd_pkg_n.ready),
        .m_axis_tdata (m_tcp_rd_pkg_n.data)
    );

    axis_register_slice_tcp_40 inst_reg_tcp_rx_meta (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_tcp_rx_meta_n.valid),
        .s_axis_tready(s_tcp_rx_meta_n.ready),
        .s_axis_tdata (s_tcp_rx_meta_n.data),  
        .m_axis_tvalid(m_tcp_rx_meta_u.valid),
        .m_axis_tready(m_tcp_rx_meta_u.ready),
        .m_axis_tdata (m_tcp_rx_meta_u.data)
    );

    axis_register_slice_tcp_40 inst_reg_tcp_tx_meta (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_tcp_tx_meta_u.valid),
        .s_axis_tready(s_tcp_tx_meta_u.ready),
        .s_axis_tdata (s_tcp_tx_meta_u.data),  
        .m_axis_tvalid(m_tcp_tx_meta_n.valid),
        .m_axis_tready(m_tcp_tx_meta_n.ready),
        .m_axis_tdata (m_tcp_tx_meta_n.data)
    );

    axis_register_slice_tcp_64 inst_reg_tcp_tx_stat (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_tcp_tx_stat_n.valid),
        .s_axis_tready(s_tcp_tx_stat_n.ready),
        .s_axis_tdata (s_tcp_tx_stat_n.data),  
        .m_axis_tvalid(m_tcp_tx_stat_u.valid),
        .m_axis_tready(m_tcp_tx_stat_u.ready),
        .m_axis_tdata (m_tcp_tx_stat_u.data)
    );

    axis_register_slice_tcp_512 inst_tcp_tx_data (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_axis_tcp_tx_u.tvalid),
        .s_axis_tready(s_axis_tcp_tx_u.tready),
        .s_axis_tdata (s_axis_tcp_tx_u.tdata),
        .s_axis_tkeep (s_axis_tcp_tx_u.tkeep),
        .s_axis_tlast (s_axis_tcp_tx_u.tlast),
        .m_axis_tvalid(m_axis_tcp_tx_n.tvalid),
        .m_axis_tready(m_axis_tcp_tx_n.tready),
        .m_axis_tdata (m_axis_tcp_tx_n.tdata),
        .m_axis_tkeep (m_axis_tcp_tx_n.tkeep),
        .m_axis_tlast (m_axis_tcp_tx_n.tlast)
    );

    axis_register_slice_tcp_512 inst_tcp_rx_data (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_axis_tcp_rx_n.tvalid),
        .s_axis_tready(s_axis_tcp_rx_n.tready),
        .s_axis_tdata (s_axis_tcp_rx_n.tdata),
        .s_axis_tkeep (s_axis_tcp_rx_n.tkeep),
        .s_axis_tlast (s_axis_tcp_rx_n.tlast),
        .m_axis_tvalid(m_axis_tcp_rx_u.tvalid),
        .m_axis_tready(m_axis_tcp_rx_u.tready),
        .m_axis_tdata (m_axis_tcp_rx_u.tdata),
        .m_axis_tkeep (m_axis_tcp_rx_u.tkeep),
        .m_axis_tlast (m_axis_tcp_rx_u.tlast)
    );

endmodule