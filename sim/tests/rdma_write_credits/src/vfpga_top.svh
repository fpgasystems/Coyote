/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025, Systems Group, ETH Zurich
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

import lynxTypes::*;

// Test design for dreq_credits_wr, which holds each RDMA WRITE request until the request's payload
// is in the data queue: it counts the payload beats that arrive (xfer) and charges each request
// its beats.
//
// Every beat of host stream 0 is one request, in its low 64 bits: [31:0] its length in bytes, [63]
// tlast of the matching output. Once a request shows up, a generator plays its payload beats into
// xfer, one every other cycle, after those of the requests before it. Every request the module
// lets through is written back on host stream 0, one beat each: [31:0] its length, [32] set if its
// whole payload had arrived by then, [63] tlast.

localparam integer BEAT_BYTES = AXI_DATA_BITS / 8;

metaIntf #(.STYPE(dreq_t)) req_in (.aclk(aclk), .aresetn(aresetn));
metaIntf #(.STYPE(dreq_t)) req_out (.aclk(aclk), .aresetn(aresetn));
logic xfer;

dreq_credits_wr inst_credits (.aclk(aclk), .aresetn(aresetn), .s_req(req_in), .m_req(req_out), .xfer(xfer));

assign req_out.ready = 1'b1;

function automatic logic [31:0] beats(input logic [31:0] len);
    beats = (len + BEAT_BYTES - 1) / BEAT_BYTES;
endfunction

function automatic dreq_t cmd_req(input logic [63:0] c);
    cmd_req = '0;
    cmd_req.req_1.opcode = RC_RDMA_WRITE_ONLY;
    cmd_req.req_1.len = c[31:0];
    cmd_req.req_1.last = 1'b1;
endfunction

logic [63:0] cmd;
logic handshake;
logic seen;             // the current request's payload is already owed
logic phase;            // a payload beat every other cycle
logic [31:0] owed;      // payload beats still to play
logic [31:0] received;  // payload beats played so far
logic [31:0] charged;   // payload beats of the requests let through so far
logic ok;

logic out_ready;
logic out_valid;
logic [63:0] out_data;

assign cmd = axis_host_recv[0].tdata[63:0];

// Continuous assignments, not an always_comb with defaults, for what dreq_credits_wr reads: it
// drives its ready that way, and two such blocks reading each other's outputs wake each other up
// without end in xsim
assign req_in.valid = axis_host_recv[0].tvalid & out_ready;
assign req_in.data = cmd_req(cmd);
assign axis_host_recv[0].tready = req_in.ready;
assign handshake = req_in.valid & req_in.ready;

assign xfer = (owed != 0) & phase;
assign ok = received >= charged + beats(cmd[31:0]);

always_ff @(posedge aclk) begin
    if (!aresetn) begin
        seen <= 1'b0;
        phase <= 1'b0;
        owed <= '0;
        received <= '0;
        charged <= '0;
    end
    else begin
        phase <= ~phase;
        owed <= owed - xfer + ((axis_host_recv[0].tvalid & ~seen) ? beats(cmd[31:0]) : 0);
        received <= received + xfer;
        if (handshake) begin
            seen <= 1'b0;
            charged <= charged + beats(cmd[31:0]);
        end
        else if (axis_host_recv[0].tvalid) begin
            seen <= 1'b1;
        end
    end
end

queue_stream #(
    .QTYPE(logic [63:0]),
    .QDEPTH(32)
) inst_out_que (
    .aclk(aclk),
    .aresetn(aresetn),
    .val_snk(handshake),
    .rdy_snk(out_ready),
    .data_snk({cmd[63], 30'b0, ok, cmd[31:0]}),
    .val_src(out_valid),
    .rdy_src(axis_host_send[0].tready),
    .data_src(out_data)
);

assign axis_host_send[0].tvalid = out_valid;
assign axis_host_send[0].tdata = {{(AXI_DATA_BITS - 64){1'b0}}, out_data};
assign axis_host_send[0].tkeep = '1;
assign axis_host_send[0].tid = '0;
assign axis_host_send[0].tlast = out_data[63];

// Tie-off unused
always_comb notify.tie_off_m();
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();
always_comb axi_ctrl.tie_off_s();
