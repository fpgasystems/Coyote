/**
 * VFPGA TOP
 *
 * Tie up all signals to the user kernels
 * Still to this day, interfaces are not supported by Vivado packager ...
 * This means verilog style port connections are needed.
 * 
 */

//
// Instantiate top level
//

hllsketch_16x32 (
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

// Tie-off the rest of the interfaces
always_comb notify.tie_off_m();
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();

// ILA
ila_hll inst_ila_hll (
    .clk(aclk),
    .probe0(axis_host_recv[0].tvalid),
    .probe1(axis_host_recv[0].tready),
    .probe2(axis_host_recv[0].tlast),
    .probe3(axis_host_send[0].tvalid),
    .probe4(axis_host_send[0].tready),
    .probe5(axis_host_send[0].tlast),
    .probe6(axis_host_send[0].tdata[31:0])
);
