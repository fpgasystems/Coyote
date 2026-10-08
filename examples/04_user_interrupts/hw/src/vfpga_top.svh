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

// In this example, the vFPGA reads a buffer from host memory and turns every 512-bit beat into one interrupt
// Each beat is a notification descriptor written by the software:
//   - bits [31:0]:  interrupt value, propagated to the interrupt callback
//   - bits [63:32]: Coyote thread ID (ctid) the interrupt is sent to (only the lowest PID_BITS are used)
//   - bits [95:64]: if non-zero, the beat issues an interrupt, otherwise it is dropped
// A buffer with many descriptors therefore issues back-to-back interrupts, as fast as the shell accepts them
// As a sanity check, we confirm that the streaming interface (EN_STRM) was enabled during compilation
`ifdef EN_STRM
logic notify_valid;
irq_not_t notify_data;

// A beat is only accepted once the previous interrupt was handed over to the shell
assign axis_host_recv[0].tready = ~notify_valid | notify.ready;

always_ff @(posedge aclk) begin
    if (~aresetn) begin
        notify_valid <= 1'b0;
        notify_data <= '0;
    end
    else if (axis_host_recv[0].tready) begin
        notify_valid <= axis_host_recv[0].tvalid && axis_host_recv[0].tdata[95:64] != 32'd0;
        notify_data.value <= axis_host_recv[0].tdata[31:0];
        notify_data.pid <= axis_host_recv[0].tdata[32+:PID_BITS];
    end
end

assign notify.valid = notify_valid;
assign notify.data = notify_data;

// Since we are not writing any data, tie off the axis_host_signal
always_comb axis_host_send[0].tie_off_m();

`else
// Streaming interface disabled during compilation => do nothing
assign axis_host_recv[0].tready = 1'b1;
assign notify.valid = 1'b0;
assign notify.data.value = 32'd0;
assign notify.data.pid = 6'd0;
`endif

// Tie off unused signals
always_comb axi_ctrl.tie_off_s();
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();

// Debug ILA
ila_vfpga_interrupt ila_vfpga_interrupt_inst (
    .clk(aclk),
    .probe0(notify.valid),
    .probe1(notify.data.value),
    .probe2(axis_host_recv[0].tvalid),
    .probe3(axis_host_recv[0].tready),
    .probe4(axis_host_recv[0].tlast),
    .probe5(axis_host_recv[0].tdata),
    .probe6(notify.ready),
    .probe7(notify.data.pid)
);
