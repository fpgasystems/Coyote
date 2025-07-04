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

module rdma_slice (
    // Network 
    metaIntf.m              m_rdma_sq_n,
    metaIntf.s              s_rdma_ack_n,
    metaIntf.s              s_rdma_rd_req_n,
    metaIntf.s              s_rdma_wr_req_n,
    AXI4S.m                 m_axis_rdma_rd_req_n,
    AXI4S.m                 m_axis_rdma_rd_rsp_n,
    AXI4S.s                 s_axis_rdma_wr_n,
    
    // User 
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

    // RDMA send queue
    axis_register_slice_rdma_256 inst_rdma_sq_nc (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_rdma_sq_u.valid),
        .s_axis_tready(s_rdma_sq_u.ready),
        .s_axis_tdata (s_rdma_sq_u.data),
        .m_axis_tvalid(m_rdma_sq_n.valid),
        .m_axis_tready(m_rdma_sq_n.ready),
        .m_axis_tdata (m_rdma_sq_n.data)
    );

    // RDMA acks
    axis_register_slice_rdma_32 inst_rdma_acks_nc (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_rdma_ack_n.valid),
        .s_axis_tready(s_rdma_ack_n.ready),
        .s_axis_tdata (s_rdma_ack_n.data),
        .m_axis_tvalid(m_rdma_ack_u.valid),
        .m_axis_tready(m_rdma_ack_u.ready),
        .m_axis_tdata (m_rdma_ack_u.data)
    );

    // RDMA rd command
    axis_register_slice_rdma_128 inst_rdma_req_rd_nc (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_rdma_rd_req_n.valid),
        .s_axis_tready(s_rdma_rd_req_n.ready),
        .s_axis_tdata (s_rdma_rd_req_n.data),
        .m_axis_tvalid(m_rdma_rd_req_u.valid),
        .m_axis_tready(m_rdma_rd_req_u.ready),
        .m_axis_tdata (m_rdma_rd_req_u.data)
    );

    // Read data crossing
    axis_register_slice_rdma_data_512 inst_rdma_data_rd_req_nc (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_axis_rdma_rd_req_u.tvalid),
        .s_axis_tready(s_axis_rdma_rd_req_u.tready),
        .s_axis_tdata (s_axis_rdma_rd_req_u.tdata),
        .s_axis_tkeep (s_axis_rdma_rd_req_u.tkeep),
        .s_axis_tlast (s_axis_rdma_rd_req_u.tlast),
        .m_axis_tvalid(m_axis_rdma_rd_req_n.tvalid),
        .m_axis_tready(m_axis_rdma_rd_req_n.tready),
        .m_axis_tdata (m_axis_rdma_rd_req_n.tdata),
        .m_axis_tkeep (m_axis_rdma_rd_req_n.tkeep),
        .m_axis_tlast (m_axis_rdma_rd_req_n.tlast)
    );

    axis_register_slice_rdma_data_512 inst_rdma_data_rd_rsp_nc (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_axis_rdma_rd_rsp_u.tvalid),
        .s_axis_tready(s_axis_rdma_rd_rsp_u.tready),
        .s_axis_tdata (s_axis_rdma_rd_rsp_u.tdata),
        .s_axis_tkeep (s_axis_rdma_rd_rsp_u.tkeep),
        .s_axis_tlast (s_axis_rdma_rd_rsp_u.tlast),
        .m_axis_tvalid(m_axis_rdma_rd_rsp_n.tvalid),
        .m_axis_tready(m_axis_rdma_rd_rsp_n.tready),
        .m_axis_tdata (m_axis_rdma_rd_rsp_n.tdata),
        .m_axis_tkeep (m_axis_rdma_rd_rsp_n.tkeep),
        .m_axis_tlast (m_axis_rdma_rd_rsp_n.tlast)
    );


    // RDMA wr command
    axis_register_slice_rdma_128 inst_rdma_req_wr_nc (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_rdma_wr_req_n.valid),
        .s_axis_tready(s_rdma_wr_req_n.ready),
        .s_axis_tdata (s_rdma_wr_req_n.data),
        .m_axis_tvalid(m_rdma_wr_req_u.valid),
        .m_axis_tready(m_rdma_wr_req_u.ready),
        .m_axis_tdata (m_rdma_wr_req_u.data)
    );

    // Write data crossing
    axis_register_slice_rdma_data_512 inst_rdma_data_wr_nc (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_axis_rdma_wr_n.tvalid),
        .s_axis_tready(s_axis_rdma_wr_n.tready),
        .s_axis_tdata (s_axis_rdma_wr_n.tdata),
        .s_axis_tkeep (s_axis_rdma_wr_n.tkeep),
        .s_axis_tlast (s_axis_rdma_wr_n.tlast),
        .m_axis_tvalid(m_axis_rdma_wr_u.tvalid),
        .m_axis_tready(m_axis_rdma_wr_u.tready),
        .m_axis_tdata (m_axis_rdma_wr_u.tdata),
        .m_axis_tkeep (m_axis_rdma_wr_u.tkeep),
        .m_axis_tlast (m_axis_rdma_wr_u.tlast)
    );

endmodule
