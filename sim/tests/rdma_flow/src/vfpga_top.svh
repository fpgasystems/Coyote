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

// Test design for rdma_flow, which keeps a ring of outstanding requests per QP (a WRITE ring and a
// READ ring), admits a request only while its ring has a free slot, and frees slots on ACKs.
//
// Every beat of host stream 0 is one command, in its low 64 bits:
//   [7:0] QP (pid), [8] READ (else WRITE), [9] ACK (else request), [10] tlast of the matching output
// A request goes to rdma_flow's s_req and an ACK to its s_ack. Every request rdma_flow admits is
// written back on host stream 0, one beat each: [7:0] QP, [8] READ, [23:16] the slot it was given
// (req_1.offs). Completions are dropped.

metaIntf #(.STYPE(dreq_t)) req_in (.aclk(aclk), .aresetn(aresetn));
metaIntf #(.STYPE(dreq_t)) req_out (.aclk(aclk), .aresetn(aresetn));
metaIntf #(.STYPE(dack_t)) ack_in (.aclk(aclk), .aresetn(aresetn));
metaIntf #(.STYPE(ack_t)) ack_out (.aclk(aclk), .aresetn(aresetn));

rdma_flow inst_flow (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_req(req_in),
    .m_req(req_out),
    .s_ack(ack_in),
    .m_ack(ack_out)
);

// The pointer table is block RAM, all zeros once the FPGA is configured, but undefined in
// simulation
initial begin
    for (int i = 0; i < 2**(1+N_REGIONS_BITS+PID_BITS); i++) inst_flow.inst_pntr_table.ram[i] = '0;
end

logic [63:0] cmd;
assign cmd = axis_host_recv[0].tdata[63:0];

// Continuous assignments, not an always_comb with defaults: rdma_flow drives its readies that way,
// and two such blocks reading each other's outputs wake each other up without end in xsim
function automatic dreq_t cmd_req(input logic [63:0] c);
    cmd_req = '0;
    cmd_req.req_1.opcode = c[8] ? RC_RDMA_READ_REQUEST : RC_RDMA_WRITE_ONLY;
    cmd_req.req_1.pid = c[0+:PID_BITS];
    cmd_req.req_1.len = AXI_DATA_BITS / 8;
    cmd_req.req_1.last = c[10];
endfunction

function automatic dack_t cmd_ack(input logic [63:0] c);
    cmd_ack = '0;
    cmd_ack.ack.opcode = c[8] ? RC_RDMA_READ_RESP_ONLY : RC_ACK;
    cmd_ack.ack.pid = c[0+:PID_BITS];
    cmd_ack.last = 1'b1;
endfunction

assign req_in.valid = axis_host_recv[0].tvalid & ~cmd[9];
assign req_in.data = cmd_req(cmd);
assign ack_in.valid = axis_host_recv[0].tvalid & cmd[9];
assign ack_in.data = cmd_ack(cmd);
assign axis_host_recv[0].tready = cmd[9] ? ack_in.ready : req_in.ready;

assign ack_out.ready = 1'b1;

assign axis_host_send[0].tvalid = req_out.valid;
assign req_out.ready = axis_host_send[0].tready;
assign axis_host_send[0].tdata = {
    {(AXI_DATA_BITS - 24){1'b0}},
    8'(req_out.data.req_1.offs),
    7'b0,
    is_opcode_rd_req(req_out.data.req_1.opcode),
    8'(req_out.data.req_1.pid)
};
assign axis_host_send[0].tkeep = '1;
assign axis_host_send[0].tid = '0;
assign axis_host_send[0].tlast = req_out.data.req_1.last;

// Tie-off unused
always_comb notify.tie_off_m();
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();
always_comb axi_ctrl.tie_off_s();
