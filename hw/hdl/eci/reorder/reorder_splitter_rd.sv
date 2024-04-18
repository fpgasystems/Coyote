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

module reorder_splitter_rd (
    input  logic                                aclk,
    input  logic                                aresetn,

    input  logic [ECI_ADDR_BITS-1:0]                         axi_in_araddr,
    input  logic [7:0]                          axi_in_arlen,
    input  logic                                axi_in_arvalid,
    output logic                                axi_in_arready,
    
    output logic [1:0][ECI_ADDR_BITS-1:0]                    axi_out_araddr,
    output logic [1:0][7:0]                     axi_out_arlen,
    output logic [1:0]                          axi_out_arvalid,
    input  logic [1:0]                          axi_out_arready,

    metaIntf.m                                  mux_r
);

// Internal
logic [1:0][ECI_ADDR_BITS-1:0] araddr;
logic [1:0][7:0] arlen;
logic [1:0] arvalid;
logic [1:0] arready;

metaIntf #(.STYPE(logic[8+1-1:0])) mux_in ();

logic mib_even_odd;
logic stall;

always_comb begin
    araddr[0] = ~mib_even_odd ? axi_in_araddr : axi_in_araddr + 128;
    araddr[1] = mib_even_odd  ? axi_in_araddr : axi_in_araddr + 128;

    arlen[0] = ~mib_even_odd ? (axi_in_arlen >> 1) : (axi_in_arlen >> 1) - {{7{1'b0}}, {1{~axi_in_arlen[0]}}};
    arlen[1] = mib_even_odd  ? (axi_in_arlen >> 1) : (axi_in_arlen >> 1) - {{7{1'b0}}, {1{~axi_in_arlen[0]}}};

    if(axi_in_arlen == 0) begin
        arvalid[0] = ~stall & axi_in_arvalid & ~mib_even_odd;
        arvalid[1] = ~stall & axi_in_arvalid & mib_even_odd;
    end
    else begin
        arvalid[0] = ~stall & axi_in_arvalid;
        arvalid[1] = ~stall & axi_in_arvalid;
    end
end

// Output queues
for(genvar i = 0; i < 2; i++) begin
    axis_data_fifo_splitter_48 inst_queue_sequence_ar (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(arvalid[i]),
        .s_axis_tready(arready[i]),
        .s_axis_tdata({araddr[i], arlen[i]}),
        .m_axis_tvalid(axi_out_arvalid[i]),
        .m_axis_tready(axi_out_arready[i]),
        .m_axis_tdata({axi_out_araddr[i], axi_out_arlen[i]})
    );
end

// Sequence queue
axis_data_fifo_splitter_9 inst_queue_sequence_r (
    .s_axis_aresetn(aresetn),
    .s_axis_aclk(aclk),
    .s_axis_tvalid(mux_in.valid),
    .s_axis_tready(mux_in.ready),
    .s_axis_tuser(mux_in.data),
    .m_axis_tvalid(mux_r.valid),
    .m_axis_tready(mux_r.ready),
    .m_axis_tuser(mux_r.data)
);

// Even odd
assign mib_even_odd = ~(axi_in_araddr[7] ^ axi_in_araddr[12] ^ axi_in_araddr[20]);

// Stall
assign stall = ~arready[0] || ~arready[1] || ~mux_in.ready;

// Mux in
assign mux_in.valid = ~stall && axi_in_arvalid;
assign mux_in.data = {axi_in_arlen, mib_even_odd};

assign axi_in_arready = ~stall;

/*
ila_splitter_rd inst_ila_splitter_rd (
    .clk(aclk),
    .probe0(axi_in_arvalid),
    .probe1(axi_in_arready),
    .probe2(axi_in_araddr), // 40
    .probe3(axi_in_arlen), // 8
    .probe4(axi_out_araddr[0]), // 40
    .probe5(axi_out_araddr[1]), // 40
    .probe6(axi_out_arlen[0]), // 8
    .probe7(axi_out_arlen[1]), // 8
    .probe8(axi_out_arvalid[0]), 
    .probe9(axi_out_arvalid[1]),
    .probe10(axi_out_arready[0]), 
    .probe11(axi_out_arready[1]),
    .probe12(stall)
);
*/

endmodule