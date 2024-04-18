/**
 * VFPGA TOP
 *
 * Tie up all signals to the user kernels
 * Still to this day, interfaces are not supported by Vivado packager ...
 * This means verilog style port connections are needed.
 * 
 */

AXI4SR axis_sink_int ();
AXI4SR axis_src_int ();

axisr_reg inst_reg_sink (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_host_recv[0]), .m_axis(axis_sink_int));
axisr_reg inst_reg_src (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_src_int), .m_axis(axis_host_send[0]));

localparam integer N_AES_PIPELINES = 4;

logic [127:0] key;
logic key_start;
logic key_done;

// Slave
aes_slave inst_slave (
    .aclk(aclk),
    .aresetn(aresetn),
    .axi_ctrl(axi_ctrl),
    .key_out(key),
    .keyStart(key_start)
);

// AES pipelines
aes_top #(
    .NPAR(N_AES_PIPELINES)
) inst_aes_top (
    .clk(aclk),
    .reset_n(aresetn),
    .stall(~axis_src_int.tready),
    .key_in(key),
    .keyVal_in(key_start),
    .keyVal_out(key_done),
    .last_in(axis_sink_int.tlast),
    .last_out(axis_src_int.tlast),
    .keep_in(axis_sink_int.tkeep),
    .keep_out(axis_src_int.tkeep),
    .id_in(axis_sink_int.tid),
    .id_out(axis_src_int.tid),
    .dVal_in(axis_sink_int.tvalid),
    .dVal_out(axis_src_int.tvalid),
    .data_in(axis_sink_int.tdata),
    .data_out(axis_src_int.tdata)
);

assign axis_sink_int.tready = axis_src_int.tready;

// Tie-off the rest of the interfaces
always_comb notify.tie_off_m();
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();

//
// DBG
//

