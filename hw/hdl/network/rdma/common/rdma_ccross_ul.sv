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

`timescale 1ns / 1ps

import lynxTypes::*;

`include "axi_macros.svh"
`include "lynx_macros.svh"

/**
 * @brief   RDMA clock crossing
 *
 * The clock crossing from nclk -> aclk
 */
module rdma_ccross_ul (
    // Network
    metaIntf.m              m_rdma_sq_nclk,
    metaIntf.s              s_rdma_ack_nclk,
    metaIntf.s              s_rdma_rd_req_nclk,
    metaIntf.s              s_rdma_wr_req_nclk,
    AXI4S.m                 m_axis_rdma_rd_req_nclk,
    AXI4S.m                 m_axis_rdma_rd_rsp_nclk,
    AXI4S.s                 s_axis_rdma_wr_nclk,

    // User
    metaIntf.s              s_rdma_sq_aclk,
    metaIntf.m              m_rdma_ack_aclk,
    metaIntf.m              m_rdma_rd_req_aclk,
    metaIntf.m              m_rdma_wr_req_aclk,
    AXI4S.s                 s_axis_rdma_rd_req_aclk,
    AXI4S.s                 s_axis_rdma_rd_rsp_aclk,
    AXI4S.m                 m_axis_rdma_wr_aclk,

    input  wire             nclk,
    input  wire             nresetn,
    input  wire             aclk,
    input  wire             aresetn
);

// ---------------------------------------------------------------------------------------------------
// Crossings
// ---------------------------------------------------------------------------------------------------

    // RDMA req host
    axis_clock_converter_rdma_256 inst_cross_rdma_host_req (
        .m_axis_aclk(nclk),
        .s_axis_aclk(aclk),
        .s_axis_aresetn(aresetn),
        .m_axis_aresetn(nresetn),
        .s_axis_tvalid(s_rdma_sq_aclk.valid),
        .s_axis_tready(s_rdma_sq_aclk.ready),
        .s_axis_tdata (s_rdma_sq_aclk.data),
        .m_axis_tvalid(m_rdma_sq_nclk.valid),
        .m_axis_tready(m_rdma_sq_nclk.ready),
        .m_axis_tdata (m_rdma_sq_nclk.data)
    );

    axis_clock_converter_rdma_32 inst_cross_rdma_acks (
        .m_axis_aclk(aclk),
        .s_axis_aclk(nclk),
        .s_axis_aresetn(nresetn),
        .m_axis_aresetn(aresetn),
        .s_axis_tvalid(s_rdma_ack_nclk.valid),
        .s_axis_tready(s_rdma_ack_nclk.ready),
        .s_axis_tdata (s_rdma_ack_nclk.data),
        .m_axis_tvalid(m_rdma_ack_aclk.valid),
        .m_axis_tready(m_rdma_ack_aclk.ready),
        .m_axis_tdata (m_rdma_ack_aclk.data)
    );

    axis_clock_converter_rdma_128 inst_cross_rdma_req_rd (
        .m_axis_aclk(aclk),
        .s_axis_aclk(nclk),
        .s_axis_aresetn(nresetn),
        .m_axis_aresetn(aresetn),
        .s_axis_tvalid(s_rdma_rd_req_nclk.valid),
        .s_axis_tready(s_rdma_rd_req_nclk.ready),
        .s_axis_tdata (s_rdma_rd_req_nclk.data),
        .m_axis_tvalid(m_rdma_rd_req_aclk.valid),
        .m_axis_tready(m_rdma_rd_req_aclk.ready),
        .m_axis_tdata (m_rdma_rd_req_aclk.data)
    );

    // Read data crossing
    axis_clock_converter_rdma_data_512 inst_cross_rdma_data_rd_req (
        .m_axis_aclk(nclk),
        .s_axis_aclk(aclk),
        .s_axis_aresetn(aresetn),
        .m_axis_aresetn(nresetn),
        .s_axis_tvalid(s_axis_rdma_rd_req_aclk.tvalid),
        .s_axis_tready(s_axis_rdma_rd_req_aclk.tready),
        .s_axis_tdata (s_axis_rdma_rd_req_aclk.tdata),
        .s_axis_tkeep (s_axis_rdma_rd_req_aclk.tkeep),
        .s_axis_tlast (s_axis_rdma_rd_req_aclk.tlast),
        .m_axis_tvalid(m_axis_rdma_rd_req_nclk.tvalid),
        .m_axis_tready(m_axis_rdma_rd_req_nclk.tready),
        .m_axis_tdata (m_axis_rdma_rd_req_nclk.tdata),
        .m_axis_tkeep (m_axis_rdma_rd_req_nclk.tkeep),
        .m_axis_tlast (m_axis_rdma_rd_req_nclk.tlast)
    );

    axis_clock_converter_rdma_data_512 inst_cross_rdma_data_rd_rsp (
        .m_axis_aclk(nclk),
        .s_axis_aclk(aclk),
        .s_axis_aresetn(aresetn),
        .m_axis_aresetn(nresetn),
        .s_axis_tvalid(s_axis_rdma_rd_rsp_aclk.tvalid),
        .s_axis_tready(s_axis_rdma_rd_rsp_aclk.tready),
        .s_axis_tdata (s_axis_rdma_rd_rsp_aclk.tdata),
        .s_axis_tkeep (s_axis_rdma_rd_rsp_aclk.tkeep),
        .s_axis_tlast (s_axis_rdma_rd_rsp_aclk.tlast),
        .m_axis_tvalid(m_axis_rdma_rd_rsp_nclk.tvalid),
        .m_axis_tready(m_axis_rdma_rd_rsp_nclk.tready),
        .m_axis_tdata (m_axis_rdma_rd_rsp_nclk.tdata),
        .m_axis_tkeep (m_axis_rdma_rd_rsp_nclk.tkeep),
        .m_axis_tlast (m_axis_rdma_rd_rsp_nclk.tlast)
    );

    axis_clock_converter_rdma_128 inst_cross_rdma_req_wr (
        .m_axis_aclk(aclk),
        .s_axis_aclk(nclk),
        .s_axis_aresetn(nresetn),
        .m_axis_aresetn(aresetn),
        .s_axis_tvalid(s_rdma_wr_req_nclk.valid),
        .s_axis_tready(s_rdma_wr_req_nclk.ready),
        .s_axis_tdata (s_rdma_wr_req_nclk.data),
        .m_axis_tvalid(m_rdma_wr_req_aclk.valid),
        .m_axis_tready(m_rdma_wr_req_aclk.ready),
        .m_axis_tdata (m_rdma_wr_req_aclk.data)
    );

    // Write data crossing
    axis_clock_converter_rdma_data_512 inst_cross_rdma_data_wr (
        .m_axis_aclk(aclk),
        .s_axis_aclk(nclk),
        .s_axis_aresetn(nresetn),
        .m_axis_aresetn(aresetn),
        .s_axis_tvalid(s_axis_rdma_wr_nclk.tvalid),
        .s_axis_tready(s_axis_rdma_wr_nclk.tready),
        .s_axis_tdata(s_axis_rdma_wr_nclk.tdata),
        .s_axis_tkeep(s_axis_rdma_wr_nclk.tkeep),
        .s_axis_tlast(s_axis_rdma_wr_nclk.tlast),
        .m_axis_tvalid(m_axis_rdma_wr_aclk.tvalid),
        .m_axis_tready(m_axis_rdma_wr_aclk.tready),
        .m_axis_tdata(m_axis_rdma_wr_aclk.tdata),
        .m_axis_tkeep(m_axis_rdma_wr_aclk.tkeep),
        .m_axis_tlast(m_axis_rdma_wr_aclk.tlast)
    );

endmodule
