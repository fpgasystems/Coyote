/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2026, Systems Group, ETH Zurich
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

// DENIM control vFPGA, plus a full RDMA endpoint.
//
// The impairment datapath lives in the shell's service layer, in series on the
// RX stream, so DENIM itself needs nothing from this application beyond the CSR
// window onto the rule table and the counters.
//
// The RDMA wiring below is here because the evaluation node has to be a real
// RDMA endpoint as well: DENIM impairs traffic on the way to its own node's
// RoCE stack, so the effect is only observable if that stack actually
// terminates the connection and reacts.
// Wiring copied from examples/09_perf_rdma so the two nodes present the same
// endpoint behaviour and only DENIM differs. The one deviation: 09 ties off
// axi_ctrl, which here belongs to denim_slv.
always_comb begin
    // Network write/read requests from the host become Coyote send queue entries
    sq_wr.valid = rq_wr.valid;
    rq_wr.ready = sq_wr.ready;
    sq_wr.data  = rq_wr.data;
    sq_wr.data.strm = STRM_HOST;        // For RDMA, data is always on the host
    sq_wr.data.dest = is_opcode_rd_resp(rq_wr.data.opcode) ? 0 : 1;

    sq_rd.valid = rq_rd.valid;
    rq_rd.ready = sq_rd.ready;
    sq_rd.data  = rq_rd.data;
    sq_rd.data.strm = STRM_HOST;
    sq_rd.data.dest = 1;
end

// Outgoing RDMA WRITEs (local host -> network stack -> remote node)
`AXISR_ASSIGN(axis_host_recv[0], axis_rreq_send[0])
// Incoming RDMA READ RESPONSEs (remote node -> network stack -> local host)
`AXISR_ASSIGN(axis_rreq_recv[0], axis_host_send[0])
// Outgoing RDMA READ RESPONSEs (local host -> network stack -> remote node)
`AXISR_ASSIGN(axis_host_recv[1], axis_rrsp_send[0])
// Incoming RDMA WRITEs (remote node -> network stack -> local host)
`AXISR_ASSIGN(axis_rrsp_recv[0], axis_host_send[1])

// No descriptors or interrupts, DENIM reports through its own counters.
always_comb notify.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();

denim_slv inst_denim_slv (
    .aclk(aclk),
    .aresetn(aresetn),
    .axi_ctrl(axi_ctrl),
    .denim_cnfg(denim_cnfg),
    .denim_stat(denim_stat)
);
