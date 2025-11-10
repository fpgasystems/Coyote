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
    metaIntf.m                          m_meta_user [N_REGIONS],
    metaIntf.m                          m_meta_host,

    // VFID
    output logic [N_REGIONS_BITS-1:0]   vfid
);

assign m_meta_host.valid = s_meta.valid;
assign m_meta_host.data  = s_meta.data;

`ifdef MULT_REGIONS

logic ready_snk;
logic valid_snk;
ack_t req_snk;

logic [N_REGIONS-1:0] ready_src;
logic [N_REGIONS-1:0] valid_src;
ack_t [N_REGIONS-1:0] req_src;

metaIntf #(.STYPE(ack_t)) meta_que [N_REGIONS] ();
metaIntf #(.STYPE(ack_t)) meta_que_out [N_REGIONS] ();

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
    axis_data_fifo_cnfg_rdma_32 inst_rx_queue (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(meta_que[i].valid),
        .s_axis_tready(meta_que[i].ready),
        .s_axis_tdata(meta_que[i].data),
        .m_axis_tvalid(m_meta_user[i].valid),
        .m_axis_tready(m_meta_user[i].ready),
        .m_axis_tdata(m_meta_user[i].data),
        .axis_wr_data_count()
    );
end

`else 

axis_data_fifo_cnfg_rdma_32 inst_rx_queue (
    .s_axis_aresetn(aresetn),
    .s_axis_aclk(aclk),
    .s_axis_tvalid(s_meta.valid),
    .s_axis_tready(s_meta.ready),
    .s_axis_tdata(s_meta.data),
    .m_axis_tvalid(m_meta_user[0].valid),
    .m_axis_tready(m_meta_user[0].ready),
    .m_axis_tdata(m_meta_user[0].data),
    .axis_wr_data_count()
);


`endif

endmodule