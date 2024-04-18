/**
 * VFPGA TOP
 *
 * Tie up all signals to the user kernels
 * Still to this day, interfaces are not supported by Vivado packager ...
 * This means verilog style port connections are needed.
 * 
 */

always_comb begin 
    // Write ops
    sq_wr.valid = rq_wr.valid;
    rq_wr.ready = sq_wr.ready;
    sq_wr.data = rq_wr.data;
    // OW
    sq_wr.data.strm = STRM_HOST;
    sq_wr.data.dest = is_opcode_rd_resp(rq_wr.data.opcode) ? 0 : 1;

    // Read ops
    sq_rd.valid = rq_rd.valid;
    rq_rd.ready = sq_rd.ready;
    sq_rd.data = rq_rd.data;
    // OW
    sq_rd.data.strm = STRM_HOST;
    sq_rd.data.dest = 1;
end

`AXISR_ASSIGN(axis_host_recv[0], axis_rreq_send[0])
`AXISR_ASSIGN(axis_rreq_recv[0], axis_host_send[0])
`AXISR_ASSIGN(axis_host_recv[1], axis_rrsp_send[0])
`AXISR_ASSIGN(axis_rrsp_recv[0], axis_host_send[1])

ila_0 inst_ila (
    .clk(aclk),
    .probe0(axis_host_recv[0].tvalid),
    .probe1(axis_host_recv[0].tready),
    .probe2(axis_host_recv[0].tlast),

    .probe3(axis_host_recv[1].tvalid),
    .probe4(axis_host_recv[1].tready),
    .probe5(axis_host_recv[1].tlast),

    .probe6(axis_host_send[0].tvalid),
    .probe7(axis_host_send[0].tready),
    .probe8(axis_host_send[0].tlast),

    .probe9(axis_host_send[1].tvalid),
    .probe10(axis_host_send[1].tready),
    .probe11(axis_host_send[1].tlast),

    .probe12(sq_wr.valid),
    .probe13(sq_wr.ready),
    .probe14(sq_wr.data), // 128
    .probe15(sq_rd.valid),
    .probe16(sq_rd.ready),
    .probe17(sq_rd.data), // 128
    .probe18(cq_rd.valid),
    .probe19(cq_wr.valid)
);

// Tie-off unused
always_comb axi_ctrl.tie_off_s();
always_comb notify.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();