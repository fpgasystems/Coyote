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

always_comb begin 
    /*
     * CONTROL SIGNALS
     * 
     * rq_(wr|rd) are two more Coyote interfaces, which act as inputs to the user application.
     * They are driven by Coyote's RDMA stack in reaction to *incoming* network traffic.
     * Their meaning is:
     *   rq_wr - payload has arrived from the remote node and has to be placed in local memory.
     *           This covers incoming RDMA WRITEs/SENDs as well as the RDMA READ RESPONSEs that
     *           come back for a READ we issued ourselves.
     *   rq_rd - a remote RDMA READ REQUEST has arrived, so local payload has to be fetched in
     *           order to build the RDMA READ RESPONSE that answers it.
     * Here, they are used to set Coyote's generic hardware send queues, previously discussed in Example 7.
     * Note that rq_(wr|rd) only carry the *request*; the corresponding payload travels on the
     * axis_rreq_* / axis_rrsp_* streams that are wired up further below, and the dest field
     * chosen here selects which axis_host_(send|recv) stream the transfer is paired with.
     */
    // Write
    sq_wr.valid = rq_wr.valid;
    rq_wr.ready = sq_wr.ready;
    sq_wr.data = rq_wr.data;            // Data field holds information such as remote, virtual address, buffer length etc.
    sq_wr.data.strm = STRM_HOST;        // Marks the transfer as local and targets host memory; this example is built without card memory
    sq_wr.data.dest = is_opcode_rd_resp(rq_wr.data.opcode) ? 0 : 1;   // READ RESPONSEs to axis_host_send[0], WRITEs/SENDs to axis_host_send[1]

    // Reads
    sq_rd.valid = rq_rd.valid;
    rq_rd.ready = sq_rd.ready;
    sq_rd.data = rq_rd.data;           // Data field holds information such as remote, virtual address, buffer length etc.
    sq_rd.data.strm = STRM_HOST;       // Marks the transfer as local and targets host memory; this example is built without card memory
    sq_rd.data.dest = 1;               // READ RESPONSE payload is fetched on axis_host_recv[1]
end

/*
 * CONTROL SIGNALS FOR HOST-INITIATED OPERATIONS (not visible in this file)
 *
 * The block above only handles traffic that the *remote* node initiates. Operations that the
 * local host software starts - i.e. coyote_thread.invoke(REMOTE_RDMA_WRITE/READ, sg) - never
 * pass through the vFPGA's sq_(wr|rd) interfaces. They are written into Coyote's host send
 * queue and split up inside the shell, outside of the vFPGA.
 *   REMOTE_RDMA_WRITE - the shell issues the descriptor to the RDMA stack *and*, in parallel,
 *                       a local host-memory read. The payload of that read shows up in the
 *                       vFPGA on axis_host_recv[rdmaSg.local_dest] (default 0) and we are
 *                       expected to push it into axis_rreq_send below. This is why
 *                       axis_host_recv[0] has no matching sq_rd anywhere in this file.
 *   REMOTE_RDMA_READ  - only the descriptor goes to the RDMA stack. The requested data comes
 *                       back later as RDMA READ RESPONSEs, which the remote node's responder
 *                       logic sends and which we then handle here via rq_wr / axis_rreq_recv.
 * Consequently, the index of a stream tells you who started the transfer: index 0 belongs to
 * the requester side (we initiated), index 1 to the responder side (the remote node initiated).
 */

/*
 * DATA SIGNALS
 *
 * Naming convention, always seen from the vFPGA: 'recv' is a stream flowing *into* the user
 * logic, 'send' a stream flowing *out* of it. The prefix names the other endpoint: 'host' is
 * host memory reached via DMA, while 'rreq'/'rrsp' are the requester and responder sides of
 * the RDMA stack, i.e. towards the network and the remote node.
 */
// Data streams for outgoing RDMA WRITEs and SENDs (from local host to network stack to remote node)
`AXISR_ASSIGN(axis_host_recv[0], axis_rreq_send[0])

// Data streams for incoming RDMA READ RESPONSEs (from remote node to network stack to local host)
`AXISR_ASSIGN(axis_rreq_recv[0], axis_host_send[0])

// Data streams for outgoing RDMA READ RESPONSEs (from local host to network stack to remote node)
`AXISR_ASSIGN(axis_host_recv[1], axis_rrsp_send[0])

// Data streams for incoming RDMA WRITEs and SENDs (from remote node to network stack to local host)
`AXISR_ASSIGN(axis_rrsp_recv[0], axis_host_send[1])

// Tie off unused interfaces
always_comb axi_ctrl.tie_off_s();
always_comb notify.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();

// ILA for debugging
ila_perf_rdma inst_ila_perf_rdma (
    .clk(aclk),
    .probe0(axis_host_recv[0].tvalid),      // 1
    .probe1(axis_host_recv[0].tready),      // 1
    .probe2(axis_host_recv[0].tlast),       // 1

    .probe3(axis_host_recv[1].tvalid),      // 1
    .probe4(axis_host_recv[1].tready),      // 1
    .probe5(axis_host_recv[1].tlast),       // 1

    .probe6(axis_host_send[0].tvalid),      // 1
    .probe7(axis_host_send[0].tready),      // 1
    .probe8(axis_host_send[0].tlast),       // 1

    .probe9(axis_host_send[1].tvalid),      // 1
    .probe10(axis_host_send[1].tready),     // 1
    .probe11(axis_host_send[1].tlast),      // 1

    .probe12(sq_wr.valid),                  // 1
    .probe13(sq_wr.ready),                  // 1
    .probe14(sq_rd.valid),                  // 1
    .probe15(sq_rd.ready)                   // 1
);
