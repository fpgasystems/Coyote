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
 * @brief   RDMA arbitration
 *
 * Arbitration layer between all present user regions
 */
module rdma_arbiter (
    input  wire             aclk,
    input  wire             aresetn,

    // Network
    metaIntf.m              m_rdma_sq_net,
    metaIntf.s              s_rdma_cq_net,

    metaIntf.s              s_rdma_rq_rd_net,
    metaIntf.s              s_rdma_rq_wr_net,
    AXI4S.m                 m_axis_rdma_rd_req_net,
    AXI4S.m                 m_axis_rdma_rd_rsp_net,
    AXI4S.s                 s_axis_rdma_wr_net,

    // User
    metaIntf.s              s_rdma_sq_user [N_REGIONS],
    metaIntf.m              m_rdma_cq_user [N_REGIONS],
    metaIntf.m              m_rdma_host_cq_user,

    metaIntf.m              m_rdma_rq_rd_user [N_REGIONS],
    metaIntf.m              m_rdma_rq_wr_user [N_REGIONS],
    AXI4S.s                 s_axis_rdma_rd_req_user [N_REGIONS],
    AXI4S.s                 s_axis_rdma_rd_rsp_user [N_REGIONS],
    AXI4S.m                 m_axis_rdma_wr_user [N_REGIONS]
);

//
// Arbitration
//

// Arbitration RDMA requests host
rdma_meta_tx_arbiter inst_rdma_req_host_arbiter (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_meta(s_rdma_sq_user),
    .m_meta(m_rdma_sq_net),
    .s_axis_rd(s_axis_rdma_rd_req_user),
    .m_axis_rd(m_axis_rdma_rd_req_net),
    .vfid()
);

// Arbitration ACKs
metaIntf #(.STYPE(ack_t)) rdma_cq_user [N_REGIONS] ();

rdma_meta_rx_arbiter inst_rdma_ack_arbiter (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_meta(s_rdma_cq_net),
    .m_meta_user(rdma_cq_user),
    .m_meta_host(m_rdma_host_cq_user),
    .vfid()
);

for(genvar i = 0; i < N_REGIONS; i++) begin
    assign m_rdma_cq_user[i].valid = rdma_cq_user[i].valid;
    assign m_rdma_cq_user[i].data  = rdma_cq_user[i].data;

    assign rdma_cq_user[i].ready = 1'b1;
end

//
// Memory
//

// Read command and data
rdma_mux_cmd_rd inst_mux_cmd_rd (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_req(s_rdma_rq_rd_net),
    .m_req(m_rdma_rq_rd_user),
    .s_axis_rd(s_axis_rdma_rd_rsp_user),
    .m_axis_rd(m_axis_rdma_rd_rsp_net)
);

// Write command crossing
rdma_mux_cmd_wr inst_mux_cmd_wr (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_req(s_rdma_rq_wr_net),
    .m_req(m_rdma_rq_wr_user),
    .s_axis_wr(s_axis_rdma_wr_net),
    .m_axis_wr(m_axis_rdma_wr_user),
    .m_wr_rdy()
);

endmodule