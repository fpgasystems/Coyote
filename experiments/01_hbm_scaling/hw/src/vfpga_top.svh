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

import lynxTypes::*;

// Data movement card memory => vFPGA => card memory
for (genvar i = 0; i < N_CARD_AXI; i++) begin
    perf_local inst_card_link (
        .axis_in    (axis_card_recv[i]),
        .axis_out   (axis_card_send[i]),
        .aclk       (aclk),
        .aresetn    (aresetn)
    );
end

// Tie-off unused signals to avoid synthesis problems
always_comb notify.tie_off_m();
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();
always_comb axi_ctrl.tie_off_s();

// Debug ILA
ila_perf_card inst_ila_perf_card (
    .clk(aclk),
    .probe0(axis_card_recv[0].tvalid),  // 1 bit
    .probe1(axis_card_recv[0].tready),  // 1 bit
    .probe2(axis_card_recv[0].tlast),   // 1 bit
    .probe3(axis_card_send[0].tvalid),  // 1 bit
    .probe4(axis_card_send[0].tready),  // 1 bit
    .probe5(axis_card_send[0].tlast)    // 1 bit
);
