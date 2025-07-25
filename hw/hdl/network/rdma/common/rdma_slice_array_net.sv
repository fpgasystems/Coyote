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
 * @brief   RDMA slice array
 *
 * RDMA slicing
 *
 */
module rdma_slice_array_net #(
    parameter integer       N_STAGES = 2  
) (
    // Network
    metaIntf.m              m_rdma_qp_interface_n,
    metaIntf.m              m_rdma_conn_interface_n,
    metaIntf.m              m_rdma_sq_n,
    metaIntf.s              s_rdma_ack_n,
    metaIntf.s              s_rdma_rd_req_n,
    metaIntf.s              s_rdma_wr_req_n,
    AXI4S.m                 m_axis_rdma_rd_req_n,
    AXI4S.m                 m_axis_rdma_rd_rsp_n,
    AXI4S.s                 s_axis_rdma_wr_n,
    
    // User
    metaIntf.s              s_rdma_qp_interface_u,
    metaIntf.s              s_rdma_conn_interface_u,
    metaIntf.s              s_rdma_sq_u,
    metaIntf.m              m_rdma_ack_u,
    metaIntf.m              m_rdma_rd_req_u,
    metaIntf.m              m_rdma_wr_req_u,
    AXI4S.s                 s_axis_rdma_rd_req_u,
    AXI4S.s                 s_axis_rdma_rd_rsp_u,
    AXI4S.m                 m_axis_rdma_wr_u,

    input  wire             aclk,
    input  wire             aresetn
);

metaIntf #(.STYPE(rdma_qp_ctx_t)) rdma_qp_interface_s [N_STAGES+1]();
metaIntf #(.STYPE(rdma_qp_conn_t)) rdma_conn_interface_s [N_STAGES+1]();
metaIntf #(.STYPE(dreq_t)) rdma_sq_s [N_STAGES+1]();
metaIntf #(.STYPE(ack_t)) rdma_ack_s [N_STAGES+1]();
metaIntf #(.STYPE(req_t)) rdma_rd_req_s [N_STAGES+1]();
metaIntf #(.STYPE(req_t)) rdma_wr_req_s [N_STAGES+1]();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_rdma_rd_req_s [N_STAGES+1]();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_rdma_rd_rsp_s [N_STAGES+1]();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_rdma_wr_s [N_STAGES+1]();

// Slaves
`META_ASSIGN(s_rdma_ack_n, rdma_ack_s[0])
`META_ASSIGN(s_rdma_rd_req_n, rdma_rd_req_s[0])
`META_ASSIGN(s_rdma_wr_req_n, rdma_wr_req_s[0])
`AXIS_ASSIGN(s_axis_rdma_wr_n, axis_rdma_wr_s[0])

`META_ASSIGN(s_rdma_qp_interface_u, rdma_qp_interface_s[0])
`META_ASSIGN(s_rdma_conn_interface_u, rdma_conn_interface_s[0])
`META_ASSIGN(s_rdma_sq_u, rdma_sq_s[0])
`AXIS_ASSIGN(s_axis_rdma_rd_req_u, axis_rdma_rd_req_s[0])
`AXIS_ASSIGN(s_axis_rdma_rd_rsp_u, axis_rdma_rd_rsp_s[0])

// Masters
`META_ASSIGN(rdma_qp_interface_s[N_STAGES], m_rdma_qp_interface_n)
`META_ASSIGN(rdma_conn_interface_s[N_STAGES], m_rdma_conn_interface_n)
`META_ASSIGN(rdma_sq_s[N_STAGES], m_rdma_sq_n)
`AXIS_ASSIGN(axis_rdma_rd_req_s[N_STAGES], m_axis_rdma_rd_req_n)
`AXIS_ASSIGN(axis_rdma_rd_rsp_s[N_STAGES], m_axis_rdma_rd_rsp_n)

`META_ASSIGN(rdma_ack_s[N_STAGES], m_rdma_ack_u)
`META_ASSIGN(rdma_rd_req_s[N_STAGES], m_rdma_rd_req_u)
`META_ASSIGN(rdma_wr_req_s[N_STAGES], m_rdma_wr_req_u)
`AXIS_ASSIGN(axis_rdma_wr_s[N_STAGES], m_axis_rdma_wr_u)

for(genvar i = 0; i < N_STAGES; i++) begin

    // RDMA qp interface
    axis_register_slice_rdma_184 inst_rdma_qp_interface (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(rdma_qp_interface_s[i].valid),
        .s_axis_tready(rdma_qp_interface_s[i].ready),
        .s_axis_tdata (rdma_qp_interface_s[i].data),
        .m_axis_tvalid(rdma_qp_interface_s[i+1].valid),
        .m_axis_tready(rdma_qp_interface_s[i+1].ready),
        .m_axis_tdata (rdma_qp_interface_s[i+1].data)
    );

    // RDMA conn interface
    axis_register_slice_rdma_184 inst_rdma_conn_interface (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(rdma_conn_interface_s[i].valid),
        .s_axis_tready(rdma_conn_interface_s[i].ready),
        .s_axis_tdata (rdma_conn_interface_s[i].data),
        .m_axis_tvalid(rdma_conn_interface_s[i+1].valid),
        .m_axis_tready(rdma_conn_interface_s[i+1].ready),
        .m_axis_tdata (rdma_conn_interface_s[i+1].data)
    );

    // RDMA send queue
    axis_register_slice_rdma_256 inst_rdma_sq_nc (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(rdma_sq_s[i].valid),
        .s_axis_tready(rdma_sq_s[i].ready),
        .s_axis_tdata (rdma_sq_s[i].data),
        .m_axis_tvalid(rdma_sq_s[i+1].valid),
        .m_axis_tready(rdma_sq_s[i+1].ready),
        .m_axis_tdata (rdma_sq_s[i+1].data)
    );

    // RDMA acks
    axis_register_slice_rdma_32 inst_rdma_acks_nc (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(rdma_ack_s[i].valid),
        .s_axis_tready(rdma_ack_s[i].ready),
        .s_axis_tdata (rdma_ack_s[i].data),
        .m_axis_tvalid(rdma_ack_s[i+1].valid),
        .m_axis_tready(rdma_ack_s[i+1].ready),
        .m_axis_tdata (rdma_ack_s[i+1].data)
    );

    // RDMA rd command
    axis_register_slice_rdma_128 inst_rdma_req_rd_nc (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(rdma_rd_req_s[i].valid),
        .s_axis_tready(rdma_rd_req_s[i].ready),
        .s_axis_tdata (rdma_rd_req_s[i].data),
        .m_axis_tvalid(rdma_rd_req_s[i+1].valid),
        .m_axis_tready(rdma_rd_req_s[i+1].ready),
        .m_axis_tdata (rdma_rd_req_s[i+1].data)
    );

    // Read data crossing
    axis_register_slice_rdma_data_512 inst_rdma_data_rd_req_nc (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(axis_rdma_rd_req_s[i].tvalid),
        .s_axis_tready(axis_rdma_rd_req_s[i].tready),
        .s_axis_tdata (axis_rdma_rd_req_s[i].tdata),
        .s_axis_tkeep (axis_rdma_rd_req_s[i].tkeep),
        .s_axis_tlast (axis_rdma_rd_req_s[i].tlast),
        .m_axis_tvalid(axis_rdma_rd_req_s[i+1].tvalid),
        .m_axis_tready(axis_rdma_rd_req_s[i+1].tready),
        .m_axis_tdata (axis_rdma_rd_req_s[i+1].tdata),
        .m_axis_tkeep (axis_rdma_rd_req_s[i+1].tkeep),
        .m_axis_tlast (axis_rdma_rd_req_s[i+1].tlast)
    );

    axis_register_slice_rdma_data_512 inst_rdma_data_rd_rsp_nc (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(axis_rdma_rd_rsp_s[i].tvalid),
        .s_axis_tready(axis_rdma_rd_rsp_s[i].tready),
        .s_axis_tdata (axis_rdma_rd_rsp_s[i].tdata),
        .s_axis_tkeep (axis_rdma_rd_rsp_s[i].tkeep),
        .s_axis_tlast (axis_rdma_rd_rsp_s[i].tlast),
        .m_axis_tvalid(axis_rdma_rd_rsp_s[i+1].tvalid),
        .m_axis_tready(axis_rdma_rd_rsp_s[i+1].tready),
        .m_axis_tdata (axis_rdma_rd_rsp_s[i+1].tdata),
        .m_axis_tkeep (axis_rdma_rd_rsp_s[i+1].tkeep),
        .m_axis_tlast (axis_rdma_rd_rsp_s[i+1].tlast)
    );

    // RDMA wr command
    axis_register_slice_rdma_128 inst_rdma_req_wr_nc (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(rdma_wr_req_s[i].valid),
        .s_axis_tready(rdma_wr_req_s[i].ready),
        .s_axis_tdata (rdma_wr_req_s[i].data),
        .m_axis_tvalid(rdma_wr_req_s[i+1].valid),
        .m_axis_tready(rdma_wr_req_s[i+1].ready),
        .m_axis_tdata (rdma_wr_req_s[i+1].data)
    );

    // Write data crossing
    axis_register_slice_rdma_data_512 inst_rdma_data_wr_nc (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(axis_rdma_wr_s[i].tvalid),
        .s_axis_tready(axis_rdma_wr_s[i].tready),
        .s_axis_tdata (axis_rdma_wr_s[i].tdata),
        .s_axis_tkeep (axis_rdma_wr_s[i].tkeep),
        .s_axis_tlast (axis_rdma_wr_s[i].tlast),
        .m_axis_tvalid(axis_rdma_wr_s[i+1].tvalid),
        .m_axis_tready(axis_rdma_wr_s[i+1].tready),
        .m_axis_tdata (axis_rdma_wr_s[i+1].tdata),
        .m_axis_tkeep (axis_rdma_wr_s[i+1].tkeep),
        .m_axis_tlast (axis_rdma_wr_s[i+1].tlast)
    );

end

endmodule
