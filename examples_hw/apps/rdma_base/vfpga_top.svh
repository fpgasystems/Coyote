/**
 * VFPGA TOP
 *
 * Tie up all signals to the user kernels
 * Still to this day, interfaces are not supported by Vivado packager ...
 * This means verilog style port connections are needed.
 * 
 */

// CSR
logic [PID_BITS-1:0] mux_ctid; // go to card with this ctid

rdma_base_slv inst_rdma_base_slv (
    .aclk(aclk),
    .aresetn(aresetn),

    .axi_ctrl(axi_ctrl),

    .mux_ctid(mux_ctid)
);

mux_host_card_rd_rdma inst_mux_send (
    .aclk(aclk),
    .aresetn(aresetn),

    .mux_ctid(mux_ctid),
    .s_rq(rq_rd),
    .m_sq(sq_rd),

    .s_axis_host(axis_host_recv[0]),
    .s_axis_card(axis_card_recv[0]),
    .m_axis(axis_rdma_send[0])
);  

mux_host_card_wr_rdma inst_mux_recv (
    .aclk(aclk),
    .aresetn(aresetn),

    .mux_ctid(mux_ctid),
    .s_rq(rq_wr),
    .m_sq(sq_wr),

    .s_axis(axis_rdma_recv[0]),
    .m_axis_host(axis_host_send[0]),
    .m_axis_card(axis_card_send[0])
);

// Tie-off unused
always_comb notify.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();