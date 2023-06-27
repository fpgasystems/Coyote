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

/**
 * @brief   RDMA RX meta arbitration
 *
 * Arbitration layer between all present user regions
 */
module rdma_meta_rx_arbiter (
	input  logic    					aclk,    
	input  logic    					aresetn,

	// User logic
    metaIntf.s                          s_meta,
    metaIntf.m                          m_meta [N_REGIONS],

    // VFID
    output logic [N_REGIONS_BITS-1:0]   vfid
);

`ifdef MULT_REGIONS

logic ready_snk;
logic valid_snk;
rdma_ack_t req_snk;

logic [N_REGIONS-1:0] ready_src;
logic [N_REGIONS-1:0] valid_src;
rdma_ack_t [N_REGIONS-1:0] req_src;

metaIntf #(.STYPE(rdma_ack_t)) meta_que [N_REGIONS] ();

// --------------------------------------------------------------------------------
// -- I/O !!! interface
// --------------------------------------------------------------------------------
for(genvar i = 0; i < N_REGIONS; i++) begin
    assign meta_que[i].valid = valid_src[i];
    assign ready_src[i] = meta_que[i].ready;
    assign meta_que[i].data = req_src[i];   
end

assign valid_snk = s_meta.valid;
assign s_meta.ready = ready_snk;
assign req_snk = s_meta.data;

// --------------------------------------------------------------------------------
// -- Mux 
// --------------------------------------------------------------------------------
always_comb begin
    vfid = req_snk.vfid;

    for(int i = 0; i < N_REGIONS; i++) begin
        valid_src[i] = (vfid == i) ? valid_snk : 1'b0;
        req_src[i] = req_snk;
    end
    ready_snk = ready_src[vfid];
end

for(genvar i = 0; i < N_REGIONS; i++) begin
    axis_data_fifo_cnfg_rdma_40 inst_rx_queue (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(meta_que[i].valid),
        .s_axis_tready(meta_que[i].ready),
        .s_axis_tdata(meta_que[i].data),
        .m_axis_tvalid(m_meta[i].valid),
        .m_axis_tready(m_meta[i].ready),
        .m_axis_tdata(m_meta[i].data),
        .axis_wr_data_count()
    );
end

`else 

axis_data_fifo_cnfg_rdma_40 inst_rx_queue (
    .s_axis_aresetn(aresetn),
    .s_axis_aclk(aclk),
    .s_axis_tvalid(s_meta.valid),
    .s_axis_tready(s_meta.ready),
    .s_axis_tdata(s_meta.data),
    .m_axis_tvalid(m_meta[0].valid),
    .m_axis_tready(m_meta[0].ready),
    .m_axis_tdata(m_meta[0].data),
    .axis_wr_data_count()
);


`endif

endmodule