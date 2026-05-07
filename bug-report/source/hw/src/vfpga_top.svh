/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025-2026, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

reduce_ops_hls_ip inst_reduce_ops (
    .in0_TDATA    (axis_host_recv[0].tdata),
    .in0_TKEEP    (axis_host_recv[0].tkeep),
    .in0_TLAST    (axis_host_recv[0].tlast),
    .in0_TDEST    (8'd2),                       // hardwire to int32 add
    .in0_TVALID   (axis_host_recv[0].tvalid),
    .in0_TREADY   (axis_host_recv[0].tready),

    .in1_TDATA    (axis_host_recv[1].tdata),
    .in1_TKEEP    (axis_host_recv[1].tkeep),
    .in1_TLAST    (axis_host_recv[1].tlast),
    .in1_TDEST    (8'd2),                       // hardwire to int32 add
    .in1_TVALID   (axis_host_recv[1].tvalid),
    .in1_TREADY   (axis_host_recv[1].tready),

    .out_r_TDATA  (axis_host_send[0].tdata),
    .out_r_TKEEP  (axis_host_send[0].tkeep),
    .out_r_TLAST  (axis_host_send[0].tlast),
    .out_r_TDEST  (),
    .out_r_TVALID (axis_host_send[0].tvalid),
    .out_r_TREADY (axis_host_send[0].tready),

    .ap_clk       (aclk),
    .ap_rst_n     (aresetn)
);

// Second send stream is unused — tie off
always_comb axis_host_send[1].tie_off_m();

// Tie off unused control/memory interfaces
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();
always_comb notify.tie_off_m();
always_comb axi_ctrl.tie_off_s();

// Debug ILA
ila_reduce inst_ila_reduce (
    .clk    (aclk),

    // in0 (first operand from host)
    .probe0 (axis_host_recv[0].tvalid),  // 1
    .probe1 (axis_host_recv[0].tready),  // 1
    .probe2 (axis_host_recv[0].tlast),   // 1
    .probe3 (axis_host_recv[0].tdata),   // 512

    // in1 (second operand from host)
    .probe4 (axis_host_recv[1].tvalid),  // 1
    .probe5 (axis_host_recv[1].tready),  // 1
    .probe6 (axis_host_recv[1].tlast),   // 1
    .probe7 (axis_host_recv[1].tdata),   // 512

    // out (fp32 result to host)
    .probe8  (axis_host_send[0].tvalid), // 1
    .probe9  (axis_host_send[0].tready), // 1
    .probe10 (axis_host_send[0].tlast),  // 1
    .probe11 (axis_host_send[0].tdata)   // 512
);
