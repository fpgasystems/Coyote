
/**
 * VFPGA TOP
 *
 * Tie up all signals to the user kernels
 * Still to this day, interfaces are not supported by Vivado packager ...
 * This means verilog style port connections are needed.
 * 
 */

//
// RDMA base (READ + WRITE)
//
always_comb axi_ctrl.tie_off_s();
always_comb notify.tie_off_m();
always_comb cq_wr.tie_off_s();
always_comb cq_rd.tie_off_s();

// Mux receive and response packets
metaIntf #(.STYPE(req_t)) rq_wr_int ();
AXI4SR axis_rdma_sink ();

axis_mux_join inst_join (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_rq(rq_wr),
    .m_sq(rq_wr_int),
    .s_axis_recv(axis_rdma_recv[0]),
    .s_axis_resp(axis_rdma_resp[0]),
    .m_axis(axis_rdma_sink)
);

// Mux between host and card memories, write
mux_host_card_wr_rdma inst_mux_wr (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_rq(rq_wr_int),
    .m_sq(sq_wr),
    .s_axis(axis_rdma_sink),
    .m_axis_host(axis_host_send[0]),
    .m_axis_card(axis_card_send[0])
);

// Mux between host and card memories, read
mux_host_card_rd_rdma inst_mux_rd (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_rq(rq_rd),
    .m_sq(sq_rd),
    .s_axis_host(axis_host_resp[0]),
    .s_axis_card(axis_card_resp[0]),
    .m_axis(axis_rdma_send[0])
);