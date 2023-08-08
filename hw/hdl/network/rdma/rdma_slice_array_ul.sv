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
 * @brief   RDMA slice array
 *
 * RDMA slicing
 *
 */
module rdma_slice_array_ul #(
    parameter integer       N_STAGES = 2  
) (
    // Network
`ifdef EN_RPC
    metaIntf.m              m_rdma_sq_n,
    metaIntf.s              s_rdma_ack_n,
`endif
    metaIntf.s              s_rdma_rd_req_n,
    metaIntf.s              s_rdma_wr_req_n,
    AXI4SR.m                m_axis_rdma_rd_n,
    AXI4SR.s                s_axis_rdma_wr_n,
    
    // User
`ifdef EN_RPC    
    metaIntf.s              s_rdma_sq_u,
    metaIntf.m              m_rdma_ack_u,
`endif    
    metaIntf.m              m_rdma_rd_req_u,
    metaIntf.m              m_rdma_wr_req_u,
    AXI4SR.s                s_axis_rdma_rd_u,
    AXI4SR.m                m_axis_rdma_wr_u,

    input  wire             aclk,
    input  wire             aresetn
);

`ifdef EN_RPC    
metaIntf #(.STYPE(rdma_req_t)) rdma_sq_s [N_STAGES+1]();
metaIntf #(.STYPE(rdma_ack_t)) rdma_ack_s [N_STAGES+1]();
`endif
metaIntf #(.STYPE(req_t)) rdma_rd_req_s [N_STAGES+1]();
metaIntf #(.STYPE(req_t)) rdma_wr_req_s [N_STAGES+1]();
AXI4SR #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_rdma_rd_s [N_STAGES+1]();
AXI4SR #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_rdma_wr_s [N_STAGES+1]();

// Slaves
`ifdef EN_RPC    
`META_ASSIGN(s_rdma_ack_n, rdma_ack_s[0])
`endif
`META_ASSIGN(s_rdma_rd_req_n, rdma_rd_req_s[0])
`META_ASSIGN(s_rdma_wr_req_n, rdma_wr_req_s[0])
`AXISR_ASSIGN(s_axis_rdma_wr_n, axis_rdma_wr_s[0])

`ifdef EN_RPC 
`META_ASSIGN(s_rdma_sq_u, rdma_sq_s[0])
`endif
`AXISR_ASSIGN(s_axis_rdma_rd_u, axis_rdma_rd_s[0])

// Masters
`ifdef EN_RPC 
`META_ASSIGN(rdma_sq_s[N_STAGES], m_rdma_sq_n)
`endif
`AXISR_ASSIGN(axis_rdma_rd_s[N_STAGES], m_axis_rdma_rd_n)

`ifdef EN_RPC 
`META_ASSIGN(rdma_ack_s[N_STAGES], m_rdma_ack_u)
`endif
`META_ASSIGN(rdma_rd_req_s[N_STAGES], m_rdma_rd_req_u)
`META_ASSIGN(rdma_wr_req_s[N_STAGES], m_rdma_wr_req_u)
`AXISR_ASSIGN(axis_rdma_wr_s[N_STAGES], m_axis_rdma_wr_u)

for(genvar i = 0; i < N_STAGES; i++) begin

`ifdef EN_RPC 
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
    axis_register_slice_rdma_40 inst_rdma_acks_nc (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(rdma_ack_s[i].valid),
        .s_axis_tready(rdma_ack_s[i].ready),
        .s_axis_tdata (rdma_ack_s[i].data),
        .m_axis_tvalid(rdma_ack_s[i+1].valid),
        .m_axis_tready(rdma_ack_s[i+1].ready),
        .m_axis_tdata (rdma_ack_s[i+1].data)
    );
`endif    

    // RDMA rd command
    axis_register_slice_rdma_96 inst_rdma_req_rd_nc (
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
    axisr_register_slice_rdma_data_512 inst_rdma_data_rd_nc (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(axis_rdma_rd_s[i].tvalid),
        .s_axis_tready(axis_rdma_rd_s[i].tready),
        .s_axis_tdata (axis_rdma_rd_s[i].tdata),
        .s_axis_tkeep (axis_rdma_rd_s[i].tkeep),
        .s_axis_tid   (axis_rdma_rd_s[i].tid),
        .s_axis_tlast (axis_rdma_rd_s[i].tlast),
        .m_axis_tvalid(axis_rdma_rd_s[i+1].tvalid),
        .m_axis_tready(axis_rdma_rd_s[i+1].tready),
        .m_axis_tdata (axis_rdma_rd_s[i+1].tdata),
        .m_axis_tkeep (axis_rdma_rd_s[i+1].tkeep),
        .m_axis_tid   (axis_rdma_rd_s[i+1].tid),
        .m_axis_tlast (axis_rdma_rd_s[i+1].tlast)
    );

    // RDMA wr command
    axis_register_slice_rdma_96 inst_rdma_req_wr_nc (
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
    axisr_register_slice_rdma_data_512 inst_rdma_data_wr_nc (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(axis_rdma_wr_s[i].tvalid),
        .s_axis_tready(axis_rdma_wr_s[i].tready),
        .s_axis_tdata (axis_rdma_wr_s[i].tdata),
        .s_axis_tkeep (axis_rdma_wr_s[i].tkeep),
        .s_axis_tid   (axis_rdma_wr_s[i].tid),
        .s_axis_tlast (axis_rdma_wr_s[i].tlast),
        .m_axis_tvalid(axis_rdma_wr_s[i+1].tvalid),
        .m_axis_tready(axis_rdma_wr_s[i+1].tready),
        .m_axis_tdata (axis_rdma_wr_s[i+1].tdata),
        .m_axis_tkeep (axis_rdma_wr_s[i+1].tkeep),
        .m_axis_tid   (axis_rdma_wr_s[i+1].tid),
        .m_axis_tlast (axis_rdma_wr_s[i+1].tlast)
    );

end

endmodule
