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

`timescale 1ns / 1ps

import lynxTypes::*;

`include "axi_macros.svh"
`include "lynx_macros.svh"

/**
 * @brief   RDMA clock crossing
 *
 * The clock crossing from nclk -> aclk
 */
module rdma_ccross_net_late #(
    parameter integer       ENABLED = 0
) (
    // ACLK
    metaIntf.s              s_rdma_qp_interface_aclk,
    metaIntf.s              s_rdma_conn_interface_aclk,

    metaIntf.s              s_rdma_sq_aclk,
    metaIntf.m              m_rdma_ack_aclk,

    metaIntf.m              m_rdma_rd_req_aclk,
    metaIntf.m              m_rdma_wr_req_aclk,
    AXI4S.s                 s_axis_rdma_rd_req_aclk,
    AXI4S.s                 s_axis_rdma_rd_rsp_aclk,
    AXI4S.m                 m_axis_rdma_wr_aclk,

    metaIntf.s              s_rdma_mem_rd_cmd_nclk,
    metaIntf.s              s_rdma_mem_wr_cmd_nclk,
    metaIntf.m              m_rdma_mem_rd_sts_nclk,
    metaIntf.m              m_rdma_mem_wr_sts_nclk,
    AXI4S.m                 m_axis_rdma_mem_rd_nclk,
    AXI4S.s                 s_axis_rdma_mem_wr_nclk, 

    // NCLK
    metaIntf.m              m_rdma_qp_interface_nclk,
    metaIntf.m              m_rdma_conn_interface_nclk,

    metaIntf.m              m_rdma_sq_nclk,
    metaIntf.s              s_rdma_ack_nclk,

    metaIntf.s              s_rdma_rd_req_nclk,
    metaIntf.s              s_rdma_wr_req_nclk,
    AXI4S.m                 m_axis_rdma_rd_req_nclk,
    AXI4S.m                 m_axis_rdma_rd_rsp_nclk,
    AXI4S.s                 s_axis_rdma_wr_nclk,

    metaIntf.m              m_rdma_mem_rd_cmd_aclk,
    metaIntf.m              m_rdma_mem_wr_cmd_aclk,
    metaIntf.s              s_rdma_mem_rd_sts_aclk,
    metaIntf.s              s_rdma_mem_wr_sts_aclk,
    AXI4S.s                 s_axis_rdma_mem_rd_aclk,
    AXI4S.m                 m_axis_rdma_mem_wr_aclk,

    input  wire             aclk,
    input  wire             aresetn,
    input  wire             nclk,
    input  wire             nresetn
);

if(ENABLED == 1) begin

// ---------------------------------------------------------------------------------------------------
// Crossings
// ---------------------------------------------------------------------------------------------------

    // Qp interface clock crossing
    axis_clock_converter_rdma_184 inst_cross_qp_interface (
        .s_axis_aresetn(aresetn),
        .m_axis_aresetn(nresetn),
        .s_axis_aclk(aclk),
        .m_axis_aclk(nclk),
        .s_axis_tvalid(s_rdma_qp_interface_aclk.valid),
        .s_axis_tready(s_rdma_qp_interface_aclk.ready),
        .s_axis_tdata(s_rdma_qp_interface_aclk.data),  
        .m_axis_tvalid(m_rdma_qp_interface_nclk.valid),
        .m_axis_tready(m_rdma_qp_interface_nclk.ready),
        .m_axis_tdata(m_rdma_qp_interface_nclk.data)
    );

    // Connection interface clock crossing
    axis_clock_converter_rdma_184 inst_cross_conn_interface (
        .s_axis_aresetn(aresetn),
        .m_axis_aresetn(nresetn),
        .s_axis_aclk(aclk),
        .m_axis_aclk(nclk),
        .s_axis_tvalid(s_rdma_conn_interface_aclk.valid),
        .s_axis_tready(s_rdma_conn_interface_aclk.ready),
        .s_axis_tdata(s_rdma_conn_interface_aclk.data),  
        .m_axis_tvalid(m_rdma_conn_interface_nclk.valid),
        .m_axis_tready(m_rdma_conn_interface_nclk.ready),
        .m_axis_tdata(m_rdma_conn_interface_nclk.data)
    );

    // RDMA req host
    axis_data_fifo_rdma_ccross_256 inst_cross_rdma_host_req (
        .m_axis_aclk(nclk),
        .s_axis_aclk(aclk),
        .s_axis_aresetn(aresetn),
        .s_axis_tvalid(s_rdma_sq_aclk.valid),
        .s_axis_tready(s_rdma_sq_aclk.ready),
        .s_axis_tdata(s_rdma_sq_aclk.data),
        .m_axis_tvalid(m_rdma_sq_nclk.valid),
        .m_axis_tready(m_rdma_sq_nclk.ready),
        .m_axis_tdata(m_rdma_sq_nclk.data)
    );

    // RDMA acks
    axis_data_fifo_rdma_ccross_32 inst_cross_rdma_acks (
        .m_axis_aclk(aclk),
        .s_axis_aclk(nclk),
        .s_axis_aresetn(nresetn),
        .s_axis_tvalid(s_rdma_ack_nclk.valid),
        .s_axis_tready(s_rdma_ack_nclk.ready),
        .s_axis_tdata(s_rdma_ack_nclk.data),
        .m_axis_tvalid(m_rdma_ack_aclk.valid),
        .m_axis_tready(m_rdma_ack_aclk.ready),
        .m_axis_tdata(m_rdma_ack_aclk.data)
    );

    axis_data_fifo_rdma_ccross_128 inst_cross_rdma_req_rd (
        .m_axis_aclk(aclk),
        .s_axis_aclk(nclk),
        .s_axis_aresetn(nresetn),
        .s_axis_tvalid(s_rdma_rd_req_nclk.valid),
        .s_axis_tready(s_rdma_rd_req_nclk.ready),
        .s_axis_tdata(s_rdma_rd_req_nclk.data),
        .m_axis_tvalid(m_rdma_rd_req_aclk.valid),
        .m_axis_tready(m_rdma_rd_req_aclk.ready),
        .m_axis_tdata(m_rdma_rd_req_aclk.data)
    );

    // Read data crossing
    axis_data_fifo_rdma_ccross_data_512 inst_cross_rdma_data_rd_req (
        .m_axis_aclk(nclk),
        .s_axis_aclk(aclk),
        .s_axis_aresetn(aresetn),
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

    axis_data_fifo_rdma_ccross_data_512 inst_cross_rdma_data_rd_rsp (
        .m_axis_aclk(nclk),
        .s_axis_aclk(aclk),
        .s_axis_aresetn(aresetn),
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

    axis_data_fifo_rdma_ccross_128 inst_cross_rdma_req_wr (
        .m_axis_aclk(aclk),
        .s_axis_aclk(nclk),
        .s_axis_aresetn(nresetn),
        .s_axis_tvalid(s_rdma_wr_req_nclk.valid),
        .s_axis_tready(s_rdma_wr_req_nclk.ready),
        .s_axis_tdata(s_rdma_wr_req_nclk.data),
        .m_axis_tvalid(m_rdma_wr_req_aclk.valid),
        .m_axis_tready(m_rdma_wr_req_aclk.ready),
        .m_axis_tdata(m_rdma_wr_req_aclk.data)
    );

    // Write data crossing
    axis_data_fifo_rdma_ccross_data_512 inst_cross_rdma_data_wr (
        .m_axis_aclk(aclk),
        .s_axis_aclk(nclk),
        .s_axis_aresetn(nresetn),
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

    //
    // Memory
    //

    axis_data_fifo_rdma_ccross_96 inst_rdma_mem_cmd_rd(
        .m_axis_aclk(aclk),
        .s_axis_aclk(nclk),
        .s_axis_aresetn(nresetn),
        .s_axis_tvalid(s_rdma_mem_rd_cmd_nclk.valid),
        .s_axis_tready(s_rdma_mem_rd_cmd_nclk.ready),
        .s_axis_tdata (s_rdma_mem_rd_cmd_nclk.data),
        .m_axis_tvalid(m_rdma_mem_rd_cmd_aclk.valid),
        .m_axis_tready(m_rdma_mem_rd_cmd_aclk.ready),
        .m_axis_tdata (m_rdma_mem_rd_cmd_aclk.data)
    );

    axis_data_fifo_rdma_ccross_96 inst_rdma_mem_cmd_wr(
        .m_axis_aclk(aclk),
        .s_axis_aclk(nclk),
        .s_axis_aresetn(nresetn),
        .s_axis_tvalid(s_rdma_mem_wr_cmd_nclk.valid),
        .s_axis_tready(s_rdma_mem_wr_cmd_nclk.ready),
        .s_axis_tdata (s_rdma_mem_wr_cmd_nclk.data),
        .m_axis_tvalid(m_rdma_mem_wr_cmd_aclk.valid),
        .m_axis_tready(m_rdma_mem_wr_cmd_aclk.ready),
        .m_axis_tdata (m_rdma_mem_wr_cmd_aclk.data)
    );

    // Mem status
    axis_data_fifo_rdma_ccross_8 inst_rdma_mem_sts_rd(
        .m_axis_aclk(nclk),
        .s_axis_aclk(aclk),
        .s_axis_aresetn(aresetn),
        .s_axis_tvalid(s_rdma_mem_rd_sts_aclk.valid),
        .s_axis_tready(s_rdma_mem_rd_sts_aclk.ready),
        .s_axis_tdata (s_rdma_mem_rd_sts_aclk.data),
        .m_axis_tvalid(m_rdma_mem_rd_sts_nclk.valid),
        .m_axis_tready(m_rdma_mem_rd_sts_nclk.ready),
        .m_axis_tdata (m_rdma_mem_rd_sts_nclk.data)
    );

    axis_data_fifo_rdma_ccross_8 inst_rdma_mem_sts_wr(
        .m_axis_aclk(nclk),
        .s_axis_aclk(aclk),
        .s_axis_aresetn(aresetn),
        .s_axis_tvalid(s_rdma_mem_wr_sts_aclk.valid),
        .s_axis_tready(s_rdma_mem_wr_sts_aclk.ready),
        .s_axis_tdata (s_rdma_mem_wr_sts_aclk.data),
        .m_axis_tvalid(m_rdma_mem_wr_sts_nclk.valid),
        .m_axis_tready(m_rdma_mem_wr_sts_nclk.ready),
        .m_axis_tdata (m_rdma_mem_wr_sts_nclk.data)
    );

    // Mem data
    axis_data_fifo_rdma_ccross_data_512 inst_mem_rd_data (
        .m_axis_aclk(nclk),
        .s_axis_aclk(aclk),
        .s_axis_aresetn(aresetn),
        .s_axis_tvalid(s_axis_rdma_mem_rd_aclk.tvalid),
        .s_axis_tready(s_axis_rdma_mem_rd_aclk.tready),
        .s_axis_tdata (s_axis_rdma_mem_rd_aclk.tdata),
        .s_axis_tkeep (s_axis_rdma_mem_rd_aclk.tkeep),
        .s_axis_tlast (s_axis_rdma_mem_rd_aclk.tlast),
        .m_axis_tvalid(m_axis_rdma_mem_rd_nclk.tvalid),
        .m_axis_tready(m_axis_rdma_mem_rd_nclk.tready),
        .m_axis_tdata (m_axis_rdma_mem_rd_nclk.tdata),
        .m_axis_tkeep (m_axis_rdma_mem_rd_nclk.tkeep),
        .m_axis_tlast (m_axis_rdma_mem_rd_nclk.tlast)
    );

    axis_data_fifo_rdma_ccross_data_512 inst_mem_wr_data (
        .m_axis_aclk(aclk),
        .s_axis_aclk(nclk),
        .s_axis_aresetn(nresetn),
        .s_axis_tvalid(s_axis_rdma_mem_wr_nclk.tvalid),
        .s_axis_tready(s_axis_rdma_mem_wr_nclk.tready),
        .s_axis_tdata (s_axis_rdma_mem_wr_nclk.tdata),
        .s_axis_tkeep (s_axis_rdma_mem_wr_nclk.tkeep),
        .s_axis_tlast (s_axis_rdma_mem_wr_nclk.tlast),
        .m_axis_tvalid(m_axis_rdma_mem_wr_aclk.tvalid),
        .m_axis_tready(m_axis_rdma_mem_wr_aclk.tready),
        .m_axis_tdata (m_axis_rdma_mem_wr_aclk.tdata),
        .m_axis_tkeep (m_axis_rdma_mem_wr_aclk.tkeep),
        .m_axis_tlast (m_axis_rdma_mem_wr_aclk.tlast)
    );

end
else begin

//
// Decouple it a bit 
//

    // Qp interface clock crossing
    axis_register_slice_rdma_184 inst_clk_cnvrt_qp_interface_nc (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_rdma_qp_interface_aclk.valid),
        .s_axis_tready(s_rdma_qp_interface_aclk.ready),
        .s_axis_tdata(s_rdma_qp_interface_aclk.data),  
        .m_axis_tvalid(m_rdma_qp_interface_nclk.valid),
        .m_axis_tready(m_rdma_qp_interface_nclk.ready),
        .m_axis_tdata(m_rdma_qp_interface_nclk.data)
    );

    // Connection interface clock crossing
    axis_register_slice_rdma_184 inst_clk_cnvrt_conn_interface_nc (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_rdma_conn_interface_aclk.valid),
        .s_axis_tready(s_rdma_conn_interface_aclk.ready),
        .s_axis_tdata(s_rdma_conn_interface_aclk.data),  
        .m_axis_tvalid(m_rdma_conn_interface_nclk.valid),
        .m_axis_tready(m_rdma_conn_interface_nclk.ready),
        .m_axis_tdata(m_rdma_conn_interface_nclk.data)
    );

    // RDMA req host
    axis_data_fifo_rdma_512 inst_rdma_sq_cross_nc (
        .s_axis_aclk(aclk),
        .s_axis_aresetn(aresetn),
        .s_axis_tvalid(s_rdma_sq_aclk.valid),
        .s_axis_tready(s_rdma_sq_aclk.ready),
        .s_axis_tdata(s_rdma_sq_aclk.data),
        .m_axis_tvalid(m_rdma_sq_nclk.valid),
        .m_axis_tready(m_rdma_sq_nclk.ready),
        .m_axis_tdata(m_rdma_sq_nclk.data)
    );

    // RDMA acks
    axis_data_fifo_rdma_32 inst_rdma_ack_cross_nc (
        .s_axis_aclk(aclk),
        .s_axis_aresetn(aresetn),
        .s_axis_tvalid(s_rdma_ack_nclk.valid),
        .s_axis_tready(s_rdma_ack_nclk.ready),
        .s_axis_tdata(s_rdma_ack_nclk.data),
        .m_axis_tvalid(m_rdma_ack_aclk.valid),
        .m_axis_tready(m_rdma_ack_aclk.ready),
        .m_axis_tdata(m_rdma_ack_aclk.data)
    );

    axis_data_fifo_rdma_128 inst_rdma_req_rd_nc (
        .s_axis_aclk(aclk),
        .s_axis_aresetn(aresetn),
        .s_axis_tvalid(s_rdma_rd_req_nclk.valid),
        .s_axis_tready(s_rdma_rd_req_nclk.ready),
        .s_axis_tdata(s_rdma_rd_req_nclk.data),
        .m_axis_tvalid(m_rdma_rd_req_aclk.valid),
        .m_axis_tready(m_rdma_rd_req_aclk.ready),
        .m_axis_tdata(m_rdma_rd_req_aclk.data)
    );

    // Read data crossing
    axis_data_fifo_rdma_data_512 inst_rdma_data_rd_req_nc (
        .s_axis_aclk(aclk),
        .s_axis_aresetn(aresetn),
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

    axis_data_fifo_rdma_data_512 inst_rdma_data_rd_rsp_nc (
        .s_axis_aclk(aclk),
        .s_axis_aresetn(aresetn),
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

    axis_data_fifo_rdma_128 inst_rdma_req_wr_nc (
        .s_axis_aclk(aclk),
        .s_axis_aresetn(aresetn),
        .s_axis_tvalid(s_rdma_wr_req_nclk.valid),
        .s_axis_tready(s_rdma_wr_req_nclk.ready),
        .s_axis_tdata(s_rdma_wr_req_nclk.data),
        .m_axis_tvalid(m_rdma_wr_req_aclk.valid),
        .m_axis_tready(m_rdma_wr_req_aclk.ready),
        .m_axis_tdata(m_rdma_wr_req_aclk.data)
    );

    // Write data crossing
    axis_data_fifo_rdma_data_512 inst_rdma_data_wr_nc (
        .s_axis_aclk(aclk),
        .s_axis_aresetn(aresetn),
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

    //
    // Memory
    //
    axis_data_fifo_rdma_96 inst_rdma_reg_mem_cmd_rd(
            .s_axis_aclk(aclk),
            .s_axis_aresetn(aresetn),
            .s_axis_tvalid(s_rdma_mem_rd_cmd_nclk.valid),
            .s_axis_tready(s_rdma_mem_rd_cmd_nclk.ready),
            .s_axis_tdata (s_rdma_mem_rd_cmd_nclk.data),
            .m_axis_tvalid(m_rdma_mem_rd_cmd_aclk.valid),
            .m_axis_tready(m_rdma_mem_rd_cmd_aclk.ready),
            .m_axis_tdata (m_rdma_mem_rd_cmd_aclk.data)
        );

        axis_data_fifo_rdma_96 inst_rdma_reg_mem_cmd_wr(
            .s_axis_aclk(aclk),
            .s_axis_aresetn(aresetn),
            .s_axis_tvalid(s_rdma_mem_wr_cmd_nclk.valid),
            .s_axis_tready(s_rdma_mem_wr_cmd_nclk.ready),
            .s_axis_tdata (s_rdma_mem_wr_cmd_nclk.data),
            .m_axis_tvalid(m_rdma_mem_wr_cmd_aclk.valid),
            .m_axis_tready(m_rdma_mem_wr_cmd_aclk.ready),
            .m_axis_tdata (m_rdma_mem_wr_cmd_aclk.data)
        );

        // Mem status
        axis_data_fifo_rdma_8 inst_rdma_reg_mem_sts_rd(
            .s_axis_aclk(aclk),
            .s_axis_aresetn(aresetn),
            .s_axis_tvalid(s_rdma_mem_rd_sts_aclk.valid),
            .s_axis_tready(s_rdma_mem_rd_sts_aclk.ready),
            .s_axis_tdata (s_rdma_mem_rd_sts_aclk.data),
            .m_axis_tvalid(m_rdma_mem_rd_sts_nclk.valid),
            .m_axis_tready(m_rdma_mem_rd_sts_nclk.ready),
            .m_axis_tdata (m_rdma_mem_rd_sts_nclk.data)
        );

        axis_data_fifo_rdma_8 inst_rdma_reg_mem_sts_wr(
            .s_axis_aclk(aclk),
            .s_axis_aresetn(aresetn),
            .s_axis_tvalid(s_rdma_mem_wr_sts_aclk.valid),
            .s_axis_tready(s_rdma_mem_wr_sts_aclk.ready),
            .s_axis_tdata (s_rdma_mem_wr_sts_aclk.data),
            .m_axis_tvalid(m_rdma_mem_wr_sts_nclk.valid),
            .m_axis_tready(m_rdma_mem_wr_sts_nclk.ready),
            .m_axis_tdata (m_rdma_mem_wr_sts_nclk.data)
        );

        // Mem data
        axis_data_fifo_rdma_512 inst_reg_mem_rd_data (
            .s_axis_aclk(aclk),
            .s_axis_aresetn(aresetn),
            .s_axis_tvalid(s_axis_rdma_mem_rd_aclk.tvalid),
            .s_axis_tready(s_axis_rdma_mem_rd_aclk.tready),
            .s_axis_tdata (s_axis_rdma_mem_rd_aclk.tdata),
            .s_axis_tkeep (s_axis_rdma_mem_rd_aclk.tkeep),
            .s_axis_tlast (s_axis_rdma_mem_rd_aclk.tlast),
            .m_axis_tvalid(m_axis_rdma_mem_rd_nclk.tvalid),
            .m_axis_tready(m_axis_rdma_mem_rd_nclk.tready),
            .m_axis_tdata (m_axis_rdma_mem_rd_nclk.tdata),
            .m_axis_tkeep (m_axis_rdma_mem_rd_nclk.tkeep),
            .m_axis_tlast (m_axis_rdma_mem_rd_nclk.tlast)
        );

        axis_data_fifo_rdma_512 inst_reg_mem_wr_data (
            .s_axis_aclk(aclk),
            .s_axis_aresetn(aresetn),
            .s_axis_tvalid(s_axis_rdma_mem_wr_nclk.tvalid),
            .s_axis_tready(s_axis_rdma_mem_wr_nclk.tready),
            .s_axis_tdata (s_axis_rdma_mem_wr_nclk.tdata),
            .s_axis_tkeep (s_axis_rdma_mem_wr_nclk.tkeep),
            .s_axis_tlast (s_axis_rdma_mem_wr_nclk.tlast),
            .m_axis_tvalid(m_axis_rdma_mem_wr_aclk.tvalid),
            .m_axis_tready(m_axis_rdma_mem_wr_aclk.tready),
            .m_axis_tdata (m_axis_rdma_mem_wr_aclk.tdata),
            .m_axis_tkeep (m_axis_rdma_mem_wr_aclk.tkeep),
            .m_axis_tlast (m_axis_rdma_mem_wr_aclk.tlast)
        );

end

endmodule
