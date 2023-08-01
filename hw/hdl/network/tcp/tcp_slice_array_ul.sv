/**
  * Copyright (c) 2021, Systems Group, ETH Zurich
  * All rights reserved.
  *
  * Redistribution and use in source and binary forms, with or without modification,
  * are permitted provided that the following conditions are met:
  *
  * 1. Redistributions of source code must retain the above copyright notice,
  * this list of conditions and the following disclaimer.
  * 2. Redistributions in binary form must reproduce the above copyright notice,
  * this list of conditions and the following disclaimer in the documentation
  * and/or other materials provided with the distribution.
  * 3. Neither the name of the copyright holder nor the names of its contributors
  * may be used to endorse or promote products derived from this software
  * without specific prior written permission.
  *
  * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
  * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
  * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
  * IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
  * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
  * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
  * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
  * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
  * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
  */

import lynxTypes::*;

`include "axi_macros.svh"
`include "lynx_macros.svh"

/**
 * @brief   TCP slice array
 *
 * TCP slicing
 *
 */
module tcp_slice_array_ul #(
    parameter integer       N_STAGES = 2  
) (
    // Network
    // metaIntf.m              m_tcp_listen_req_n,
    // metaIntf.s              s_tcp_listen_rsp_n,
    // metaIntf.m              m_tcp_open_req_n,
    // metaIntf.s              s_tcp_open_rsp_n,
    // metaIntf.m              m_tcp_close_req_n,
    metaIntf.s              s_tcp_notify_n,
    metaIntf.m              m_tcp_rd_pkg_n,
    metaIntf.s              s_tcp_rx_meta_n,
    metaIntf.m              m_tcp_tx_meta_n,
    metaIntf.s              s_tcp_tx_stat_n,
    AXI4SR.m                m_axis_tcp_tx_n, 
    AXI4SR.s                s_axis_tcp_rx_n,
    
    // User
    // metaIntf.s              s_tcp_listen_req_u,
    // metaIntf.m              m_tcp_listen_rsp_u,
    // metaIntf.s              s_tcp_open_req_u,
    // metaIntf.m              m_tcp_open_rsp_u,
    // metaIntf.s              s_tcp_close_req_u,
    metaIntf.m              m_tcp_notify_u,
    metaIntf.s              s_tcp_rd_pkg_u,
    metaIntf.m              m_tcp_rx_meta_u,
    metaIntf.s              s_tcp_tx_meta_u,
    metaIntf.m              m_tcp_tx_stat_u,
    AXI4SR.s                s_axis_tcp_tx_u,         
    AXI4SR.m                m_axis_tcp_rx_u,

    input  wire             aclk,
    input  wire             aresetn
);

// metaIntf #(.STYPE(tcp_listen_req_t)) tcp_listen_req_s [N_STAGES+1]();
// metaIntf #(.STYPE(tcp_listen_rsp_t)) tcp_listen_rsp_s [N_STAGES+1]();
// metaIntf #(.STYPE(tcp_open_req_t)) tcp_open_req_s [N_STAGES+1]();
// metaIntf #(.STYPE(tcp_open_rsp_t)) tcp_open_rsp_s [N_STAGES+1]();
// metaIntf #(.STYPE(tcp_close_req_t)) tcp_close_req_s [N_STAGES+1]();
metaIntf #(.STYPE(tcp_notify_t)) tcp_notify_s [N_STAGES+1]();
metaIntf #(.STYPE(tcp_rd_pkg_t)) tcp_rd_pkg_s [N_STAGES+1]();
metaIntf #(.STYPE(tcp_rx_meta_t)) tcp_rx_meta_s [N_STAGES+1]();
metaIntf #(.STYPE(tcp_tx_meta_t)) tcp_tx_meta_s [N_STAGES+1]();
metaIntf #(.STYPE(tcp_tx_stat_t)) tcp_tx_stat_s [N_STAGES+1]();
AXI4SR #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_tcp_rx_s [N_STAGES+1]();
AXI4SR #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_tcp_tx_s [N_STAGES+1]();

// Slaves
// `META_ASSIGN(s_tcp_listen_rsp_n, tcp_listen_rsp_s[0])
// `META_ASSIGN(s_tcp_open_rsp_n, tcp_open_rsp_s[0])
`META_ASSIGN(s_tcp_notify_n, tcp_notify_s[0])
`META_ASSIGN(s_tcp_rx_meta_n, tcp_rx_meta_s[0])
`META_ASSIGN(s_tcp_tx_stat_n, tcp_tx_stat_s[0])
`AXISR_ASSIGN(s_axis_tcp_rx_n, axis_tcp_rx_s[0])

// `META_ASSIGN(s_tcp_listen_req_u, tcp_listen_req_s[0])
// `META_ASSIGN(s_tcp_open_req_u, tcp_open_req_s[0])
// `META_ASSIGN(s_tcp_close_req_u, tcp_close_req_s[0])
`META_ASSIGN(s_tcp_rd_pkg_u, tcp_rd_pkg_s[0])
`META_ASSIGN(s_tcp_tx_meta_u, tcp_tx_meta_s[0])
`AXISR_ASSIGN(s_axis_tcp_tx_u, axis_tcp_tx_s[0])

// Masters
// `META_ASSIGN(tcp_listen_req_s[N_STAGES], m_tcp_listen_req_n)
// `META_ASSIGN(tcp_open_req_s[N_STAGES], m_tcp_open_req_n)
// `META_ASSIGN(tcp_close_req_s[N_STAGES], m_tcp_close_req_n)
`META_ASSIGN(tcp_rd_pkg_s[N_STAGES], m_tcp_rd_pkg_n)
`META_ASSIGN(tcp_tx_meta_s[N_STAGES], m_tcp_tx_meta_n)
`AXISR_ASSIGN(axis_tcp_tx_s[N_STAGES], m_axis_tcp_tx_n)

// `META_ASSIGN(tcp_listen_rsp_s[N_STAGES], m_tcp_listen_rsp_u)
// `META_ASSIGN(tcp_open_rsp_s[N_STAGES], m_tcp_open_rsp_u)
`META_ASSIGN(tcp_notify_s[N_STAGES], m_tcp_notify_u)
`META_ASSIGN(tcp_rx_meta_s[N_STAGES], m_tcp_rx_meta_u)
`META_ASSIGN(tcp_tx_stat_s[N_STAGES], m_tcp_tx_stat_u)
`AXISR_ASSIGN(axis_tcp_rx_s[N_STAGES], m_axis_tcp_rx_u)

for(genvar i = 0; i < N_STAGES; i++) begin

    // axis_register_slice_tcp_16 inst_slice_listen_req (
    //     .aclk(aclk),
    //     .aresetn(aresetn),
    //     .s_axis_tvalid(tcp_listen_req_s[i].valid),
    //     .s_axis_tready(tcp_listen_req_s[i].ready),
    //     .s_axis_tdata (tcp_listen_req_s[i].data),  
    //     .m_axis_tvalid(tcp_listen_req_s[i+1].valid),
    //     .m_axis_tready(tcp_listen_req_s[i+1].ready),
    //     .m_axis_tdata (tcp_listen_req_s[i+1].data)
    // );

    // axis_register_slice_tcp_8 inst_slice_listen_rsp (
    //     .aclk(aclk),
    //     .aresetn(aresetn),
    //     .s_axis_tvalid(tcp_listen_rsp_s[i].valid),
    //     .s_axis_tready(tcp_listen_rsp_s[i].ready),
    //     .s_axis_tdata (tcp_listen_rsp_s[i].data),  
    //     .m_axis_tvalid(tcp_listen_rsp_s[i+1].valid),
    //     .m_axis_tready(tcp_listen_rsp_s[i+1].ready),
    //     .m_axis_tdata (tcp_listen_rsp_s[i+1].data)
    // );

    // axis_register_slice_tcp_48 inst_slice_open_req (
    //     .aclk(aclk),
    //     .aresetn(aresetn),
    //     .s_axis_tvalid(tcp_open_req_s[i].valid),
    //     .s_axis_tready(tcp_open_req_s[i].ready),
    //     .s_axis_tdata (tcp_open_req_s[i].data),  
    //     .m_axis_tvalid(tcp_open_req_s[i+1].valid),
    //     .m_axis_tready(tcp_open_req_s[i+1].ready),
    //     .m_axis_tdata (tcp_open_req_s[i+1].data)
    // );

    // axis_register_slice_tcp_72 inst_slice_open_rsp (
    //     .aclk(aclk),
    //     .aresetn(aresetn),
    //     .s_axis_tvalid(tcp_open_rsp_s[i].valid),
    //     .s_axis_tready(tcp_open_rsp_s[i].ready),
    //     .s_axis_tdata (tcp_open_rsp_s[i].data),  
    //     .m_axis_tvalid(tcp_open_rsp_s[i+1].valid),
    //     .m_axis_tready(tcp_open_rsp_s[i+1].ready),
    //     .m_axis_tdata (tcp_open_rsp_s[i+1].data)
    // );

    // axis_register_slice_tcp_16 inst_slice_close_req (
    //     .aclk(aclk),
    //     .aresetn(aresetn),
    //     .s_axis_tvalid(tcp_close_req_s[i].valid),
    //     .s_axis_tready(tcp_close_req_s[i].ready),
    //     .s_axis_tdata (tcp_close_req_s[i].data),  
    //     .m_axis_tvalid(tcp_close_req_s[i+1].valid),
    //     .m_axis_tready(tcp_close_req_s[i+1].ready),
    //     .m_axis_tdata (tcp_close_req_s[i+1].data)
    // );

    axis_register_slice_tcp_88 inst_slice_notify (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(tcp_notify_s[i].valid),
        .s_axis_tready(tcp_notify_s[i].ready),
        .s_axis_tdata (tcp_notify_s[i].data),  
        .m_axis_tvalid(tcp_notify_s[i+1].valid),
        .m_axis_tready(tcp_notify_s[i+1].ready),
        .m_axis_tdata (tcp_notify_s[i+1].data)
    );

    axis_register_slice_tcp_40 inst_slice_rd_pkg (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(tcp_rd_pkg_s[i].valid),
        .s_axis_tready(tcp_rd_pkg_s[i].ready),
        .s_axis_tdata (tcp_rd_pkg_s[i].data),  
        .m_axis_tvalid(tcp_rd_pkg_s[i+1].valid),
        .m_axis_tready(tcp_rd_pkg_s[i+1].ready),
        .m_axis_tdata (tcp_rd_pkg_s[i+1].data)
    );

    axis_register_slice_tcp_16 inst_slice_rx_meta (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(tcp_rx_meta_s[i].valid),
        .s_axis_tready(tcp_rx_meta_s[i].ready),
        .s_axis_tdata (tcp_rx_meta_s[i].data),  
        .m_axis_tvalid(tcp_rx_meta_s[i+1].valid),
        .m_axis_tready(tcp_rx_meta_s[i+1].ready),
        .m_axis_tdata (tcp_rx_meta_s[i+1].data)
    );

    axis_register_slice_tcp_40 inst_slice_tx_meta (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(tcp_tx_meta_s[i].valid),
        .s_axis_tready(tcp_tx_meta_s[i].ready),
        .s_axis_tdata (tcp_tx_meta_s[i].data),  
        .m_axis_tvalid(tcp_tx_meta_s[i+1].valid),
        .m_axis_tready(tcp_tx_meta_s[i+1].ready),
        .m_axis_tdata (tcp_tx_meta_s[i+1].data)
    );

    axis_register_slice_tcp_64 inst_slice_tx_stat (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(tcp_tx_stat_s[i].valid),
        .s_axis_tready(tcp_tx_stat_s[i].ready),
        .s_axis_tdata (tcp_tx_stat_s[i].data),  
        .m_axis_tvalid(tcp_tx_stat_s[i+1].valid),
        .m_axis_tready(tcp_tx_stat_s[i+1].ready),
        .m_axis_tdata (tcp_tx_stat_s[i+1].data)
    );

    axisr_register_slice_tcp_512 inst_slice_tx (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(axis_tcp_tx_s[i].tvalid),
        .s_axis_tready(axis_tcp_tx_s[i].tready),
        .s_axis_tdata (axis_tcp_tx_s[i].tdata),
        .s_axis_tkeep (axis_tcp_tx_s[i].tkeep),
        .s_axis_tid   (axis_tcp_tx_s[i].tid),
        .s_axis_tlast (axis_tcp_tx_s[i].tlast),
        .m_axis_tvalid(axis_tcp_tx_s[i+1].tvalid),
        .m_axis_tready(axis_tcp_tx_s[i+1].tready),
        .m_axis_tdata (axis_tcp_tx_s[i+1].tdata),
        .m_axis_tkeep (axis_tcp_tx_s[i+1].tkeep),
        .m_axis_tid   (axis_tcp_tx_s[i+1].tid),
        .m_axis_tlast (axis_tcp_tx_s[i+1].tlast)
    );

    axisr_register_slice_tcp_512 inst_slice_rx (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(axis_tcp_rx_s[i].tvalid),
        .s_axis_tready(axis_tcp_rx_s[i].tready),
        .s_axis_tdata (axis_tcp_rx_s[i].tdata),
        .s_axis_tkeep (axis_tcp_rx_s[i].tkeep),
        .s_axis_tid   (axis_tcp_rx_s[i].tid),
        .s_axis_tlast (axis_tcp_rx_s[i].tlast),
        .m_axis_tvalid(axis_tcp_rx_s[i+1].tvalid),
        .m_axis_tready(axis_tcp_rx_s[i+1].tready),
        .m_axis_tdata (axis_tcp_rx_s[i+1].tdata),
        .m_axis_tkeep (axis_tcp_rx_s[i+1].tkeep),
        .m_axis_tid   (axis_tcp_rx_s[i+1].tid),
        .m_axis_tlast (axis_tcp_rx_s[i+1].tlast)
    );

end

endmodule