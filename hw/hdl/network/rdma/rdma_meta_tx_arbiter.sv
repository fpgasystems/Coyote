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
 * @brief   RDMA TX meta arbitration
 *
 * Arbitration layer between all present user regions
 */
module rdma_meta_tx_arbiter (
	input  logic    					aclk,    
	input  logic    					aresetn,

	// User logic
    metaIntf.s                          s_meta [N_REGIONS],
    metaIntf.m                          m_meta,

    // ID
    output logic [N_REGIONS_BITS-1:0]   vfid
);

`ifdef MULT_REGIONS

logic [N_REGIONS-1:0] ready_snk;
logic [N_REGIONS-1:0] valid_snk;
rdma_req_t [N_REGIONS-1:0] req_snk;

logic ready_src;
logic valid_src;
rdma_req_t [N_REGIONS-1:0] req_src;

logic [N_REGIONS_BITS-1:0] rr_reg;

metaIntf #(.STYPE(rdma_req_t)) meta_que [N_REGIONS] ();

// -------------------------------------------------------------------------------- 
// I/O !!! interface 
// -------------------------------------------------------------------------------- 
for(genvar i = 0; i < N_REGIONS; i++) begin
    assign valid_snk[i] = meta_que[i].valid;
    assign meta_que[i].ready = ready_snk[i];
    assign req_snk[i] = meta_que[i].data;    
end

assign m_meta.valid = valid_src;
assign ready_src = m_meta.ready;
assign m_meta.data = req_src;

// -------------------------------------------------------------------------------- 
// RR 
// -------------------------------------------------------------------------------- 
always_ff @(posedge aclk) begin
	if(aresetn == 1'b0) begin
		rr_reg <= 0;
	end else begin
        if(valid_src & ready_src) begin 
            rr_reg <= rr_reg + 1;
            if(rr_reg >= N_REGIONS-1)
                rr_reg <= 0;
        end
	end
end

// DP
always_comb begin
    ready_snk = 0;
    valid_src = 1'b0;
    vfid = 0;
    
    for(int i = 0; i < N_REGIONS; i++) begin
        if(i+rr_reg >= N_REGIONS) begin
            if(valid_snk[i+rr_reg-N_REGIONS]) begin
                valid_src = valid_snk[i+rr_reg-N_REGIONS];
                vfid = i+rr_reg-N_REGIONS;
                break;
            end
        end
        else begin
            if(valid_snk[i+rr_reg]) begin
                valid_src = valid_snk[i+rr_reg];
                vfid = i+rr_reg;
                break;
            end
        end
    end

    ready_snk[vfid] = ready_src;
    req_src = req_snk[vfid];
end

for(genvar i = 0; i < N_REGIONS; i++) begin
    axis_data_fifo_cnfg_rdma_256 inst_tx_queue (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(s_meta[i].valid),
        .s_axis_tready(s_meta[i].ready),
        .s_axis_tdata(s_meta[i].data),
        .m_axis_tvalid(meta_que[i].valid),
        .m_axis_tready(meta_que[i].ready),
        .m_axis_tdata(meta_que[i].data),
        .axis_wr_data_count()
    );
end

`else

axis_data_fifo_cnfg_rdma_256 inst_tx_queue (
    .s_axis_aresetn(aresetn),
    .s_axis_aclk(aclk),
    .s_axis_tvalid(s_meta[0].valid),
    .s_axis_tready(s_meta[0].ready),
    .s_axis_tdata(s_meta[0].data),
    .m_axis_tvalid(m_meta.valid),
    .m_axis_tready(m_meta.ready),
    .m_axis_tdata(m_meta.data),
    .axis_wr_data_count()
);

`endif

endmodule