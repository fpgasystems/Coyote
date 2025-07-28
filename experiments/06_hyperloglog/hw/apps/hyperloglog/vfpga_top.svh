/*
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

// Instantiate HLS kernel module
// Note, the suffix _hls_ip to identify HLS kernels, as explained in the README of Example 2: HLS Vector Add
hllsketch_16x32_hls_ip inst_hll (
    .s_axis_host_sink_TDATA     (axis_host_recv[0].tdata),
    .s_axis_host_sink_TKEEP     (axis_host_recv[0].tkeep),
    .s_axis_host_sink_TLAST     (axis_host_recv[0].tlast),
    .s_axis_host_sink_TID       (axis_host_recv[0].tid),
    .s_axis_host_sink_TSTRB     (0),
    .s_axis_host_sink_TVALID    (axis_host_recv[0].tvalid),
    .s_axis_host_sink_TREADY    (axis_host_recv[0].tready),

    .m_axis_host_src_TDATA      (axis_host_send[0].tdata),
    .m_axis_host_src_TKEEP      (axis_host_send[0].tkeep),
    .m_axis_host_src_TLAST      (axis_host_send[0].tlast),
    .m_axis_host_src_TID        (axis_host_send[0].tid),
    .m_axis_host_src_TSTRB      (),
    .m_axis_host_src_TVALID     (axis_host_send[0].tvalid),
    .m_axis_host_src_TREADY     (axis_host_send[0].tready),

    .s_axi_control_ARADDR       (axi_ctrl.araddr),
    .s_axi_control_ARVALID      (axi_ctrl.arvalid),
    .s_axi_control_ARREADY      (axi_ctrl.arready),
    .s_axi_control_AWADDR       (axi_ctrl.awaddr),
    .s_axi_control_AWVALID      (axi_ctrl.awvalid),
    .s_axi_control_AWREADY      (axi_ctrl.awready),
    .s_axi_control_RDATA        (axi_ctrl.rdata),
    .s_axi_control_RRESP        (axi_ctrl.rresp),
    .s_axi_control_RVALID       (axi_ctrl.rvalid),
    .s_axi_control_RREADY       (axi_ctrl.rready),
    .s_axi_control_WDATA        (axi_ctrl.wdata),
    .s_axi_control_WSTRB        (axi_ctrl.wstrb),
    .s_axi_control_WVALID       (axi_ctrl.wvalid),
    .s_axi_control_WREADY       (axi_ctrl.wready),
    .s_axi_control_BRESP        (axi_ctrl.bresp),
    .s_axi_control_BVALID       (axi_ctrl.bvalid),
    .s_axi_control_BREADY       (axi_ctrl.bready),

    .ap_clk                     (aclk),
    .ap_rst_n                   (aresetn)
);

// Tie-off unused interfaces, to avoid synthesis errors
always_comb notify.tie_off_m();
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();

// Debug ILA
ila_hll inst_ila_hll (
    .clk(aclk), 
    .probe0(axis_host_recv[0].tvalid),          // 1
    .probe1(axis_host_recv[0].tready),          // 1
    .probe2(axis_host_recv[0].tlast),           // 1
    .probe3(axis_host_send[0].tvalid),          // 1
    .probe4(axis_host_send[0].tready),          // 1
    .probe5(axis_host_send[0].tlast),           // 1
    .probe6(axis_host_send[0].tdata[31:0])      // 32
);
