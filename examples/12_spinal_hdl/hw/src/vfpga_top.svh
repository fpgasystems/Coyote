/**
 * This file is part of Coyote <https://github.com/fpgasystems/Coyote>
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

vector_adder_spinal inst_vadd (
    .io_s_axis_in1_tdata    (axis_host_recv[0].tdata),
    .io_s_axis_in1_tkeep    (axis_host_recv[0].tkeep),
    .io_s_axis_in1_tlast    (axis_host_recv[0].tlast),
    .io_s_axis_in1_tvalid   (axis_host_recv[0].tvalid),
    .io_s_axis_in1_tready   (axis_host_recv[0].tready),

    .io_s_axis_in2_tdata    (axis_host_recv[1].tdata),
    .io_s_axis_in2_tkeep    (axis_host_recv[1].tkeep),
    .io_s_axis_in2_tlast    (axis_host_recv[1].tlast),
    .io_s_axis_in2_tvalid   (axis_host_recv[1].tvalid),
    .io_s_axis_in2_tready   (axis_host_recv[1].tready),

    .io_m_axis_out_tdata    (axis_host_send[0].tdata),
    .io_m_axis_out_tkeep    (axis_host_send[0].tkeep),
    .io_m_axis_out_tlast    (axis_host_send[0].tlast),
    .io_m_axis_out_tvalid   (axis_host_send[0].tvalid),
    .io_m_axis_out_tready   (axis_host_send[0].tready),

    .aclk                   (aclk),
    .aresetn                (aresetn)
);

// There are two host streams, for both incoming and outgoing signals
// The second outgoing is unused in this example, so tie it off
always_comb axis_host_send[1].tie_off_m();

// Tie-off unused signals to avoid synthesis problems
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();
always_comb notify.tie_off_m();
always_comb axi_ctrl.tie_off_s();

// Debug ILA
ila_vadd inst_ila_vadd (
    .clk(aclk),                             // clock   
 
    .probe0(axis_host_recv[0].tvalid),      // 1
    .probe1(axis_host_recv[0].tready),      // 1
    .probe2(axis_host_recv[0].tlast),       // 1
    .probe3(axis_host_recv[0].tdata),       // 512

    .probe4(axis_host_recv[1].tvalid),      // 1
    .probe5(axis_host_recv[1].tready),      // 1
    .probe6(axis_host_recv[1].tlast),       // 1
    .probe7(axis_host_send[1].tdata),       // 512

    .probe8(axis_host_send[0].tvalid),      // 1
    .probe9(axis_host_send[0].tready),      // 1
    .probe10(axis_host_send[0].tlast),      // 1
    .probe11(axis_host_send[0].tdata)       // 512
);
