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

/**
 * vFPGA Top Module for RDMA with Compression/Decompression
 *
 * This module extends the basic RDMA example (09_perf_rdma) by adding
 * compression and decompression engines on the data paths between the
 * host and the network stack.
 *
 * Data Flow Architecture:
 * 
 * Outgoing RDMA WRITEs (Host -> Network):
 *   axis_host_recv[0] -> COMPRESSION -> axis_rreq_send[0]
 *
 * Incoming RDMA READ RESPONSEs (Network -> Host):
 *   axis_rreq_recv[0] -> DECOMPRESSION -> axis_host_send[0]
 *
 * Outgoing RDMA READ RESPONSEs (Host -> Network):
 *   axis_host_recv[1] -> COMPRESSION -> axis_rrsp_send[0]
 *
 * Incoming RDMA WRITEs (Network -> Host):
 *   axis_rrsp_recv[0] -> DECOMPRESSION -> axis_host_send[1]
 *
 * The compression/decompression engines operate at 250 MHz on 512-bit
 * AXI streams, providing sufficient bandwidth for 100G RDMA traffic.
 */

// Internal AXI streams for compression/decompression
AXI4SR axis_comp_out_wr();      // Compressed output for RDMA writes
AXI4SR axis_decomp_out_rd();    // Decompressed output for RDMA read responses
AXI4SR axis_comp_out_rsp();     // Compressed output for RDMA responses
AXI4SR axis_decomp_out_rcv();   // Decompressed output for RDMA received writes

/*
 * CONTROL SIGNALS
 * 
 * rq_(wr|rd) are two more Coyote interfaces, which act as inputs to the user application
 * They corresponds to network write/read requests, set from the host software and driver
 * Here, they are used to set Coyote's generic send queues, previously discussed in Example 7.
 */
always_comb begin 
    // Write
    sq_wr.valid = rq_wr.valid;
    rq_wr.ready = sq_wr.ready;
    sq_wr.data = rq_wr.data;            // Data field holds information such as remote, virtual address, buffer length etc.
    sq_wr.data.strm = STRM_HOST;        // For RDMA, by definition data is always on the host
    sq_wr.data.dest = is_opcode_rd_resp(rq_wr.data.opcode) ? 0 : 1;

    // Reads
    sq_rd.valid = rq_rd.valid;
    rq_rd.ready = sq_rd.ready;
    sq_rd.data = rq_rd.data;           // Data field holds information such as remote, virtual address, buffer length etc.
    sq_rd.data.strm = STRM_HOST;       // For RDMA, by definition data is always on the host
    sq_rd.data.dest = 1;
end

/*
 * COMPRESSION/DECOMPRESSION ENGINES
 * 
 * Four engine instances handle the bidirectional data flow:
 * 1. Compression for outgoing RDMA WRITEs (host -> network)
 * 2. Decompression for incoming RDMA READ responses (network -> host)
 * 3. Compression for outgoing RDMA READ responses (host -> network)
 * 4. Decompression for incoming RDMA WRITEs (network -> host)
 */

// Engine 1: Compress outgoing RDMA WRITEs (from local host to network stack to remote node)
rdma_compression_engine inst_comp_wr (
    .aclk(aclk),
    .aresetn(aresetn),
    .axis_in(axis_host_recv[0]),
    .axis_out(axis_comp_out_wr)
);
`AXISR_ASSIGN(axis_comp_out_wr, axis_rreq_send[0])

// Engine 2: Decompress incoming RDMA READ RESPONSEs (from remote node to network stack to local host)
rdma_decompression_engine inst_decomp_rd (
    .aclk(aclk),
    .aresetn(aresetn),
    .axis_in(axis_rreq_recv[0]),
    .axis_out(axis_decomp_out_rd)
);
`AXISR_ASSIGN(axis_decomp_out_rd, axis_host_send[0])

// Engine 3: Compress outgoing RDMA READ RESPONSEs (from local host to network stack to remote node)
rdma_compression_engine inst_comp_rsp (
    .aclk(aclk),
    .aresetn(aresetn),
    .axis_in(axis_host_recv[1]),
    .axis_out(axis_comp_out_rsp)
);
`AXISR_ASSIGN(axis_comp_out_rsp, axis_rrsp_send[0])

// Engine 4: Decompress incoming RDMA WRITEs (from remote node to network stack to local host)
rdma_decompression_engine inst_decomp_rcv (
    .aclk(aclk),
    .aresetn(aresetn),
    .axis_in(axis_rrsp_recv[0]),
    .axis_out(axis_decomp_out_rcv)
);
`AXISR_ASSIGN(axis_decomp_out_rcv, axis_host_send[1])

// Tie off unused interfaces
always_comb axi_ctrl.tie_off_s();
always_comb notify.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();

// ILA for debugging - monitoring compression/decompression data flow
ila_rdma_compression inst_ila_rdma_compression (
    .clk(aclk),
    // Outgoing RDMA WRITE path (with compression)
    .probe0(axis_host_recv[0].tvalid),      // 1
    .probe1(axis_host_recv[0].tready),      // 1
    .probe2(axis_host_recv[0].tlast),       // 1
    .probe3(axis_comp_out_wr.tvalid),       // 1
    .probe4(axis_comp_out_wr.tready),       // 1
    .probe5(axis_comp_out_wr.tlast),        // 1

    // Incoming RDMA READ RESPONSE path (with decompression)
    .probe6(axis_rreq_recv[0].tvalid),      // 1
    .probe7(axis_rreq_recv[0].tready),      // 1
    .probe8(axis_rreq_recv[0].tlast),       // 1
    .probe9(axis_decomp_out_rd.tvalid),     // 1
    .probe10(axis_decomp_out_rd.tready),    // 1
    .probe11(axis_decomp_out_rd.tlast),     // 1

    // Outgoing RDMA READ RESPONSE path (with compression)
    .probe12(axis_host_recv[1].tvalid),     // 1
    .probe13(axis_host_recv[1].tready),     // 1
    .probe14(axis_host_recv[1].tlast),      // 1
    .probe15(axis_comp_out_rsp.tvalid),     // 1
    .probe16(axis_comp_out_rsp.tready),     // 1
    .probe17(axis_comp_out_rsp.tlast),      // 1

    // Incoming RDMA WRITE path (with decompression)
    .probe18(axis_rrsp_recv[0].tvalid),     // 1
    .probe19(axis_rrsp_recv[0].tready),     // 1
    .probe20(axis_rrsp_recv[0].tlast),      // 1
    .probe21(axis_decomp_out_rcv.tvalid),   // 1
    .probe22(axis_decomp_out_rcv.tready),   // 1
    .probe23(axis_decomp_out_rcv.tlast),    // 1

    // Control signals
    .probe24(sq_wr.valid),                  // 1
    .probe25(sq_wr.ready),                  // 1
    .probe26(sq_wr.data),                   // 128
    .probe27(sq_rd.valid),                  // 1
    .probe28(sq_rd.ready),                  // 1
    .probe29(sq_rd.data)                    // 128
);
