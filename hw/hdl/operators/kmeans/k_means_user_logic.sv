`timescale 1ns / 1ps

import lynxTypes::*;
import kmeansTypes::*;

/**
 * User logic
 * 
 */
module design_user_logic_0 (
    // Clock and reset
    input  wire                 aclk,
    input  wire[0:0]            aresetn,

    // AXI4 control
    AXI4L.s                     axi_ctrl,

    // AXI4S
    AXI4S.m                     axis_src,
    AXI4S.s                     axis_sink
);

/* -- Tie-off unused interfaces and signals ----------------------------- */
//always_comb axi_ctrl.tie_off_s();
//always_comb axis_src.tie_off_m();
//always_comb axis_sink.tie_off_s();

/* -- USER LOGIC -------------------------------------------------------- */
// Reg input
AXI4S axis_sink_r ();
AXI4S axis_src_r ();
axis_reg_rtl inst_reg_sink (.aclk(aclk), .aresetn(aresetn), .axis_in(axis_sink), .axis_out(axis_sink_r));
axis_reg_rtl inst_reg_src (.aclk(aclk), .aresetn(aresetn), .axis_in(axis_src_r), .axis_out(axis_src));

logic start_operator;
logic um_done;
logic [63:0] data_set_size;
logic [NUM_CLUSTER_BITS:0] num_clusters;
logic [MAX_DEPTH_BITS:0] data_dim;
logic select;

AXI4S axis_tuple();
AXI4S axis_centroid();

// Slave
k_means_slave inst_slave (
    .aclk(aclk),
    .aresetn(aresetn),
    .axi_ctrl(axi_ctrl),
    .start_operator(start_operator),
    .um_done(um_done),
    .data_set_size(data_set_size),
    .num_clusters(num_clusters),
    .data_dim(data_dim),
    .select(select)
);

always_comb begin
    axis_tuple.tdata = axis_sink_r.tdata;
    axis_tuple.tkeep = axis_sink_r.tkeep;
    axis_tuple.tlast = axis_sink_r.tlast;
    axis_tuple.tvalid = select ? axis_sink_r.tvalid : 1'b0;
      
    axis_centroid.tdata = axis_sink_r.tdata;
    axis_centroid.tkeep = axis_sink_r.tkeep;
    axis_centroid.tlast = axis_sink_r.tlast;
    axis_centroid.tvalid = select ? 1'b0 : axis_sink_r.tvalid;
    
    axis_sink_r.tready = select ? axis_tuple.tready : axis_centroid.tready;
end

k_means_operator inst_top (
    .aclk(aclk),
    .aresetn(aresetn),
    .axis_tuple(axis_tuple),
    .axis_centroid(axis_centroid),
    .axis_output(axis_src_r),
    .start_operator(start_operator),
    .um_done(um_done),
    .data_set_size(data_set_size),
    .num_clusters(num_clusters),
    .data_dim(data_dim),
    .agg_div_debug_cnt(),
    .k_means_module_debug_cnt()
);

endmodule

