import lynxTypes::*;

// In this example, the vFPGA is only reading data from host memory
// As a sanity check, we confirm that the streaming interface (EN_STRM) was enabled during compilation
`ifdef EN_STRM
// There is no back-pressure; so the stream can always receive data from the host
assign axis_host_recv[0].tready = 1'b1;

// Trigger an interrupt when the condition is met (data[0] == 73)
assign notify.valid = axis_host_recv[0].tvalid && axis_host_recv[0].tdata[31:0] == 32'd73;

// We assign the interrupt value to the first integer of the incoming stream
// Knowing that the interrupt is only ever triggered when data[0] == 73
// Then, it's also true that notify.data.value is equal to 73; which we can verify from software
// This little test can help us verify we get the correct value and not some random interrupt values
assign notify.data.value = 32'd73;

// Each interrupt is associated with a Coyote thread, corresponding to notify.data.pid
// By default, Coyote threads for a a single vFPGA have unique IDs: 0, 1, 2...etc.
// In this example, we assume one Coyote thread and one FPGA, so then, notify.data.pid = 0
// TODO: Extend this to multiple PIDs and extract the correct value from control interfaces
assign notify.data.pid = 6'd0;

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
`ifdef EN_STRM
ila_vfpga_interrupt ila_vfpga_interrupt_inst (
    .clk(aclk),
    .probe0(notify.valid),
    .probe1(notify.data.value),
    .probe2(axis_host_recv[0].tvalid),
    .probe3(axis_host_recv[0].tready),
    .probe4(axis_host_recv[0].tlast),
    .probe5(axis_host_recv[0].tdata)
);
`endif
