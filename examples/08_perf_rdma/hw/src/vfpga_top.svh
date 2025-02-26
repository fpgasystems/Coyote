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

// Tie off unused interfaces
always_comb axi_ctrl.tie_off_s();
always_comb notify.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();

// ILA for debugging
ila_perf_rdma inst_ila_perf_rdma (
    .clk(aclk),
    .probe0(axis_host_recv[0].tvalid),      // 1
    .probe1(axis_host_recv[0].tready),      // 1
    .probe2(axis_host_recv[0].tlast),       // 1

    .probe3(axis_host_recv[1].tvalid),      // 1
    .probe4(axis_host_recv[1].tready),      // 1
    .probe5(axis_host_recv[1].tlast),       // 1

    .probe6(axis_host_send[0].tvalid),      // 1
    .probe7(axis_host_send[0].tready),      // 1
    .probe8(axis_host_send[0].tlast),       // 1

    .probe9(axis_host_send[1].tvalid),      // 1
    .probe10(axis_host_send[1].tready),     // 1
    .probe11(axis_host_send[1].tlast),      // 1

    .probe12(sq_wr.valid),                  // 1
    .probe13(sq_wr.ready),                  // 1
    .probe14(sq_wr.data),                   // 128
    .probe15(sq_rd.valid),                  // 1
    .probe16(sq_rd.ready),                  // 1
    .probe17(sq_rd.data),                   // 128
    .probe18(cq_rd.valid),                  // 1
    .probe19(cq_wr.valid)                   // 1
);
