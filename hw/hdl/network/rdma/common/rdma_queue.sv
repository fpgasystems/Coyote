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

module rdma_queue (
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
    axis_data_fifo_rdma_256 inst_rdma_sq_nc (
        .s_axis_aclk(aclk),
        .s_axis_aresetn(aresetn),
        .s_axis_tvalid(s_rdma_sq_u.valid),
        .s_axis_tready(s_rdma_sq_u.ready),
        .s_axis_tdata (s_rdma_sq_u.data),
        .m_axis_tvalid(m_rdma_sq_n.valid),
        .m_axis_tready(m_rdma_sq_n.ready),
        .m_axis_tdata (m_rdma_sq_n.data)
    );

    // RDMA acks
    axis_data_fifo_rdma_32 inst_rdma_acks_nc (
        .s_axis_aclk(aclk),
        .s_axis_aresetn(aresetn),
        .s_axis_tvalid(s_rdma_ack_n.valid),
        .s_axis_tready(s_rdma_ack_n.ready),
        .s_axis_tdata (s_rdma_ack_n.data),
        .m_axis_tvalid(m_rdma_ack_u.valid),
        .m_axis_tready(m_rdma_ack_u.ready),
        .m_axis_tdata (m_rdma_ack_u.data)
    );

    // RDMA rd command
    axis_data_fifo_rdma_128 inst_rdma_req_rd_nc (
        .s_axis_aclk(aclk),
        .s_axis_aresetn(aresetn),
        .s_axis_tvalid(s_rdma_rd_req_n.valid),
        .s_axis_tready(s_rdma_rd_req_n.ready),
        .s_axis_tdata (s_rdma_rd_req_n.data),
        .m_axis_tvalid(m_rdma_rd_req_u.valid),
        .m_axis_tready(m_rdma_rd_req_u.ready),
        .m_axis_tdata (m_rdma_rd_req_u.data)
    );

    // Read data crossing
    axis_data_fifo_rdma_data_512 inst_rdma_data_rd_req_nc (
        .s_axis_aclk(aclk),
        .s_axis_aresetn(aresetn),
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

    axis_data_fifo_rdma_data_512 inst_rdma_data_rd_rsp_nc (
        .s_axis_aclk(aclk),
        .s_axis_aresetn(aresetn),
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
    axis_data_fifo_rdma_128 inst_rdma_req_wr_nc (
        .s_axis_aclk(aclk),
        .s_axis_aresetn(aresetn),
        .s_axis_tvalid(s_rdma_wr_req_n.valid),
        .s_axis_tready(s_rdma_wr_req_n.ready),
        .s_axis_tdata (s_rdma_wr_req_n.data),
        .m_axis_tvalid(m_rdma_wr_req_u.valid),
        .m_axis_tready(m_rdma_wr_req_u.ready),
        .m_axis_tdata (m_rdma_wr_req_u.data)
    );

    // Write data crossing
    axis_data_fifo_rdma_data_512 inst_rdma_data_wr_nc (
        .s_axis_aclk(aclk),
        .s_axis_aresetn(aresetn),
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
