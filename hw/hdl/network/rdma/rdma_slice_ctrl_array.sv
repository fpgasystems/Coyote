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
 * @brief   RDMA ctrl slice array
 *
 * RDMA control slicing
 *
 */
module rdma_slice_ctrl_array #(
    parameter integer       N_STAGES = 2  
) (
    // Network
    metaIntf.m              m_rdma_qp_interface_n,
    metaIntf.m              m_rdma_conn_interface_n,
    
    // User
    metaIntf.s              s_rdma_qp_interface_u,
    metaIntf.s              s_rdma_conn_interface_u,

    input  wire             aclk,
    input  wire             aresetn
);

metaIntf #(.STYPE(logic[RDMA_QP_INTF_BITS-1:0])) rdma_qp_interface_s [N_STAGES+1]();
metaIntf #(.STYPE(logic[RDMA_QP_CONN_BITS-1:0])) rdma_conn_interface_s [N_STAGES+1]();

// Slaves
`META_ASSIGN(s_rdma_qp_interface_u, rdma_qp_interface_s[0])
`META_ASSIGN(s_rdma_conn_interface_u, rdma_conn_interface_s[0])

// Masters
`META_ASSIGN(rdma_qp_interface_s[N_STAGES], m_rdma_qp_interface_n)
`META_ASSIGN(rdma_conn_interface_s[N_STAGES], m_rdma_conn_interface_n)

for(genvar i = 0; i < N_STAGES; i++) begin

    // RDMA qp interface
    axis_register_slice_rdma_168 inst_rdma_qp_interface (
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

end

endmodule