// nodbg variant of A04_user_interrupts — ILA (ila_vfpga_interrupt) removed
// Added stream[1] tie-offs for N_STRM_AXI=2 shell.

import lynxTypes::*;

// In this example, the vFPGA is only reading data from host memory
`ifdef EN_STRM
// There is no back-pressure; so the stream can always receive data from the host
assign axis_host_recv[0].tready = 1'b1;

// Trigger an interrupt when the condition is met (data[0] == 73)
assign notify.valid = axis_host_recv[0].tvalid && axis_host_recv[0].tdata[31:0] == 32'd73;

assign notify.data.value = 32'd73;
assign notify.data.pid = 6'd0;

// Since we are not writing any data, tie off the axis_host_signal
always_comb axis_host_send[0].tie_off_m();

`else
assign axis_host_recv[0].tready = 1'b1;
assign notify.valid = 1'b0;
assign notify.data.value = 32'd0;
assign notify.data.pid = 6'd0;
`endif

// Tie-off unused stream[1] (shell has N_STRM_AXI=2)
always_comb axis_host_recv[1].tie_off_s();
always_comb axis_host_send[1].tie_off_m();

// Tie off unused signals
always_comb axi_ctrl.tie_off_s();
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();

