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

import eci_cmd_defs::*;

import lynxTypes::*;

module reorder_splitter_wr (
    input  logic                                aclk,
    input  logic                                aresetn,

    input  logic [ECI_ADDR_BITS-1:0]            axi_in_awaddr,
    input  logic [7:0]                          axi_in_awlen,
    output logic                                axi_in_awready,
    input  logic                                axi_in_awvalid,
    
    output logic [1:0][ECI_ADDR_BITS-1:0]       axi_out_awaddr,
    output logic [1:0][7:0]                     axi_out_awlen,
    input  logic [1:0]                          axi_out_awready,
    output logic [1:0]                          axi_out_awvalid,

    metaIntf.m                                  mux_w,
    metaIntf.m                                  mux_b
);

// Internal
logic [1:0][ECI_ADDR_BITS-1:0] awaddr;
logic [1:0][7:0] awlen;
logic [1:0] awvalid;
logic [1:0] awready;

metaIntf #(.STYPE(logic[8+1-1:0])) mux_in_w ();
metaIntf #(.STYPE(logic[8+1-1:0])) mux_in_b ();

logic mib_even_odd;
logic stall;

always_comb begin
    awaddr[0] = ~mib_even_odd ? axi_in_awaddr : axi_in_awaddr + 128;
    awaddr[1] = mib_even_odd  ? axi_in_awaddr : axi_in_awaddr + 128;

    awlen[0] = ~mib_even_odd ? (axi_in_awlen >> 1) : (axi_in_awlen >> 1) - {{7{1'b0}}, {1{~axi_in_awlen[0]}}};
    awlen[1] = mib_even_odd  ? (axi_in_awlen >> 1) : (axi_in_awlen >> 1) - {{7{1'b0}}, {1{~axi_in_awlen[0]}}};

    if(axi_in_awlen == 0) begin
        awvalid[0] = ~stall & axi_in_awvalid & ~mib_even_odd;
        awvalid[1] = ~stall & axi_in_awvalid & mib_even_odd;
    end
    else begin
        awvalid[0] = ~stall & axi_in_awvalid;
        awvalid[1] = ~stall & axi_in_awvalid;
    end
end

// Output queues
for(genvar i = 0; i < 2; i++) begin
    axis_data_fifo_splitter_48 inst_queue_sequence_aw (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(awvalid[i]),
        .s_axis_tready(awready[i]),
        .s_axis_tdata({awaddr[i], awlen[i]}),
        .m_axis_tvalid(axi_out_awvalid[i]),
        .m_axis_tready(axi_out_awready[i]),
        .m_axis_tdata({axi_out_awaddr[i], axi_out_awlen[i]})
    );
end

// Sequence queues
axis_data_fifo_splitter_9 inst_queue_sequence_b (
    .s_axis_aresetn(aresetn),
    .s_axis_aclk(aclk),
    .s_axis_tvalid(mux_in_b.valid),
    .s_axis_tready(mux_in_b.ready),
    .s_axis_tuser(mux_in_b.data),
    .m_axis_tvalid(mux_b.valid),
    .m_axis_tready(mux_b.ready),
    .m_axis_tuser(mux_b.data)
);

axis_data_fifo_splitter_9 inst_queue_sequence_w (
    .s_axis_aresetn(aresetn),
    .s_axis_aclk(aclk),
    .s_axis_tvalid(mux_in_w.valid),
    .s_axis_tready(mux_in_w.ready),
    .s_axis_tuser(mux_in_w.data),
    .m_axis_tvalid(mux_w.valid),
    .m_axis_tready(mux_w.ready),
    .m_axis_tuser(mux_w.data)
);

// Even odd
assign mib_even_odd = ~(axi_in_awaddr[7] ^ axi_in_awaddr[12] ^ axi_in_awaddr[20]);

// Stall
assign stall = ~awready[0] || ~awready[1] || ~mux_in_b.ready || ~mux_in_w.ready;

// Mux in
assign mux_in_b.valid = ~stall && axi_in_awvalid;
assign mux_in_b.data = {axi_in_awlen, mib_even_odd};

assign mux_in_w.valid = ~stall && axi_in_awvalid;
assign mux_in_w.data = {axi_in_awlen, mib_even_odd};

assign axi_in_awready = ~stall;

/*
ila_splitter_wr inst_ila_splitter_wr (
    .clk(aclk),
    .probe0(axi_in_awvalid),
    .probe1(axi_in_awready),
    .probe2(axi_in_awaddr), // 40
    .probe3(axi_in_awlen), // 8
    .probe4(axi_out_awaddr[0]), // 40
    .probe5(axi_out_awaddr[1]), // 40
    .probe6(axi_out_awlen[0]), // 8
    .probe7(axi_out_awlen[1]), // 8
    .probe8(axi_out_awvalid[0]), 
    .probe9(axi_out_awvalid[1]),
    .probe10(axi_out_awready[0]), 
    .probe11(axi_out_awready[1]),
    .probe12(stall)
);
*/

endmodule