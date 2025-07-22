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

// HLS kernel for cosine similarity calculation
// Note, the suffix _hls_ip to identify HLS kernels, as explained in Example 2
cosine_similarity_hls_ip inst_similarity_calc(
    .s_axi_in1_TDATA        (axis_host_recv[0].tdata),
    .s_axi_in1_TKEEP        (axis_host_recv[0].tkeep),
    .s_axi_in1_TLAST        (axis_host_recv[0].tlast),
    .s_axi_in1_TSTRB        (0),
    .s_axi_in1_TVALID       (axis_host_recv[0].tvalid),
    .s_axi_in1_TREADY       (axis_host_recv[0].tready),

    .s_axi_in2_TDATA        (axis_host_recv[1].tdata),
    .s_axi_in2_TKEEP        (axis_host_recv[1].tkeep),
    .s_axi_in2_TLAST        (axis_host_recv[1].tlast),
    .s_axi_in2_TSTRB        (0),
    .s_axi_in2_TVALID       (axis_host_recv[1].tvalid),
    .s_axi_in2_TREADY       (axis_host_recv[1].tready),

    .m_axi_out_TDATA        (axis_host_send[0].tdata),
    .m_axi_out_TKEEP        (axis_host_send[0].tkeep),
    .m_axi_out_TLAST        (axis_host_send[0].tlast),
    .m_axi_out_TSTRB        (),
    .m_axi_out_TVALID       (axis_host_send[0].tvalid),
    .m_axi_out_TREADY       (axis_host_send[0].tready),

    .ap_clk                 (aclk),
    .ap_rst_n               (aresetn)
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
ila_similarity inst_ila_similarity (
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
